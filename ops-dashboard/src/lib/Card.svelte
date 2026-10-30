<script>
  // A section card. When a `table` snippet is given, a Chart/Table toggle appears
  // so every chart has an accessible data view.
  let { title, note = '', chart, table = null, children = null } = $props();
  let view = $state('chart');
</script>

<section class="card">
  <header>
    <div>
      <h2>{title}</h2>
      {#if note}<p class="note">{note}</p>{/if}
    </div>
    {#if table}
      <div class="seg" role="group" aria-label="View">
        <button class:on={view === 'chart'} onclick={() => (view = 'chart')}>Chart</button>
        <button class:on={view === 'table'} onclick={() => (view = 'table')}>Table</button>
      </div>
    {/if}
  </header>
  {#if children}{@render children()}{/if}
  {#if view === 'table' && table}
    <div class="scroll">{@render table()}</div>
  {:else if chart}
    {@render chart()}
  {/if}
</section>

<style>
  .card { background: var(--surface); border: 1px solid var(--border); border-radius: 12px; padding: 16px 18px 18px; min-width: 0; }
  header { display: flex; justify-content: space-between; align-items: flex-start; gap: 12px; margin-bottom: 10px; }
  h2 { font-size: 14px; font-weight: 600; }
  .note { color: var(--text-3); font-size: 12px; margin-top: 2px; }
  .seg { display: inline-flex; border: 1px solid var(--border); border-radius: 8px; overflow: hidden; flex: none; }
  .seg button { background: none; border: 0; padding: 4px 10px; font-size: 12px; color: var(--text-2); cursor: pointer; }
  .seg button.on { background: var(--bg); color: var(--text); font-weight: 600; }
  .scroll { max-height: 320px; overflow: auto; }
</style>
