#!/usr/bin/env python3
"""yazi 预览器（经 piper 插件调用）：SQLite 数据库结构速览。

只用 Python 标准库（本机没有 sqlite3 CLI 也能用）。用法：
    sqlite-preview.py <db文件>
"""
import os
import sqlite3
import sys

# 超过该大小的库跳过 count(*)（piper 翻页时会重跑脚本，避免扫全表卡秒级）
MAX_COUNT_BYTES = 200 * 1024 * 1024


def main() -> None:
    path = sys.argv[1] if len(sys.argv) > 1 else ""
    skip_count = False
    try:
        skip_count = os.path.getsize(path) > MAX_COUNT_BYTES
    except OSError:
        pass
    try:
        con = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
    except sqlite3.Error as e:
        print(f"无法打开数据库: {e}")
        return
    con.row_factory = sqlite3.Row
    cur = con.cursor()
    try:
        objects = cur.execute(
            "SELECT name, type, sql FROM sqlite_master"
            " WHERE type IN ('table','view') AND name NOT LIKE 'sqlite_%'"
            " ORDER BY type, name"
        ).fetchall()
    except sqlite3.Error as e:
        print(f"读取失败: {e}")
        return

    print(f"SQLite 数据库  {path}  （{len(objects)} 个表/视图）")
    print("=" * 60)
    if not objects:
        print("(空数据库)")
        return
    for obj in objects:
        name, typ = obj["name"], obj["type"]
        if typ == "table":
            if skip_count:
                print(f"\n-- {name}  [table · 行数已跳过(库>200MB)]")
            else:
                try:
                    n = cur.execute(
                        'SELECT count(*) FROM "{}"'.format(name.replace('"', '""'))
                    ).fetchone()[0]
                    print(f"\n-- {name}  [table · {n} 行]")
                except sqlite3.Error as e:
                    print(f"\n-- {name}  [table · 行数统计失败: {e}]")
        else:
            print(f"\n-- {name}  [view]")
        for line in (obj["sql"] or "").splitlines():
            print("  " + line)


if __name__ == "__main__":
    main()
