SELECT
  `用户id`,
  `店铺id`,
  `R`,
  `F`,
  `M`,
  `分层`,
  `人群`
FROM v_用户RFM
ORDER BY `用户id`;