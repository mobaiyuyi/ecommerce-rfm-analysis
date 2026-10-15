SELECT
  `分层`,
  `人群`,
  COUNT(*)                                                                 AS `用户数`,
  ROUND(CAST(COUNT(*) AS DECIMAL(30,12)) / SUM(COUNT(*)) OVER () * 100, 2) AS `用户占比%`,
  SUM(`M`)                                                                 AS `GMV`,
  ROUND(CAST(SUM(`M`) AS DECIMAL(30,12)) / SUM(SUM(`M`)) OVER () * 100, 2) AS `GMV占比%`,
  ROUND(CAST(SUM(`M`) AS DECIMAL(30,12)) / COUNT(*), 0)                    AS `人均GMV`,
  ROUND(CAST(SUM(`F`) AS DECIMAL(30,12)) / COUNT(*), 2)                    AS `平均F`,
  ROUND(CAST(SUM(`R`) AS DECIMAL(30,12)) / COUNT(*), 1)                    AS `平均R`
FROM v_用户RFM
GROUP BY `分层`, `人群`
ORDER BY `用户数` DESC;