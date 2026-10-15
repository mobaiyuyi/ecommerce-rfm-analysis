from __future__ import annotations

import os
import re
import sys
from pathlib import Path

import pandas as pd
import pymysql

ROOT = Path(__file__).resolve().parent.parent
SQL_DIR = ROOT / "sql"
OUT_DIR = ROOT / "data" / "metrics"

OUTPUT_DIRECTIVE = re.compile(r"^--\s*@输出:\s*(\S+)\s*$", re.MULTILINE)

CONN = dict(
    host=os.environ.get("MYSQL_HOST", "127.0.0.1"),
    port=int(os.environ.get("MYSQL_PORT", "3306")),
    user=os.environ.get("MYSQL_USER", "root"),
    password=os.environ.get("MYSQL_PASSWORD", "root"),
    database=os.environ.get("MYSQL_DB", "project2"),
    charset="utf8mb4",
    autocommit=True,
)


def output_name(sql_text: str) -> str | None:
    m = OUTPUT_DIRECTIVE.search(sql_text)
    return m.group(1) if m else None


def run_and_fetch_last(cursor, sql_text: str):
    cursor.execute(sql_text)
    columns, rows = None, None
    while True:
        if cursor.description is not None:
            columns = [d[0] for d in cursor.description]
            rows = cursor.fetchall()
        if not cursor.nextset():
            break
    return columns, rows


def main() -> int:
    sql_files = sorted(SQL_DIR.glob("*.sql"))
    if not sql_files:
        print(f"[X] {SQL_DIR} 下没有 .sql 文件", file=sys.stderr)
        return 1

    conn = pymysql.connect(**CONN)
    try:
        with conn.cursor() as cur:
            try:
                cur.execute("SELECT COUNT(*) FROM 订单明细")
            except pymysql.err.ProgrammingError as exc:
                print(f"[X] 读不到表「订单明细」：{exc}", file=sys.stderr)
                return 1
            total = cur.fetchone()[0]
            print(f"订单明细：{total:,} 行\n")
            OUT_DIR.mkdir(parents=True, exist_ok=True)
            results, skipped = [], []

            for path in sql_files:
                text = path.read_text(encoding="utf-8")
                name = output_name(text)
                rel = path.relative_to(ROOT)

                if name is None:
                    skipped.append(rel)
                    continue

                columns, rows = run_and_fetch_last(cur, text)
                if not columns:
                    print(f"[X] {rel} 声明了输出「{name}」但没有返回结果集", file=sys.stderr)
                    return 1

                df = pd.DataFrame(rows, columns=columns)
                df.to_csv(out_path, index=False, encoding="utf-8-sig")
                results.append((name, df.shape, out_path))
                print(f"  [OK] {rel.name:<28} -> {out_path.name:<24} {df.shape[0]:>6} 行 × {df.shape[1]} 列")

            print()
            if skipped:
                print("跳过")
                for rel in skipped:
                    print(f"  - {rel}")
                print()

            print(f"共导出 {len(results)} 张结果表到 {OUT_DIR.relative_to(ROOT)}")
    finally:
        conn.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())