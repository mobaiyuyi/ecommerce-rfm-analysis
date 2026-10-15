SELECT DISTINCT
  `观察点`,
  `窗口起`,
  `窗口止`,
  2                        AS `F阈值`,
  ROUND(`R中位`, 1)         AS `R中位`,
  ROUND(`M中位`, 1)         AS `M中位`
FROM v_用户RFM;