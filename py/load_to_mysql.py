from __future__ import annotations

import os
import sys
from pathlib import Path

import pymysql
from pymysql.constants import CLIENT

ROOT = Path(__file__).resolve().parent.parent
CSV_PATH = ROOT / "data" / "订单表_clear.csv"
SCHEMA_SQL = ROOT / "sql" / "00_schema.sql"

CONN = dict(
    host=os.environ.get("MYSQL_HOST", "127.0.0.1"),
    port=int(os.environ.get("MYSQL_PORT", "3306")),
    user=os.environ.get("MYSQL_USER", "root"),
    password=os.environ.get("MYSQL_PASSWORD", "root"),
    database=os.environ.get("MYSQL_DB", "project2"),
    charset="utf8mb4",
    autocommit=True,
    #LOAD DATA LOCAL INFILE 需要客户端显式声明允许本地文件
    local_infile=True,
    client_flag=CLIENT.MULTI_STATEMENTS,
)

#CSV 列顺序,与 data/订单表_clear.csv 表头一致
COLUMNS = [
    "订单id", "店铺id", "日期", "订单状态", "流量渠道", "数量", "折扣率",
    "明细金额", "成本价快照", "用户id", "佣金率", "商品id", "商品成交单价", "总成本",
]
#期望装载行数 = 原始 472,481 行 − 无用户标识的 18,015 行
EXPECTED_ROWS = 454_466


def ensure_database() -> None:
    conn = pymysql.connect(**{k: v for k, v in CONN.items() if k != "database"})
    try:
        with conn.cursor() as cur:
            cur.execute(
                f"CREATE DATABASE IF NOT EXISTS `{CONN['database']}` "
                "DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci"
            )
    finally:
        conn.close()


def run_script(cursor, path: Path) -> None:
    cursor.execute(path.read_text(encoding="utf-8"))
    while cursor.nextset():
        pass


def main() -> int:
    if not CSV_PATH.exists():
        print(f"[X] 找不到 {CSV_PATH}", file=sys.stderr)
        print("    请先运行 py/data_cleaning.ipynb 生成该文件。", file=sys.stderr)
        return 1

    ensure_database()
    conn = pymysql.connect(**CONN)
    try:
        with conn.cursor() as cur:
            cur.execute("SET GLOBAL local_infile = 1")
            cur.execute("SELECT @@local_infile")
            print(f"[1/4] 服务端 local_infile = {cur.fetchone()[0]}")

            run_script(cur, SCHEMA_SQL)
            print(f"[2/4] 已执行 {SCHEMA_SQL.relative_to(ROOT)}（建表 + 4 个口径视图）")

            cur.execute("TRUNCATE TABLE 订单明细")
            cols = ", ".join(
                "@日期文本" if c == "日期" else f"`{c}`" for c in COLUMNS
            )
            infile = str(CSV_PATH).replace("\\", "/")
            cur.execute(
                f"""
                LOAD DATA LOCAL INFILE '{infile}'
                INTO TABLE 订单明细
                CHARACTER SET utf8mb4
                FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
                LINES TERMINATED BY '\\r\\n'
                IGNORE 1 LINES
                ({cols})
                SET `日期` = STR_TO_DATE(@日期文本, '%Y/%c/%e %H:%i')
                """
            )
            loaded = cur.rowcount
            print(f"[3/4] LOAD DATA 装载 {loaded:,} 行")

            #装载后校验：行数、日期解析、主键、金额
            cur.execute(
                """
                SELECT COUNT(*)                          AS 行数,
                    SUM(`日期` IS NULL)               AS 日期解析失败,
                    SUM(YEAR(`日期`) = 0)             AS 零日期,
                    COUNT(DISTINCT `订单id`)          AS 订单数,
                    COUNT(DISTINCT `用户id`)          AS 用户数,
                    MIN(`日期`)                       AS 最早,
                    MAX(`日期`)                       AS 最晚,
                    SUM(`明细金额`)                    AS 明细金额合计
                FROM 订单明细
                """
            )
            (rows, bad_dates, zero_dates, orders, users, dmin, dmax, gmv) = cur.fetchone()
            print("[4/4] 装载校验")
            print(f"      行数         {rows:,}（期望 {EXPECTED_ROWS:,}）")
            print(f"      日期解析失败  {bad_dates} / 零日期 {zero_dates}")
            print(f"      订单 / 用户   {orders:,} / {users:,}")
            print(f"      日期范围     {dmin} ~ {dmax}")
            print(f"      明细金额合计  {gmv:,} 元")

            if rows != EXPECTED_ROWS:
                print(f"[X] 行数不符：{rows:,} != {EXPECTED_ROWS:,}", file=sys.stderr)
                return 1
            if bad_dates or zero_dates:
                print(f"[X] 日期异常：NULL {bad_dates} 行、零日期 {zero_dates} 行", file=sys.stderr)
                return 1
    finally:
        conn.close()

    print("\n装载完成。下一步：python py/run_metrics.py")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())