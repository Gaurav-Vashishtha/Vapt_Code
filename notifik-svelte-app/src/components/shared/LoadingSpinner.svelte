<script>
  import "../../styles/components/shared/LoadingSpinner.css";
  export let text = '';
  export let size = 'medium';
  export let fullScreen = false;
</script>

<div class="spinner-container" class:full-screen={fullScreen}>
  <div class="spinner" class:small={size === 'small'} class:large={size === 'large'}>
    <div class="spinner-ring"></div>
  </div>
  {#if text}
    <p class="spinner-text">{text}</p>
  {/if}
</div>
