<script>
  import { onMount } from 'svelte';
  import * as echarts from 'echarts/core';
  import { BarChart, LineChart } from 'echarts/charts';
  import { GridComponent, TooltipComponent, LegendComponent } from 'echarts/components';
  import { CanvasRenderer } from 'echarts/renderers';

  echarts.use([BarChart, LineChart, GridComponent, TooltipComponent, LegendComponent, CanvasRenderer]);

  // build(tokens) -> echarts option. Colours come from CSS variables so light/dark stay in one place.
  let { build, height = 260, label = '' } = $props();
  let el;
  let chart;

  function tokens() {
    const cs = getComputedStyle(document.documentElement);
    const g = (n) => cs.getPropertyValue(n).trim();
    return {
      text: g('--text'), text2: g('--text-2'), text3: g('--text-3'), grid: g('--grid'), surface: g('--surface'),
      border: g('--border'), neutral: g('--neutral'),
      s1: g('--series-1'), s2: g('--series-2'), s3: g('--series-3'), s4: g('--series-4')
    };
  }

  function render() {
    if (chart) chart.setOption(build(tokens()), true);
  }

  onMount(() => {
    chart = echarts.init(el, null, { renderer: 'canvas' });
    render();
    const ro = new ResizeObserver(() => chart.resize());
    ro.observe(el);
    const mq = window.matchMedia('(prefers-color-scheme: dark)');
    mq.addEventListener('change', render);
    return () => {
      ro.disconnect();
      mq.removeEventListener('change', render);
      chart.dispose();
    };
  });

  $effect(() => {
    build; // re-render when data/closure changes
    render();
  });
</script>

<div bind:this={el} style="height:{height}px;width:100%" role="img" aria-label={label}></div>
