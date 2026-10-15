SELECT
  检查项,
  期望,
  实际,
  CASE WHEN 期望 = 实际 THEN '通过' ELSE '不通过' END AS 结论,
  依据
FROM (
  -- 规模
  SELECT '明细行数' AS 检查项, 454466 AS 期望,
         (SELECT COUNT(*) FROM 订单明细) AS 实际,
         '数据字典：原始 472,481 − 无用户标识 18,015' AS 依据
  UNION ALL
  SELECT '字段数', 14,
         (SELECT COUNT(*) FROM information_schema.COLUMNS
           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = '订单明细'),
         '数据字典：14 列'
  UNION ALL
  SELECT '成交明细行数', 410752,
         (SELECT COUNT(*) FROM v_成交明细),
         '数据字典：订单状态「已完成」410,752'
  UNION ALL
  SELECT '成交订单数', 286823,
         (SELECT COUNT(*) FROM v_成交订单),
         '独立基线'
  UNION ALL
  SELECT '成交订单去重后一致（视图一行一订单）', 0,
         (SELECT COUNT(*) FROM v_成交订单) - (SELECT COUNT(DISTINCT 订单id) FROM v_成交明细),
         '口径自洽：v_成交订单 的行数应等于成交订单id 去重数'
  UNION ALL
  SELECT '订单级 GMV = 明细级 GMV', 0,
         (SELECT SUM(订单金额) FROM v_成交订单) - (SELECT SUM(明细金额) FROM v_成交明细),
         '口径自洽：订单金额由明细金额求和而来'

  -- 缺失与重复
  UNION ALL
  SELECT '用户id 缺失行数', 0,
         (SELECT COUNT(*) FROM 订单明细 WHERE 用户id IS NULL),
         '数据字典：清洗后全表零缺失'
  UNION ALL
  SELECT '完全重复行数', 0,
         (SELECT COUNT(*) FROM (
            SELECT 订单id, 店铺id, 日期, 订单状态, 流量渠道, 数量, 折扣率, 明细金额,
                   成本价快照, 用户id, 佣金率, 商品id, 商品成交单价, 总成本
            FROM 订单明细
            GROUP BY 订单id, 店铺id, 日期, 订单状态, 流量渠道, 数量, 折扣率, 明细金额,
                     成本价快照, 用户id, 佣金率, 商品id, 商品成交单价, 总成本
            HAVING COUNT(*) > 1) d),
         '数据字典：完全重复行 0'
  UNION ALL
  SELECT '订单id+商品id 重复组数', 0,
         (SELECT COUNT(*) FROM (
            SELECT 订单id, 商品id FROM 订单明细
            GROUP BY 订单id, 商品id HAVING COUNT(*) > 1) d),
         '数据字典：联合唯一（已由主键强制）'

  -- 字段间逻辑
  UNION ALL
  SELECT '总成本 = 成本价快照 × 数量 不成立行数', 0,
         (SELECT COUNT(*) FROM 订单明细
           WHERE ROUND(总成本, 2) <> ROUND(成本价快照 * 数量, 2)),
         '数据字典：472,481 行全部成立'
  UNION ALL
  SELECT '明细金额 = 单价 × 数量 × 折扣率 成立行数', 370957,
         (SELECT COUNT(*) FROM 订单明细
           WHERE 明细金额 = 商品成交单价 * 数量 * 折扣率),
         '独立基线：清洗后 370,957 行成立（占 81.62%），其余含未记录优惠'

  -- 归属关系
  UNION ALL
  SELECT '用户跨店铺数', 0,
         (SELECT COUNT(*) FROM (
            SELECT 用户id FROM 订单明细 GROUP BY 用户id HAVING COUNT(DISTINCT 店铺id) > 1) d),
         '数据字典：一个用户只出现在一个店铺内'
  UNION ALL
  SELECT '订单跨店铺数', 0,
         (SELECT COUNT(*) FROM (
            SELECT 订单id FROM 订单明细 GROUP BY 订单id HAVING COUNT(DISTINCT 店铺id) > 1) d),
         '数据字典：一个订单只对应一个店铺'
  UNION ALL
  SELECT '订单跨用户数', 0,
         (SELECT COUNT(*) FROM (
            SELECT 订单id FROM 订单明细 GROUP BY 订单id HAVING COUNT(DISTINCT 用户id) > 1) d),
         '数据字典：一个订单只对应一个用户（v_成交订单 取首行即无歧义的依据）'
  UNION ALL
  SELECT '订单跨渠道数', 0,
         (SELECT COUNT(*) FROM (
            SELECT 订单id FROM 订单明细 GROUP BY 订单id HAVING COUNT(DISTINCT 流量渠道) > 1) d),
         '独立基线：0，说明单个订单内的渠道唯一'

  -- 首单归属的歧义诊断
  -- 下面两项不检查「对不对」，而是把口径的模糊程度量出来：
  -- 首单当天有多笔订单时，「首单渠道 / 首单店铺」就不唯一。
  -- 店铺恒为 0（一个用户只属于一个店铺）；渠道有 173 人真的不唯一，
  -- 详见 sql/00_schema.sql 的 v_用户首单。
  UNION ALL
  SELECT '首单当日多笔订单的用户数', 307,
         (SELECT COUNT(*) FROM (
            SELECT o.用户id FROM v_成交订单 o
            JOIN (SELECT 用户id, MIN(下单日期) AS 首日 FROM v_成交订单 GROUP BY 用户id) f
              ON f.用户id = o.用户id AND f.首日 = o.下单日期
            GROUP BY o.用户id HAVING COUNT(*) > 1) d),
         '独立基线：首单归属是否唯一的诊断项'
  UNION ALL
  SELECT '首单当日渠道有歧义的用户数', 173,
         (SELECT COUNT(*) FROM (
            SELECT o.用户id FROM v_成交订单 o
            JOIN (SELECT 用户id, MIN(下单日期) AS 首日 FROM v_成交订单 GROUP BY 用户id) f
              ON f.用户id = o.用户id AND f.首日 = o.下单日期
            GROUP BY o.用户id HAVING COUNT(DISTINCT o.流量渠道) > 1) d),
         '独立基线：这 173 人的「首单渠道」不唯一，是选择而非事实'
  UNION ALL
  SELECT '首单当日店铺有歧义的用户数', 0,
         (SELECT COUNT(*) FROM (
            SELECT o.用户id FROM v_成交订单 o
            JOIN (SELECT 用户id, MIN(下单日期) AS 首日 FROM v_成交订单 GROUP BY 用户id) f
              ON f.用户id = o.用户id AND f.首日 = o.下单日期
            GROUP BY o.用户id HAVING COUNT(DISTINCT o.店铺id) > 1) d),
         '独立基线：0，店铺维度不存在歧义'

  -- 枚举与基数
  UNION ALL
  SELECT '订单状态取值数', 6,
         (SELECT COUNT(DISTINCT 订单状态) FROM 订单明细), '数据字典：6 个取值'
  UNION ALL
  SELECT '折扣率非 0/1 行数', 0,
         (SELECT COUNT(*) FROM 订单明细 WHERE 折扣率 NOT IN (0, 1)),
         '数据字典：折扣率实际只取 0/1，是折扣标记'
  UNION ALL
  SELECT '店铺数', 6, (SELECT COUNT(DISTINCT 店铺id) FROM 订单明细), '数据字典：6 个店铺'
  UNION ALL
  SELECT '商品数', 1320, (SELECT COUNT(DISTINCT 商品id) FROM 订单明细), '数据字典：1,320 个商品'
  UNION ALL
  SELECT '流量渠道数', 9, (SELECT COUNT(DISTINCT 流量渠道) FROM 订单明细), '数据字典：9 个渠道'
  UNION ALL
  SELECT '佣金率取值数', 12, (SELECT COUNT(DISTINCT 佣金率) FROM 订单明细), '数据字典：12 个取值'

  -- 数值范围
  UNION ALL
  SELECT '数量越界行数', 0,
         (SELECT COUNT(*) FROM 订单明细 WHERE 数量 < 1 OR 数量 > 18),
         '数据字典：数量 1 ~ 18'
  UNION ALL
  SELECT '明细金额越界行数', 0,
         (SELECT COUNT(*) FROM 订单明细 WHERE 明细金额 < 13 OR 明细金额 > 4156),
         '数据字典：明细金额 13 ~ 4156'
  UNION ALL
  SELECT '成本价快照越界行数', 0,
         (SELECT COUNT(*) FROM 订单明细 WHERE 成本价快照 < 13.13 OR 成本价快照 > 1323.09),
         '数据字典：成本价快照 13.13 ~ 1323.09'
  UNION ALL
  SELECT '佣金率越界行数', 0,
         (SELECT COUNT(*) FROM 订单明细 WHERE 佣金率 < 0.016 OR 佣金率 > 0.070),
         '数据字典：佣金率 1.6% ~ 7%'
  UNION ALL
  SELECT '金额非正行数', 0,
         (SELECT COUNT(*) FROM 订单明细
           WHERE 明细金额 <= 0 OR 成本价快照 <= 0 OR 总成本 <= 0),
         '数据字典：金额类字段无 0 值与负值'
) AS 检查
ORDER BY 结论 DESC, 检查项;