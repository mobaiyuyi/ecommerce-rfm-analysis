SELECT
  (SELECT COUNT(DISTINCT `用户id`) FROM v_成交订单) AS `成交用户数`,
  (SELECT COUNT(*) FROM v_用户RFM)                  AS `活跃用户数`,
  (SELECT COUNT(DISTINCT `用户id`) FROM v_成交订单)
    - (SELECT COUNT(*) FROM v_用户RFM)              AS `沉睡用户数`;