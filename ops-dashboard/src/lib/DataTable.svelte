<script>
  // columns: [{ key, label, fmt?, align? }]
  let { columns, rows, empty = 'No data in this range.' } = $props();
</script>

{#if rows.length === 0}
  <p class="empty">{empty}</p>
{:else}
  <table>
    <thead>
      <tr>
        {#each columns as c}<th class:r={c.align === 'right'}>{c.label}</th>{/each}
      </tr>
    </thead>
    <tbody>
      {#each rows as row}
        <tr>
          {#each columns as c}
            <td class:r={c.align === 'right'}>{c.fmt ? c.fmt(row[c.key], row) : (row[c.key] ?? '—')}</td>
          {/each}
        </tr>
      {/each}
    </tbody>
  </table>
{/if}

<style>
  table { width: 100%; border-collapse: collapse; font-size: 13px; }
  th { text-align: left; font-weight: 500; color: var(--text-3); font-size: 12px; padding: 6px 10px; border-bottom: 1px solid var(--border); position: sticky; top: 0; background: var(--surface); white-space: nowrap; }
  td { padding: 7px 10px; border-bottom: 1px solid var(--grid); white-space: nowrap; max-width: 280px; overflow: hidden; text-overflow: ellipsis; }
  .r { text-align: right; }
  .empty { color: var(--text-3); padding: 18px 0; }
</style>
