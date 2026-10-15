DROP VIEW  IF EXISTS v_用户首单;
DROP VIEW  IF EXISTS v_用户RFM;
DROP VIEW  IF EXISTS v_成交订单;
DROP VIEW  IF EXISTS v_成交明细;
DROP TABLE IF EXISTS 订单明细;

CREATE TABLE 订单明细 (
  `订单id`       VARCHAR(16)      NOT NULL COMMENT '订单唯一标识，O+7位序号',
  `店铺id`       VARCHAR(8)       NOT NULL COMMENT 'st001~st006',
  `日期`         DATE             NOT NULL COMMENT '下单日期（原值时刻均为 0:00，故用 DATE）',
  `订单状态`     VARCHAR(8)       NOT NULL COMMENT '已完成/已取消/已退款/已发货/待发货/待付款',
  `流量渠道`     VARCHAR(16)      NOT NULL COMMENT '9 个取值，见 doc/数据说明.md',
  `数量`         TINYINT UNSIGNED NOT NULL COMMENT '件，取值 1~18',
  `折扣率`       TINYINT          NOT NULL COMMENT '实际只取 0/1，是折扣标记而非折扣比例',
  `明细金额`     INT              NOT NULL COMMENT '元，该明细实际成交金额（金额一律以此为准）',
  `成本价快照`   DECIMAL(10,2)    NOT NULL COMMENT '元，下单时点的单位成本',
  `用户id`       VARCHAR(16)      NOT NULL COMMENT '前缀为平台代码 TM/DY/PDD/JD/WX/XHS',
  `佣金率`       DECIMAL(6,4)     NOT NULL COMMENT '0.052 = 5.2%',
  `商品id`       VARCHAR(16)      NOT NULL COMMENT 'p+7位序号',
  `商品成交单价` INT              NOT NULL COMMENT '元',
  `总成本`       DECIMAL(10,2)    NOT NULL COMMENT '= 成本价快照 × 数量',
  PRIMARY KEY (`订单id`, `商品id`),
  KEY idx_日期 (`日期`),
  KEY idx_用户id (`用户id`),
  KEY idx_状态_日期 (`订单状态`, `日期`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='订单商品明细（订单×商品）；主键=订单id+商品id，全表唯一';



-- 口径视图：成交明细

CREATE OR REPLACE VIEW v_成交明细 AS
SELECT * FROM 订单明细 WHERE `订单状态` = '已完成';



-- 口径视图：成交订单（订单级去重）

CREATE OR REPLACE VIEW v_成交订单 AS
SELECT `订单id`, `用户id`, `店铺id`, `流量渠道`, `下单日期`, `订单金额`
FROM (
  SELECT
    `订单id`,
    FIRST_VALUE(`用户id`)   OVER w                          AS `用户id`,
    FIRST_VALUE(`店铺id`)   OVER w                          AS `店铺id`,
    FIRST_VALUE(`流量渠道`) OVER w                          AS `流量渠道`,
    MIN(`日期`)             OVER (PARTITION BY `订单id`)     AS `下单日期`,
    SUM(`明细金额`)         OVER (PARTITION BY `订单id`)     AS `订单金额`,
    ROW_NUMBER()            OVER w                          AS rn
  FROM v_成交明细
  WINDOW w AS (PARTITION BY `订单id` ORDER BY `日期`, `商品id`)
) t
WHERE rn = 1;



-- 口径视图：用户 RFM 分层（近 12 个月窗口）

CREATE OR REPLACE VIEW v_用户RFM AS
WITH 窗口 AS (
  SELECT DATE('2026-06-30')                                            AS 观察点,
         DATE_SUB(DATE_FORMAT(DATE('2026-06-30'), '%Y-%m-01'),
                  INTERVAL 11 MONTH)                                   AS 窗口起,
         DATE('2026-06-30')                                            AS 窗口止
),
活跃 AS (
  -- 活跃用户 = 窗口内有成交的用户；R/F/M 全部按订单id 计（v_成交订单 已是订单粒度）
  SELECT
    o.`用户id`,
    -- 一个用户只出现在一个店铺内（见 sql/10_dq_校验结果.sql 的「用户跨店铺数」检查）
    MAX(o.`店铺id`)                       AS `店铺id`,
    -- 窗口 CTE 只有一行，用 MAX() 包住是为了满足 sql_mode=only_full_group_by
    DATEDIFF(MAX(w.`观察点`), MAX(o.`下单日期`)) AS `R`,
    COUNT(DISTINCT o.`订单id`)             AS `F`,
    SUM(o.`订单金额`)                      AS `M`,
    -- 把窗口参数一并带出来，供 sql/32 输出成「运行参数表」，便于事后核对用了哪个窗口
    MAX(w.`观察点`)                        AS `观察点`,
    MAX(w.`窗口起`)                        AS `窗口起`,
    MAX(w.`窗口止`)                        AS `窗口止`
  FROM v_成交订单 o
  CROSS JOIN 窗口 w
  WHERE o.`下单日期` BETWEEN w.`窗口起` AND w.`观察点`
  GROUP BY o.`用户id`
),
阈值 AS (
  SELECT
    (SELECT AVG(R) FROM (
        SELECT R, ROW_NUMBER() OVER (ORDER BY R) AS rn, COUNT(*) OVER () AS cnt FROM 活跃
     ) x WHERE x.rn IN (FLOOR((x.cnt + 1) / 2), CEIL((x.cnt + 1) / 2))) AS `R中位`,
    (SELECT AVG(M) FROM (
        SELECT M, ROW_NUMBER() OVER (ORDER BY M) AS rn, COUNT(*) OVER () AS cnt FROM 活跃
     ) y WHERE y.rn IN (FLOOR((y.cnt + 1) / 2), CEIL((y.cnt + 1) / 2))) AS `M中位`
),
分档 AS (
  SELECT
    a.*,
    t.`R中位`,
    t.`M中位`,
    CASE WHEN a.`R` <= t.`R中位` THEN '近' ELSE '远' END AS `R档`,
    CASE WHEN a.`F` >= 2          THEN '高' ELSE '低' END AS `F档`,
    CASE WHEN a.`M` >= t.`M中位` THEN '高' ELSE '低' END AS `M档`
  FROM 活跃 a CROSS JOIN 阈值 t
)
SELECT
  `用户id`, `店铺id`, `R`, `F`, `M`,
  CONCAT(`R档`, '-', `F档`, '-', `M档`) AS `分层`,
  CASE CONCAT(`R档`, '-', `F档`, '-', `M档`)
    WHEN '近-高-高' THEN '重要价值客户' WHEN '近-高-低' THEN '一般价值客户'
    WHEN '近-低-高' THEN '重要发展客户' WHEN '近-低-低' THEN '一般发展客户'
    WHEN '远-高-高' THEN '重要保持客户' WHEN '远-高-低' THEN '一般保持客户'
    WHEN '远-低-高' THEN '重要挽留客户' WHEN '远-低-低' THEN '一般挽留客户'
  END AS `人群`,
  `观察点`, `窗口起`, `窗口止`, `R中位`, `M中位`
FROM 分档;



-- 口径视图：用户首单（新客识别）

CREATE OR REPLACE VIEW v_用户首单 AS
SELECT
  `订单id`, `用户id`, `店铺id`, `流量渠道`, `下单日期`,
  DATE_FORMAT(`下单日期`, '%Y-%m') AS `新客月份`
FROM (
  SELECT o.*,
         ROW_NUMBER() OVER (PARTITION BY `用户id` ORDER BY `下单日期`, `订单id`) AS rn
  FROM v_成交订单 o
) t
WHERE rn = 1;