import { shortDate } from './fmt.js';

// Shared option builder: thin marks, recessive grid, surface-coloured gaps between stacked fills,
// legend whenever there are 2+ series, axis tooltip on hover.
export function timeChart(t, { dates, series, type = 'bar', stack = false, fmt, yFmt }) {
  const legend = series.length > 1;
  return {
    animation: false,
    color: [t.s1, t.s2, t.s3, t.s4],
    grid: { left: 8, right: 14, top: legend ? 34 : 12, bottom: 4, containLabel: true },
    legend: legend
      ? { top: 0, left: 0, icon: 'roundRect', itemWidth: 10, itemHeight: 10, itemGap: 16, textStyle: { color: t.text2 } }
      : undefined,
    tooltip: {
      trigger: 'axis',
      axisPointer: type === 'bar'
        ? { type: 'shadow', shadowStyle: { color: t.grid, opacity: 0.5 } }
        : { type: 'line', lineStyle: { color: t.neutral } },
      backgroundColor: t.surface,
      borderColor: t.border,
      textStyle: { color: t.text, fontSize: 12 },
      valueFormatter: fmt
    },
    xAxis: {
      type: 'category',
      data: dates.map(shortDate),
      axisLine: { lineStyle: { color: t.grid } },
      axisTick: { show: false },
      axisLabel: { color: t.text3, hideOverlap: true }
    },
    yAxis: {
      type: 'value',
      axisLabel: { color: t.text3, formatter: yFmt },
      splitLine: { lineStyle: { color: t.grid } }
    },
    series: series.map((s, i) => {
      const color = s.color ? t[s.color] : [t.s1, t.s2, t.s3, t.s4][i];
      if (type === 'line') {
        return {
          name: s.name, type: 'line', data: s.data, color, smooth: false,
          showSymbol: dates.length <= 45, symbolSize: 8,
          lineStyle: { width: 2 }, itemStyle: { color, borderColor: t.surface, borderWidth: 2 }
        };
      }
      const top = !stack || i === series.length - 1;
      return {
        name: s.name, type: 'bar', data: s.data, color, stack: stack ? 'total' : undefined, barMaxWidth: 18,
        itemStyle: {
          color,
          borderColor: t.surface,
          borderWidth: stack ? 1 : 0,
          borderRadius: top ? [4, 4, 0, 0] : 0
        }
      };
    })
  };
}
