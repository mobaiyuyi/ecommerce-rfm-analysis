WITH 成交明细月 AS (
  SELECT `用户id`, DATE_FORMAT(`日期`, '%Y-%m') AS `月份`, `明细金额`
  FROM v_成交明细
),
新客数 AS (
  SELECT `新客月份`, COUNT(*) AS `新客数`
  FROM v_用户首单
  GROUP BY `新客月份`
),
新客GMV AS (
  -- 把每个用户的首购月份贴回他的成交明细，只保留「明细月份 = 首购月份」的行
  SELECT s.`新客月份`, SUM(d.`明细金额`) AS `新客GMV`
  FROM v_用户首单 s
  JOIN 成交明细月 d
    ON d.`用户id` = s.`用户id` AND d.`月份` = s.`新客月份`
  GROUP BY s.`新客月份`
),
全平台GMV AS (
  SELECT `月份` AS `新客月份`, SUM(`明细金额`) AS `全平台GMV`
  FROM 成交明细月
  GROUP BY `月份`
)
SELECT
  k.`新客月份`,
  k.`新客数`,
  g.`新客GMV`,
  p.`全平台GMV`,
  ROUND(CAST(g.`新客GMV` AS DECIMAL(30,12)) / k.`新客数`, 2)          AS `新客人均GMV`,
  ROUND(CAST(g.`新客GMV` AS DECIMAL(30,12)) / p.`全平台GMV` * 100, 2) AS `新客GMV贡献占比%`
FROM 新客数 k
JOIN 新客GMV g ON g.`新客月份` = k.`新客月份`
JOIN 全平台GMV p ON p.`新客月份` = k.`新客月份`
ORDER BY k.`新客月份`;