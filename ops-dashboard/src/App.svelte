<script>
  import { onMount } from 'svelte';
  import Card from './lib/Card.svelte';
  import Chart from './lib/Chart.svelte';
  import DataTable from './lib/DataTable.svelte';
  import { timeChart } from './lib/charts.js';
  import { fetchOverview, fetchCustomerSync, setCustomerSyncMode } from './lib/api.js';
  import { num, inr, inrExact, usd, shortDate, dateTime, isoDate } from './lib/fmt.js';

  const today = () => new Date();
  const daysAgo = (n) => { const d = today(); d.setDate(d.getDate() - n); return d; };

  const params = new URLSearchParams(location.search);
  let from = $state(params.get('from') || isoDate(daysAgo(29)));
  let to = $state(params.get('to') || isoDate(today()));
  let data = $state(null);
  let loading = $state(true);
  let error = $state('');
  let controller;

  async function load() {
    controller?.abort();
    controller = new AbortController();
    loading = true;
    error = '';
    try {
      data = await fetchOverview(from, to, controller.signal);
      history.replaceState(null, '', `?from=${from}&to=${to}`);
    } catch (e) {
      if (e.name !== 'AbortError') error = e.message;
    } finally {
      loading = false;
    }
  }

  function preset(days) {
    from = isoDate(daysAgo(days - 1));
    to = isoDate(today());
    load();
  }

  let sync = $state(null);
  let syncError = $state('');
  let syncBusy = $state(false);

  async function loadSync() {
    try {
      sync = await fetchCustomerSync();
      syncError = '';
    } catch (e) {
      syncError = e.message;
    }
  }

  async function changeMode(mode) {
    const prompts = {
      killed: 'KILL all customer loading now? Running Shopify exports are cancelled and loading stops.',
      paused: 'Pause? No new exports start; loads already staged keep going.',
      running: 'Resume customer loading?'
    };
    if (!confirm(prompts[mode])) return;
    const reason = mode === 'running' ? null : prompt('Reason (optional)') || null;
    syncBusy = true;
    try {
      sync = await setCustomerSyncMode(mode, reason);
      syncError = '';
    } catch (e) {
      syncError = e.message;
    } finally {
      syncBusy = false;
    }
  }

  onMount(() => {
    load();
    loadSync();
    const timer = setInterval(loadSync, 20000);
    return () => clearInterval(timer);
  });

  const dates = $derived(data ? data.revenue.days.map((d) => d.date) : []);
  const activePreset = $derived(
    [7, 30, 90].find((n) => from === isoDate(daysAgo(n - 1)) && to === isoDate(today()))
  );

  const kpis = $derived.by(() => {
    if (!data) return [];
    const r = data.revenue.totals, s = data.subscriptions.totals, g = data.gmv.totals, a = data.active_subscriptions.latest, dc = data.dynamic_charges;
    return [
      { label: 'Net revenue', value: usd(r.net), sub: `Gross ${usd(r.gross)}` },
      { label: 'Usage charges', value: usd(r.usage), sub: 'AppUsageSale, net' },
      { label: 'Created by job', value: dc.tracking_since ? usd(dc.totals.amount, 2) : '—', sub: dc.tracking_since ? `${num(dc.totals.charges)} charges · DynamicChargeJob` : 'Tracking starts at next job run' },
      { label: 'Subscription revenue', value: usd(r.subscription), sub: 'AppSubscriptionSale, net' },
      { label: 'GMV via COD King', value: inr(g.gmv), sub: `${num(g.orders)} orders` },
      { label: 'Active subscriptions', value: a ? num(a.count) : '—', sub: a ? `${usd(a.mrr_usd)} MRR · ${shortDate(a.date)}` : 'No snapshot yet' },
      { label: 'Subscriptions', value: `+${num(s.bought)} / −${num(s.cancelled)}`, sub: `${usd(s.mrr_added)} added · ${usd(s.mrr_lost)} lost` },
      { label: 'Installs / uninstalls', value: `${num(s.installs)} / ${num(s.uninstalls)}`, sub: `${num(data.top_new_shops.total)} new shops still installed` },
      { label: 'Churn events', value: num(data.churn.total), sub: 'Uninstall, cancel, downgrade' }
    ];
  });

  const notices = $derived.by(() => {
    if (!data) return [];
    const out = [];
    const g = data.gmv;
    if (!g.coverage_from) out.push('GMV history is not loaded yet. The hourly rollup fills today and yesterday; run Ops::GmvBackfillJob for older days.');
    else if (g.coverage_from > data.range.from) out.push(`GMV is complete only from ${shortDate(g.coverage_from)} (history backfill still running). Earlier days show zero.`);
    if (g.unconverted.length) out.push(`GMV totals exclude currencies without an INR rate: ${g.unconverted.map((u) => `${u.currency} (${num(u.orders)} orders)`).join(', ')}. Add rates in OPS_FX_RATES.`);
    if (g.unparsed_orders) out.push(`${num(g.unparsed_orders)} orders had a missing or non-numeric amount and are counted in orders but not in GMV.`);
    const dcs = data.dynamic_charges.tracking_since;
    if (!dcs) out.push('Job-created usage charges are recorded from the first DynamicChargeJob run after this deploy. Nothing to show yet.');
    else if (dcs > data.range.from) out.push(`Job-created usage charges are tracked from ${shortDate(dcs)}; earlier days show zero (the job never stored them). Shopify's own figure is in the revenue chart.`);
    if (data.revenue.totals.gross === 0 && data.revenue.totals.net === 0) out.push('No partner sales in this range. They sync hourly from the Shopify Partner API.');
    return out;
  });

  const revenueChart = $derived((t) => timeChart(t, {
    dates,
    series: [
      { name: 'Usage', data: data.revenue.days.map((d) => d.usage) },
      { name: 'Subscription', data: data.revenue.days.map((d) => d.subscription) },
      { name: 'Adjustments / refunds', data: data.revenue.days.map((d) => d.adjustment), color: 'neutral' }
    ],
    stack: true, fmt: (v) => usd(v, 2), yFmt: (v) => usd(v)
  }));
  const subsChart = $derived((t) => timeChart(t, {
    dates,
    series: [
      { name: 'Bought', data: data.subscriptions.days.map((d) => d.bought) },
      { name: 'Cancelled', data: data.subscriptions.days.map((d) => d.cancelled) }
    ],
    fmt: (v) => num(v)
  }));
  const lifecycleChart = $derived((t) => timeChart(t, {
    dates,
    type: 'line',
    series: [
      { name: 'Installs', data: data.subscriptions.days.map((d) => d.installs) },
      { name: 'Uninstalls', data: data.subscriptions.days.map((d) => d.uninstalls) }
    ],
    fmt: (v) => num(v)
  }));
  const gmvChart = $derived((t) => timeChart(t, {
    dates,
    series: [
      { name: 'COD', data: data.gmv.days.map((d) => d.cod) },
      { name: 'Prepaid', data: data.gmv.days.map((d) => d.prepaid) }
    ],
    stack: true, fmt: (v) => inrExact(v), yFmt: (v) => inr(v)
  }));
  const activeChart = $derived((t) => timeChart(t, {
    dates: data.active_subscriptions.series.map((s) => s.date),
    type: 'line',
    series: [{ name: 'Active paid subscriptions', data: data.active_subscriptions.series.map((s) => s.count) }],
    fmt: (v) => num(v)
  }));

  const revenueCols = [
    { key: 'date', label: 'Date', fmt: shortDate },
    { key: 'usage', label: 'Usage', align: 'right', fmt: (v) => usd(v, 2) },
    { key: 'subscription', label: 'Subscription', align: 'right', fmt: (v) => usd(v, 2) },
    { key: 'adjustment', label: 'Adjustments', align: 'right', fmt: (v) => usd(v, 2) },
    { key: 'net', label: 'Net', align: 'right', fmt: (v) => usd(v, 2) }
  ];
  const subsCols = [
    { key: 'date', label: 'Date', fmt: shortDate },
    { key: 'bought', label: 'Bought', align: 'right', fmt: num },
    { key: 'cancelled', label: 'Cancelled', align: 'right', fmt: num },
    { key: 'mrr_added', label: 'MRR added', align: 'right', fmt: (v) => usd(v, 2) },
    { key: 'mrr_lost', label: 'MRR lost', align: 'right', fmt: (v) => usd(v, 2) },
    { key: 'installs', label: 'Installs', align: 'right', fmt: num },
    { key: 'uninstalls', label: 'Uninstalls', align: 'right', fmt: num }
  ];
  const gmvCols = [
    { key: 'date', label: 'Date', fmt: shortDate },
    { key: 'orders', label: 'Orders', align: 'right', fmt: num },
    { key: 'cod', label: 'COD', align: 'right', fmt: inrExact },
    { key: 'prepaid', label: 'Prepaid', align: 'right', fmt: inrExact },
    { key: 'gmv', label: 'Total', align: 'right', fmt: inrExact }
  ];
  const activeCols = [
    { key: 'date', label: 'Date', fmt: shortDate },
    { key: 'count', label: 'Active', align: 'right', fmt: num },
    { key: 'mrr_usd', label: 'MRR', align: 'right', fmt: (v) => usd(v, 2) }
  ];
  const newShopCols = [
    { key: 'domain', label: 'Shop' },
    { key: 'country', label: 'Country' },
    { key: 'plan', label: 'Plan' },
    { key: 'installed_at', label: 'Installed', fmt: dateTime },
    { key: 'orders', label: 'Orders', align: 'right', fmt: num },
    { key: 'net_revenue', label: 'Net revenue', align: 'right', fmt: (v) => usd(v, 2) }
  ];
  const churnCols = [
    { key: 'domain', label: 'Shop' },
    { key: 'type', label: 'Type' },
    { key: 'churned_at', label: 'When', fmt: dateTime },
    { key: 'plan', label: 'Plan' },
    { key: 'tenure_days', label: 'Tenure (d)', align: 'right', fmt: num },
    { key: 'orders', label: 'Orders', align: 'right', fmt: num },
    { key: 'last_30d_net', label: 'Last 30d net', align: 'right', fmt: (v) => usd(v, 2) },
    { key: 'ltv_net', label: 'LTV net', align: 'right', fmt: (v) => usd(v, 2) },
    { key: 'reason', label: 'Reason' }
  ];
  const bulkActiveCols = [
    { key: 'domain', label: 'Shop' },
    { key: 'status', label: 'Status' },
    { key: 'kind', label: 'Type' },
    { key: 'customers', label: 'Customers', align: 'right', fmt: (v) => (v == null ? '—' : num(v)) },
    { key: 'loaded', label: 'Loaded', align: 'right', fmt: num },
    { key: 'pct', label: '%', align: 'right', fmt: (v) => (v == null ? '—' : v + '%') },
    { key: 'failed_rows', label: 'Failed rows', align: 'right', fmt: num },
    { key: 'requested_at', label: 'Requested', fmt: dateTime }
  ];
  const bulkFailCols = [
    { key: 'domain', label: 'Shop' },
    { key: 'at', label: 'When', fmt: dateTime },
    { key: 'error', label: 'Error' }
  ];
  const bulkQueueCols = [
    { key: 'domain', label: 'Shop' },
    { key: 'unloaded', label: 'Unloaded', align: 'right', fmt: num },
    { key: 'shopify_customers', label: 'On Shopify', align: 'right', fmt: num },
    { key: 'loaded', label: 'Loaded', align: 'right', fmt: num },
    { key: 'status', label: 'Status' },
    { key: 'failures', label: 'Failures', align: 'right', fmt: num }
  ];
  const bulkRecentCols = [
    { key: 'domain', label: 'Shop' },
    { key: 'kind', label: 'Type' },
    { key: 'loaded', label: 'Customers', align: 'right', fmt: num },
    { key: 'failed_rows', label: 'Failed rows', align: 'right', fmt: num },
    { key: 'loaded_at', label: 'Loaded', fmt: dateTime }
  ];
  const bulkStatusOrder = ['requested', 'running', 'completed', 'loading', 'loaded', 'failed'];
  const dcChart = $derived((t) => timeChart(t, {
    dates,
    series: [
      { name: 'Created by DynamicChargeJob', data: data.dynamic_charges.days.map((d) => d.amount) },
      { name: 'Recorded by Shopify (gross usage)', data: data.revenue.days.map((d) => d.usage_gross) }
    ],
    fmt: (v) => usd(v, 2), yFmt: (v) => usd(v)
  }));
  const dcRows = $derived(
    data
      ? data.dynamic_charges.days.map((d, i) => {
          const shopify = data.revenue.days[i]?.usage_gross ?? 0;
          return { ...d, shopify, diff: Math.round((d.amount - shopify) * 100) / 100 };
        })
      : []
  );
  const dcCols = [
    { key: 'date', label: 'Date', fmt: shortDate },
    { key: 'amount', label: 'Created', align: 'right', fmt: (v) => usd(v, 2) },
    { key: 'shopify', label: 'Shopify gross', align: 'right', fmt: (v) => usd(v, 2) },
    { key: 'diff', label: 'Diff', align: 'right', fmt: (v) => usd(v, 2) },
    { key: 'charges', label: 'Charges', align: 'right', fmt: num },
    { key: 'failed_charges', label: 'Failed', align: 'right', fmt: num },
    { key: 'capped_shops', label: 'Capped', align: 'right', fmt: num },
    { key: 'sms', label: 'SMS', align: 'right', fmt: (v) => usd(v, 2) },
    { key: 'whatsapp', label: 'WA (MSG91)', align: 'right', fmt: (v) => usd(v, 2) },
    { key: 'whatsapp_bsp', label: 'WA (BSP)', align: 'right', fmt: (v) => usd(v, 2) },
    { key: 'preorder', label: 'Pre-order OTP', align: 'right', fmt: (v) => usd(v, 2) },
    { key: 'abandoned_sms', label: 'Abandoned SMS', align: 'right', fmt: (v) => usd(v, 2) },
    { key: 'abandoned_whatsapp', label: 'Abandoned WA', align: 'right', fmt: (v) => usd(v, 2) },
    { key: 'prepaid', label: 'Prepaid %', align: 'right', fmt: (v) => usd(v, 2) },
    { key: 'partial_payment', label: 'Partial pay', align: 'right', fmt: (v) => usd(v, 2) },
    { key: 'runs', label: 'Runs', align: 'right', fmt: num }
  ];
  const planRows = $derived(
    data?.active_subscriptions.latest
      ? Object.entries(data.active_subscriptions.latest.plans || {}).map(([plan, v]) => ({ plan, count: v.count, revenue: v.revenue }))
          .sort((a, b) => b.count - a.count)
      : []
  );
  const planCols = [
    { key: 'plan', label: 'Plan' },
    { key: 'count', label: 'Shops', align: 'right', fmt: num },
    { key: 'revenue', label: 'MRR', align: 'right', fmt: (v) => usd(v, 2) }
  ];
  const reasonMax = $derived(data ? Math.max(1, ...data.churn.reasons.map((r) => r.count)) : 1);
