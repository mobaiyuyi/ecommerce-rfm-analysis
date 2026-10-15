(function () {
  var style = getComputedStyle(document.documentElement);
  var accent = style.getPropertyValue('--accent').trim();
  var accent2 = style.getPropertyValue('--accent2').trim();
  var ink = style.getPropertyValue('--ink').trim();
  var muted = style.getPropertyValue('--muted').trim();
  var rule = style.getPropertyValue('--rule').trim();
  var bg = style.getPropertyValue('--bg').trim();

  // ===== 数据（RFM 八分层，按用户占比降序）=====
  var names = ['一般挽留客户', '一般发展客户', '重要挽留客户', '重要价值客户',
               '重要发展客户', '重要保持客户', '一般价值客户', '一般保持客户'];
  var userPct = [26.28, 19.98, 17.59, 14.40, 13.70, 4.40, 2.56, 1.11];
  var gmvPct = [7.76, 6.01, 23.24, 34.44, 18.13, 9.03, 0.97, 0.42];
  var arpu = [104, 106, 465, 841, 466, 722, 133, 132];

  var baseAxisLabel = { color: ink, fontSize: 12 };

  // ===== 图 1：用户占比 vs GMV 占比 =====
  var c1 = echarts.init(document.getElementById('chart-segment'), null, { renderer: 'svg' });
  c1.setOption({
    animation: false,
    grid: { left: 8, right: 56, top: 44, bottom: 8, containLabel: true },
    legend: { data: ['用户占比', 'GMV 占比'], top: 0, textStyle: { color: ink } },
    tooltip: {
      trigger: 'axis', appendToBody: true, axisPointer: { type: 'shadow' },
      valueFormatter: function (v) { return v + '%'; }
    },
    xAxis: {
      type: 'value',
      axisLine: { lineStyle: { color: rule } },
      axisLabel: { color: muted, formatter: '{value}%' },
      splitLine: { lineStyle: { color: rule } }
    },
    yAxis: {
      type: 'category', inverse: true, data: names,
      axisLine: { lineStyle: { color: rule } },
      axisLabel: baseAxisLabel,
      axisTick: { show: false }
    },
    series: [
      {
        name: '用户占比', type: 'bar', data: userPct, barWidth: 12,
        itemStyle: { color: accent },
        label: { show: true, position: 'right', color: muted, fontSize: 11, formatter: '{c}%' }
      },
      {
        name: 'GMV 占比', type: 'bar', data: gmvPct, barWidth: 12,
        itemStyle: { color: accent2 },
        label: { show: true, position: 'right', color: accent2, fontSize: 11, formatter: '{c}%' }
      }
    ]
  });
  window.addEventListener('resize', function () { c1.resize(); });

  // ===== 图 2：各分层人均 GMV（按值降序）=====
  var arpuPairs = names.map(function (n, i) { return [n, arpu[i]]; })
    .sort(function (a, b) { return b[1] - a[1]; });
  var arpuNames = arpuPairs.map(function (p) { return p[0]; });
  var arpuVals = arpuPairs.map(function (p) { return p[1]; });
  var maxArpu = arpuVals[0];

  var c2 = echarts.init(document.getElementById('chart-arpu'), null, { renderer: 'svg' });
  c2.setOption({
    animation: false,
    grid: { left: 8, right: 16, top: 24, bottom: 8, containLabel: true },
    tooltip: {
      trigger: 'axis', appendToBody: true, axisPointer: { type: 'shadow' },
      valueFormatter: function (v) { return v + ' 元'; }
    },
    xAxis: {
      type: 'category', data: arpuNames,
      axisLine: { lineStyle: { color: rule } },
      axisTick: { show: false },
      axisLabel: { color: ink, fontSize: 11, interval: 0, rotate: 20 }
    },
    yAxis: {
      type: 'value', name: '元', nameTextStyle: { color: muted },
      axisLine: { show: false }, axisLabel: { color: muted },
      splitLine: { lineStyle: { color: rule } }
    },
    series: [{
      type: 'bar', data: arpuVals, barWidth: 34,
      itemStyle: {
        color: function (p) { return p.value === maxArpu ? accent2 : accent; },
        borderRadius: [4, 4, 0, 0]
      },
      label: { show: true, position: 'top', color: ink, fontSize: 11, fontFamily: 'JetBrainsMono' }
    }]
  });
  window.addEventListener('resize', function () { c2.resize(); });

  // ===== 图 3：活跃 vs 沉睡用户 =====
  var active = 87547, dormant = 80813;
  var c3 = echarts.init(document.getElementById('chart-active'), null, { renderer: 'svg' });
  c3.setOption({
    animation: false,
    tooltip: {
      trigger: 'item', appendToBody: true,
      formatter: function (p) {
        return p.name + '：' + p.value.toLocaleString() + ' 人（' + p.percent + '%）';
      }
    },
    legend: { bottom: 0, textStyle: { color: ink } },
    series: [{
      type: 'pie', radius: ['52%', '76%'], center: ['50%', '44%'],
      avoidLabelOverlap: true,
      itemStyle: { borderColor: bg, borderWidth: 2 },
      label: {
        color: ink, fontSize: 12,
        formatter: function (p) {
          return p.name + '\n' + p.value.toLocaleString() + ' 人 · ' + p.percent + '%';
        }
      },
      labelLine: { lineStyle: { color: rule } },
      data: [
        { name: '活跃用户', value: active, itemStyle: { color: accent } },
        { name: '沉睡用户', value: dormant, itemStyle: { color: accent2 } }
      ]
    }]
  });
  window.addEventListener('resize', function () { c3.resize(); });

  // 容器尺寸变化时同步自适应（避免视口变化事件缺失时 SVG 固定宽度撑破页面）
  if (window.ResizeObserver) {
    var ro = new ResizeObserver(function () { c1.resize(); c2.resize(); c3.resize(); });
    ['chart-segment', 'chart-arpu', 'chart-active'].forEach(function (id) {
      ro.observe(document.getElementById(id));
    });
  }
})();
