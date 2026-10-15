SELECT
  `新客月份`,
  `流量渠道`,
  COUNT(*) AS `新客数`
FROM v_用户首单
GROUP BY `新客月份`, `流量渠道`
ORDER BY `新客月份`, `流量渠道`;