</script>

<main>
  <header class="top">
    <div>
      <h1>COD King Ops</h1>
      {#if data}<p class="muted">{shortDate(data.range.from)} – {shortDate(data.range.to)} · {data.range.days} days · IST</p>{/if}
    </div>
    <form class="range" onsubmit={(e) => { e.preventDefault(); load(); }}>
      <div class="seg" role="group" aria-label="Range presets">
        {#each [7, 30, 90] as n}
          <button type="button" class:on={activePreset === n} onclick={() => preset(n)}>{n}d</button>
        {/each}
      </div>
      <label>From <input type="date" bind:value={from} max={to} /></label>
      <label>To <input type="date" bind:value={to} min={from} max={isoDate(today())} /></label>
      <button class="apply" type="submit" disabled={loading}>{loading ? 'Loading…' : 'Apply'}</button>
    </form>
  </header>

  {#if error}
    <div class="banner err" role="alert">{error} <button onclick={load}>Retry</button></div>
  {/if}

  {#if !data && loading}
    <p class="muted pad">Loading…</p>
  {:else if data}
    {#each notices as n}<div class="banner">{n}</div>{/each}

    <div class="kpis" class:stale={loading}>
      {#each kpis as k}
        <div class="kpi">
          <span class="kl">{k.label}</span>
          <span class="kv">{k.value}</span>
          <span class="ks">{k.sub}</span>
        </div>
      {/each}
    </div>

    <div class="grid" class:stale={loading}>
      <div class="span2">
        <Card title="Revenue per day" note="Shopify Partner API, net of Shopify's share · USD">
          {#snippet chart()}<Chart build={revenueChart} label="Stacked bars of daily usage, subscription and adjustment revenue" />{/snippet}
          {#snippet table()}<DataTable columns={revenueCols} rows={data.revenue.days} />{/snippet}
        </Card>
      </div>

      <div class="span2">
        <Card title="Usage charges created by DynamicChargeJob" note="From our own ledger, written at the end of each job run · compared with what Shopify recorded the same day (gross, all usage sources) · USD · IST days">
          {#snippet chart()}<Chart build={dcChart} label="Daily usage charges created by the job versus recorded by Shopify" />{/snippet}
          {#snippet table()}<DataTable columns={dcCols} rows={dcRows} />{/snippet}
        </Card>
      </div>

      <Card title="Subscriptions bought vs cancelled" note={data.subscriptions.note}>
        {#snippet chart()}<Chart build={subsChart} height={240} label="Daily paid subscriptions bought and cancelled" />{/snippet}
        {#snippet table()}<DataTable columns={subsCols} rows={data.subscriptions.days} />{/snippet}
      </Card>

      <Card title="Installs vs uninstalls" note="Partner API app events">
        {#snippet chart()}<Chart build={lifecycleChart} height={240} label="Daily installs and uninstalls" />{/snippet}
        {#snippet table()}<DataTable columns={subsCols} rows={data.subscriptions.days} />{/snippet}
      </Card>

      <div class="span2">
        <Card title="GMV processed via COD King" note="Non-test orders, converted to INR at configured rates · day = IST">
          {#snippet chart()}<Chart build={gmvChart} label="Stacked bars of daily COD and prepaid GMV in rupees" />{/snippet}
          {#snippet table()}<DataTable columns={gmvCols} rows={data.gmv.days} />{/snippet}
        </Card>
      </div>

      <Card title="Active paid subscriptions" note="Daily snapshot from the subscription report">
        {#snippet chart()}
          {#if data.active_subscriptions.series.length}
            <Chart build={activeChart} height={220} label="Active paid subscriptions per day" />
          {:else}
            <p class="empty">No snapshots in this range yet. One is stored each time the daily subscription report (01:00 UTC) completes.</p>
          {/if}
        {/snippet}
        {#snippet table()}<DataTable columns={activeCols} rows={data.active_subscriptions.series} />{/snippet}
      </Card>

      <Card title="Plan mix" note={data.active_subscriptions.latest ? `Latest snapshot · ${shortDate(data.active_subscriptions.latest.date)}${data.active_subscriptions.latest.complete ? '' : ' · incomplete (missing shards)'}` : ''}>
        {#snippet chart()}<DataTable columns={planCols} rows={planRows} empty="No snapshot yet." />{/snippet}
      </Card>

      <div class="span2">
        <Card title="Top new shops" note={`${num(data.top_new_shops.total)} shops added in range, ranked by orders`}>
          {#snippet chart()}<div class="scroll"><DataTable columns={newShopCols} rows={data.top_new_shops.shops} /></div>{/snippet}
        </Card>
      </div>

      <Card title="Churn by type" note="Events in range">
        {#snippet chart()}<DataTable columns={[{ key: 'type', label: 'Type' }, { key: 'count', label: 'Events', align: 'right', fmt: num }]} rows={data.churn.by_type} />{/snippet}
      </Card>

      <Card title="Top uninstall reasons" note="From the exit survey">
        {#snippet chart()}
          {#if data.churn.reasons.length}
            <ul class="bars">
              {#each data.churn.reasons as r}
                <li><span class="bl">{r.reason}</span><span class="bt"><i style="width:{(r.count / reasonMax) * 100}%"></i></span><span class="bn">{num(r.count)}</span></li>
              {/each}
            </ul>
          {:else}<p class="empty">No reasons recorded in this range.</p>{/if}
        {/snippet}
      </Card>

      <div class="span2">
        <Card title="Top churned shops" note="Ranked by last-30-day net revenue lost, then orders">
          {#snippet chart()}<div class="scroll"><DataTable columns={churnCols} rows={data.churn.shops} /></div>{/snippet}
        </Card>
      </div>

      {#if sync || data.customer_bulk}
        <div class="span2">
          <Card title="Bulk customer import" note="One coordinator picks the shop with the most unloaded customers; Shopify builds the file, we load it throttled">
            {#snippet chart()}
              {@const b = sync || data.customer_bulk}
              <div class="chips">
                <span class="chip" class:ok={b.control.mode === 'running'} class:bad={b.control.mode === 'killed'} class:warn={b.control.mode === 'paused'}>
                  {b.control.mode === 'killed' ? 'KILLED' : b.control.mode === 'paused' ? 'PAUSED' : 'RUNNING'}
                </span>
                <span class="chip" class:ok={b.control.coordinator_alive} class:bad={!b.control.coordinator_alive}>
                  Coordinator {b.control.coordinator_alive ? `alive · ${b.control.coordinator_age_seconds}s ago` : 'not ticking'}
                </span>
                <span class="chip" class:ok={b.config.export_enabled} class:off={!b.config.export_enabled}>
                  Export {b.config.export_enabled ? 'on' : 'off'}
                </span>
                <span class="chip" class:ok={b.config.load_enabled} class:off={!b.config.load_enabled}>
                  Load {b.config.load_enabled ? (b.config.in_window_now ? 'on · in window' : 'on · outside window') : 'off'}
                </span>
                <span class="chip">Window {b.config.load_window} IST</span>
                <span class="chip">{b.config.batch} rows / {b.config.pause_ms} ms</span>
                {#if b.config.legacy_pull_enabled}<span class="chip bad">Legacy pull ON</span>{/if}
              </div>
              {#if sync}
                <div class="actions">
                  {#if sync.control.mode === 'running'}
                    <button type="button" disabled={syncBusy} onclick={() => changeMode('paused')}>Pause</button>
                    <button type="button" class="danger" disabled={syncBusy} onclick={() => changeMode('killed')}>Kill switch</button>
                  {:else}
                    <button type="button" disabled={syncBusy} onclick={() => changeMode('running')}>Resume</button>
                    {#if sync.control.mode === 'paused'}
                      <button type="button" class="danger" disabled={syncBusy} onclick={() => changeMode('killed')}>Kill switch</button>
                    {/if}
                    <span class="muted">{sync.control.reason || ''} {sync.control.changed_by ? `· ${sync.control.changed_by}` : ''}</span>
                  {/if}
                  {#if syncError}<span class="muted">{syncError}</span>{/if}
                </div>
              {/if}
              <div class="stats">
                <div><b>{num(b.totals.shopify_customers)}</b><span>customers on Shopify ({num(b.totals.shops_tracked)} shops)</span></div>
                <div><b>{num(b.totals.loaded_customers)}</b><span>loaded ({b.totals.loaded_pct}%)</span></div>
                <div><b>{num(b.totals.unloaded_customers)}</b><span>unloaded ({num(b.totals.shops_with_backlog)} shops waiting)</span></div>
                <div><b>{num(b.staged_rows_remaining)}</b><span>staged at Shopify files, not loaded</span></div>
                <div><b>{num(b.today.customers_loaded)}</b><span>loaded today ({num(b.today.shops_processed)} shops)</span></div>
                <div><b>{num(b.today.rows_failed)}</b><span>rows failed today</span></div>
                <div><b>{num(b.totals.shops_needing_attention)}</b><span>shops needing attention</span></div>
                {#if b.totals.shops_unreachable != null}<div><b>{num(b.totals.shops_unreachable)}</b><span>shops skipped (uninstalled or token revoked)</span></div>{/if}
              </div>
              <p class="muted statuses">
                {#each bulkStatusOrder.filter((k) => b.counts[k]) as k}<span>{k} {num(b.counts[k])}</span>{/each}
                {#if !Object.keys(b.counts).length}No exports yet.{/if}
              </p>
              <h3>In flight</h3>
              <div class="scroll"><DataTable columns={bulkActiveCols} rows={b.active} empty="Nothing in flight." /></div>
              <h3>Up next (most unloaded first)</h3>
              <div class="scroll"><DataTable columns={bulkQueueCols} rows={b.queue} empty="No shop has unloaded customers." /></div>
              <h3>Recently loaded</h3>
              <div class="scroll"><DataTable columns={bulkRecentCols} rows={b.recent_loaded} empty="Nothing loaded yet." /></div>
              {#if b.failures.length}
                <h3>Recent failures</h3>
                <div class="scroll"><DataTable columns={bulkFailCols} rows={b.failures} /></div>
              {/if}
            {/snippet}
          </Card>
        </div>
      {/if}
    </div>

    <p class="foot muted">Generated {new Date(data.generated_at).toLocaleString('en-IN')} · cached up to 5 min{data.gmv.rollup_updated_at ? ` · GMV rollup updated ${new Date(data.gmv.rollup_updated_at).toLocaleString('en-IN')}` : ''}</p>
  {/if}
</main>

<style>
  main { max-width: 1320px; margin: 0 auto; padding: 20px 16px 48px; }
  .top { display: flex; justify-content: space-between; align-items: flex-end; gap: 16px; flex-wrap: wrap; margin-bottom: 16px; }
  h1 { font-size: 20px; font-weight: 650; letter-spacing: -0.01em; }
  .muted { color: var(--text-3); font-size: 12px; }
  .chips { display: flex; gap: 8px; flex-wrap: wrap; margin-bottom: 12px; }
  .chip { font-size: 12px; padding: 3px 10px; border-radius: 999px; border: 1px solid var(--border); color: var(--text-2); background: var(--bg); }
  .chip.ok { color: var(--series-3); border-color: var(--series-3); }
  .chip.off { color: var(--text-3); }
  .chip.bad { color: #b42318; border-color: #b42318; }
  .chip.warn { color: #b54708; border-color: #b54708; }
  .actions { display: flex; gap: 8px; align-items: center; margin-bottom: 12px; }
  .actions button { border: 1px solid var(--border); background: var(--bg); border-radius: 6px; padding: 6px 12px; cursor: pointer; }
  .actions button.danger { color: #fff; background: #b42318; border-color: #b42318; }
  .actions button:disabled { opacity: 0.5; cursor: default; }
  .stats { display: grid; grid-template-columns: repeat(auto-fit, minmax(170px, 1fr)); gap: 12px; margin-bottom: 10px; }
  .stats div { display: flex; flex-direction: column; gap: 2px; }
  .stats b { font-size: 20px; font-weight: 650; font-variant-numeric: tabular-nums; }
  .stats span { color: var(--text-3); font-size: 12px; }
  .statuses { display: flex; gap: 12px; flex-wrap: wrap; margin-bottom: 12px; }
  h3 { font-size: 12px; font-weight: 600; color: var(--text-2); margin: 12px 0 6px; }
  .pad { padding: 40px 0; }
  .range { display: flex; gap: 10px; align-items: center; flex-wrap: wrap; }
  .range label { display: flex; align-items: center; gap: 6px; color: var(--text-2); font-size: 12px; }
  input[type='date'] { background: var(--surface); border: 1px solid var(--border); border-radius: 8px; padding: 5px 8px; color: var(--text); }
  .seg { display: inline-flex; border: 1px solid var(--border); border-radius: 8px; overflow: hidden; background: var(--surface); }
  .seg button { background: none; border: 0; padding: 6px 12px; cursor: pointer; color: var(--text-2); }
  .seg button.on { background: var(--bg); color: var(--text); font-weight: 600; }
  .apply { background: var(--series-1); color: #fff; border: 0; border-radius: 8px; padding: 6px 14px; cursor: pointer; font-weight: 600; }
  .apply:disabled { opacity: 0.6; cursor: default; }
  .banner { background: var(--warn-bg); color: var(--warn-text); border-radius: 8px; padding: 8px 12px; margin-bottom: 8px; font-size: 13px; }
  .banner.err button { margin-left: 8px; }
  .kpis { display: grid; grid-template-columns: repeat(auto-fill, minmax(190px, 1fr)); gap: 12px; margin: 14px 0; }
  .kpi { background: var(--surface); border: 1px solid var(--border); border-radius: 12px; padding: 12px 14px; display: flex; flex-direction: column; gap: 2px; min-width: 0; }
  .kl { color: var(--text-3); font-size: 12px; }
  .kv { font-size: 22px; font-weight: 650; letter-spacing: -0.01em; }
  .ks { color: var(--text-3); font-size: 12px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 12px; }
  .span2 { grid-column: span 2; min-width: 0; }
  .stale { opacity: 0.55; transition: opacity 0.15s; }
  .scroll { max-height: 420px; overflow: auto; }
  .empty { color: var(--text-3); padding: 18px 0; }
  .bars { list-style: none; margin: 0; padding: 0; display: grid; gap: 8px; }
  .bars li { display: grid; grid-template-columns: minmax(120px, 1.2fr) 2fr 36px; gap: 10px; align-items: center; font-size: 13px; }
  .bl { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .bt { background: var(--bg); border-radius: 4px; height: 8px; overflow: hidden; }
  .bt i { display: block; height: 100%; background: var(--series-1); border-radius: 4px; }
  .bn { text-align: right; color: var(--text-2); }
  .foot { margin-top: 16px; }
  @media (max-width: 860px) {
    .grid { grid-template-columns: minmax(0, 1fr); }
    .span2 { grid-column: auto; }
  }
</style>
