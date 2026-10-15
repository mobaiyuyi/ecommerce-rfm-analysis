SELECT
  `新客月份`,
  `店铺id`,
  COUNT(*) AS `新客数`
FROM v_用户首单
GROUP BY `新客月份`, `店铺id`
ORDER BY `新客月份`, `店铺id`;