"""生成一个 PoopLog 格式（ObjectBox → LMDB → zip）的假备份，用来在 CI 里测试导入。

用法：python3 scripts/make_pooplog_fixture.py <输出.zip>
需要：pip install lmdb
数据是随机生成的，结构和 PoopLog 一致：key = 4 字节分区前缀 + 4 字节 id（大端），value = FlatBuffer。
"""
import os
import struct
import sys
import tempfile
import zipfile

import lmdb


def flatbuffer(fields):
    """fields: {字段序号: ('i64'|'bool'|'str', 值)}，生成一个只有一张表的 FlatBuffer"""
    n = max(fields) + 1
    vt_len = 4 + 2 * n
    # 表内：soffset(4) + 8 字节字段 + 4 字节字符串偏移 + 1 字节 bool
    layout, cursor = {}, 4
    for size_kind in ("i64", "str", "bool"):
        for i, (kind, _) in sorted(fields.items()):
            if kind != size_kind:
                continue
            size = {"i64": 8, "str": 4, "bool": 1}[kind]
            cursor = (cursor + size - 1) // size * size
            layout[i] = cursor
            cursor += size
    table_len = (cursor + 3) // 4 * 4
    vt_start = 4
    table_start = (vt_start + vt_len + 7) // 8 * 8
    if (table_start + 0) % 8 != 0:
        table_start += 4
    buf = bytearray(table_start + table_len)
    struct.pack_into("<I", buf, 0, table_start)
    struct.pack_into("<HH", buf, vt_start, vt_len, table_len)
    for i in range(n):
        struct.pack_into("<H", buf, vt_start + 4 + 2 * i, layout.get(i, 0))
    struct.pack_into("<i", buf, table_start, table_start - vt_start)
    strings = []
    for i, (kind, value) in fields.items():
        pos = table_start + layout[i]
        if kind == "i64":
            struct.pack_into("<q", buf, pos, value)
        elif kind == "bool":
            buf[pos] = 1 if value else 0
        else:
            strings.append((pos, value.encode()))
    for pos, data in strings:
        while len(buf) % 4:
            buf.append(0)
        s = len(buf)
        buf += struct.pack("<I", len(data)) + data + b"\0"
        struct.pack_into("<I", buf, pos, s - pos)
    return bytes(buf)


RECORDS = [
    # id, 毫秒时间, type(0-8), feeling, weight, duration, blood, laxative, note
    (1, 1720702980000, 0, 1, 0, 2, False, True, ""),
    (2, 1720789380000, 3, 0, 1, 0, False, False, "火锅"),
    (3, 1720875780000, 6, 2, 2, 1, True, False, ""),
    (4, 1720962180000, 8, 0, 1, 0, False, False, ""),   # No bowel movement，应被跳过
    (5, 1721048580000, 7, 0, 1, 0, False, False, ""),   # Other
]


def record_value(r):
    rid, ts, typ, feeling, weight, duration, blood, laxative, note = r
    fields = {
        0: ("i64", rid), 1: ("i64", ts), 2: ("i64", 0xFFB5651E), 3: ("str", note),
        4: ("bool", blood), 5: ("bool", False), 6: ("bool", False), 7: ("bool", False),
        8: ("bool", False), 9: ("bool", False), 10: ("bool", False), 11: ("bool", False),
        12: ("bool", False), 13: ("bool", laxative), 14: ("i64", typ),
        16: ("i64", feeling), 17: ("i64", weight), 18: ("i64", duration), 20: ("bool", False),
    }
    return flatbuffer(fields)


def main(out):
    with tempfile.TemporaryDirectory() as tmp:
        db_dir = os.path.join(tmp, "app-main-db-obx")
        os.makedirs(db_dir)
        env = lmdb.open(db_dir, map_size=1 << 22)
        with env.begin(write=True) as txn:
            txn.put(b"\0" * 8, b"\x10\0\0\0default\0")
            txn.put(b"\0" * 7 + b"\x01", b"\x10\0\0\0BowelLog\0dateTime\0note\0")
            txn.put(b"\0" * 7 + b"\x02", b"\x10\0\0\0JournalEntry\0notes\0")
            for r in RECORDS:
                txn.put(bytes.fromhex("18000004") + struct.pack(">I", r[0]), record_value(r))
            # JournalEntry 的数据，导入时应忽略
            txn.put(bytes.fromhex("18000008") + struct.pack(">I", 1), flatbuffer({0: ("i64", 1), 1: ("i64", 1)}))
        env.close()
        with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
            for name in ("data.mdb", "lock.mdb"):
                path = os.path.join(db_dir, name)
                if os.path.exists(path):
                    z.write(path, f"app-main-db-obx/{name}")
    print("fixture:", out)


if __name__ == "__main__":
    main(sys.argv[1])
