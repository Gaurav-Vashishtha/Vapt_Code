<script>
  import "../../styles/components/shared/SkeletonLoader.css";
  export let lines = 3;
  export let width = '100%';
  export let height = '20px';
</script>

<div class="skeleton-container">
  {#each Array(lines) as _, i}
    <div
      class="skeleton-line"
      style="width: {i === lines - 1 ? '80%' : width}; height: {height};"
    ></div>
  {/each}
</div>
