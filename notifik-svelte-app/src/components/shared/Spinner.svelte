<script>
  let {
    size = 16,
    stroke = 2,
    color = "var(--color-blue)",
  } = $props();
</script>

<span
  class="ck-spinner"
  style="--ck-spinner-size:{size}px;--ck-spinner-stroke:{stroke}px;--ck-spinner-color:{color};"
  aria-hidden="true"
></span>

<style>
  .ck-spinner {
    display: inline-block;
    width: var(--ck-spinner-size, 16px);
    height: var(--ck-spinner-size, 16px);
    flex-shrink: 0;
    border-radius: 50%;
    border: var(--ck-spinner-stroke, 2px) solid
      color-mix(in srgb, var(--ck-spinner-color, var(--color-blue)) 25%, transparent);
    border-top-color: var(--ck-spinner-color, var(--color-blue));
    animation: ck-spin 0.7s linear infinite;
  }

  @keyframes ck-spin {
    to {
      transform: rotate(360deg);
    }
  }
</style>
