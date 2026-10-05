import Foundation
import Compression

/// 导入 PoopLog 的备份（poop_log_backup_xxx.zip，或其中的 data.mdb）。
///
/// PoopLog 用 ObjectBox 存数据：zip 里是一个 LMDB 数据库，每条记录是一个 FlatBuffer。
/// 这里不依赖第三方库，自己解 zip → 遍历 LMDB B 树 → 读 FlatBuffer 字段。
enum PoopLogImporter {
    enum ImportError: LocalizedError {
        case notPoopLog, corrupted, noRecords

        var errorDescription: String? {
            switch self {
            case .notPoopLog: return "这不是 PoopLog 的备份文件"
            case .corrupted: return "备份文件已损坏，无法读取"
            case .noRecords: return "备份里没有找到排便记录"
            }
        }
    }

    static func isPoopLogBackup(_ data: Data) -> Bool {
        data.starts(with: [0x50, 0x4B, 0x03, 0x04]) || LMDB.isLMDB(data)
    }

    static func records(from data: Data) throws -> [PoopRecord] {
        let mdb: Data
        if data.starts(with: [0x50, 0x4B, 0x03, 0x04]) {
            guard let file = try Zip.extract(from: data, where: { $0.hasSuffix("data.mdb") }) else {
                throw ImportError.notPoopLog
            }
            mdb = file
        } else {
            mdb = data
        }
        guard LMDB.isLMDB(mdb) else { throw ImportError.notPoopLog }
        let entries = try LMDB.entries(mdb)

        // ObjectBox 的模型信息存在 key 前 4 字节为 0 的条目里，找到 BowelLog 实体的 id
        guard let entityID = entries.first(where: { $0.key.count == 8 && $0.key.prefix(4).allSatisfy { $0 == 0 } &&
                                              FlatBuffer.containsString("BowelLog", in: $0.value) })
                .map({ UInt32($0.key.last ?? 1) }) else {
            throw ImportError.notPoopLog
        }
        // 数据条目的 key：4 字节分区前缀（大端，实体 id 左移 2 位再带标志位）+ 4 字节对象 id
        let records = entries.compactMap { entry -> PoopRecord? in
            guard entry.key.count == 8 else { return nil }
            let prefix = entry.key.prefix(4).reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
            guard prefix != 0, (prefix & 0x00FF_FFFF) >> 2 == entityID else { return nil }
            return BowelLog(entry.value)?.record
        }
        guard !records.isEmpty else { throw ImportError.noRecords }
        return records
    }
}

// MARK: - PoopLog 的 BowelLog 实体

/// 字段序号 = ObjectBox 属性 id - 1
private struct BowelLog {
    let id: Int64
    let dateTime: Int64      // 毫秒
    let color: UInt32        // ARGB
    let note: String
    let hadBlood, hadPain, hasFoodPieces, hadMucus, hadBloating, hadColic,
        hadFlatulence, hadAbnormalSmell, usedConstipationMedication, usedLaxative: Bool
    let type: Int64          // 0...6 → 布里斯托 1...7
    let feeling: Int64       // 0...2
    let weight: Int64        // 0...2
    let duration: Int64      // 0...2
    let duringMenstruation: Bool

    init?(_ data: Data) {
        guard let t = FlatBuffer.Table(root: data) else { return nil }
        guard let dt = t.int64(1), dt > 0 else { return nil }
        id = t.int64(0) ?? 0
        dateTime = dt
        color = UInt32(truncatingIfNeeded: t.int64(2) ?? 0)
        note = t.string(3) ?? ""
        hadBlood = t.bool(4)
        hadPain = t.bool(5)
        hasFoodPieces = t.bool(6)
        hadMucus = t.bool(7)
        hadBloating = t.bool(8)
        hadColic = t.bool(9)
        hadFlatulence = t.bool(10)
        hadAbnormalSmell = t.bool(11)
        usedConstipationMedication = t.bool(12)
        usedLaxative = t.bool(13)
        type = t.int64(14) ?? 3
        feeling = t.int64(16) ?? 0
        weight = t.int64(17) ?? 1
        duration = t.int64(18) ?? 0
        duringMenstruation = t.bool(20)
    }

    var record: PoopRecord {
        var symptoms: [Symptom] = []
        if hadPain || hadColic { symptoms.append(.pain) }
        if hadBloating || hadFlatulence { symptoms.append(.bloating) }
        if hadBlood { symptoms.append(.blood) }
        if hadMucus { symptoms.append(.mucus) }

        var tags: [String] = []
        if usedLaxative { tags.append("用了泻药") }
        if usedConstipationMedication { tags.append("用了便秘药") }
        if hadAbnormalSmell { tags.append("气味异常") }
        if hasFoodPieces { tags.append("有未消化食物") }
        if duringMenstruation { tags.append("经期") }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { tags.append(trimmed) }

        return PoopRecord(
            id: Self.stableUUID(id: id, time: dateTime),
            timestamp: Date(timeIntervalSince1970: TimeInterval(dateTime) / 1000),
            bristol: BristolType(rawValue: Int(type) + 1) ?? .t4,
            color: Self.nearestColor(color),
            amount: Amount(rawValue: Int(weight)) ?? .medium,
            ease: Ease(rawValue: Int(feeling)) ?? .normal,
            durationMinutes: [0, 10, 20][Int(max(0, min(2, duration)))],
            symptoms: symptoms,
            note: tags.joined(separator: "；"),
            isQuick: false
        )
    }

    /// 同一条记录每次导入得到同一个 UUID，重复导入不会重复
    static func stableUUID(id: Int64, time: Int64) -> UUID {
        var bytes = [UInt8](repeating: 0, count: 16)
        withUnsafeBytes(of: id.bigEndian) { for (i, b) in $0.enumerated() { bytes[i] = b } }
        withUnsafeBytes(of: time.bigEndian) { for (i, b) in $0.enumerated() { bytes[8 + i] = b } }
        bytes[0] = 0x50; bytes[1] = 0x4C          // "PL"
        bytes[6] = (bytes[6] & 0x0F) | 0x80        // 版本位，保证是合法 UUID
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    static func nearestColor(_ argb: UInt32) -> StoolColor? {
        guard argb != 0 else { return nil }
        let r = Int((argb >> 16) & 0xFF), g = Int((argb >> 8) & 0xFF), b = Int(argb & 0xFF)
        let palette: [(StoolColor, Int, Int, Int)] = [
            (.brown, 0x9A, 0x5A, 0x2A), (.darkBrown, 0x5C, 0x3A, 0x1E), (.yellow, 0xE0, 0xA8, 0x40),
            (.green, 0x6B, 0x8E, 0x23), (.black, 0x22, 0x22, 0x22), (.red, 0xC0, 0x30, 0x30), (.pale, 0xD8, 0xCF, 0xC0),
        ]
        return palette.min { a, c in
            let da = (a.1 - r) * (a.1 - r) + (a.2 - g) * (a.2 - g) + (a.3 - b) * (a.3 - b)
            let dc = (c.1 - r) * (c.1 - r) + (c.2 - g) * (c.2 - g) + (c.3 - b) * (c.3 - b)
            return da < dc
        }?.0
    }
}

// MARK: - 小工具：按小端读取

private extension Data {
    func u16(_ o: Int) -> Int? {
        guard o >= 0, o + 2 <= count else { return nil }
        return Int(self[startIndex + o]) | Int(self[startIndex + o + 1]) << 8
    }

    func u32(_ o: Int) -> UInt32? {
        guard o >= 0, o + 4 <= count else { return nil }
        var v: UInt32 = 0
        for i in 0..<4 { v |= UInt32(self[startIndex + o + i]) << (8 * i) }
        return v
    }

    func u64(_ o: Int) -> UInt64? {
        guard o >= 0, o + 8 <= count else { return nil }
        var v: UInt64 = 0
        for i in 0..<8 { v |= UInt64(self[startIndex + o + i]) << (8 * i) }
        return v
    }

    func slice(_ o: Int, _ n: Int) -> Data? {
        guard o >= 0, n >= 0, o + n <= count else { return nil }
        return Data(self[(startIndex + o)..<(startIndex + o + n)])
    }
}

// MARK: - FlatBuffer

private enum FlatBuffer {
    struct Table {
        let data: Data
        let pos: Int
        let vtable: Int
        let vtableLength: Int

        init?(root data: Data) {
            guard let rootOffset = data.u32(0) else { return nil }
            self.init(data: data, pos: Int(rootOffset))
        }

        init?(data: Data, pos: Int) {
            guard let soff = data.u32(pos) else { return nil }
            let vt = pos - Int(Int32(bitPattern: soff))
            guard let vlen = data.u16(vt), vlen >= 4 else { return nil }
            self.data = data
            self.pos = pos
            self.vtable = vt
            self.vtableLength = vlen
        }

        private func offset(_ field: Int) -> Int? {
            let o = 4 + 2 * field
            guard o < vtableLength, let v = data.u16(vtable + o), v != 0 else { return nil }
            return pos + v
        }

        func int64(_ field: Int) -> Int64? {
            guard let o = offset(field), let v = data.u64(o) else { return nil }
            return Int64(bitPattern: v)
        }

        func bool(_ field: Int) -> Bool {
            guard let o = offset(field), o < data.count else { return false }
            return data[data.startIndex + o] != 0
        }

        func string(_ field: Int) -> String? {
            guard let o = offset(field), let rel = data.u32(o) else { return nil }
            let s = o + Int(rel)
            guard let n = data.u32(s), let bytes = data.slice(s + 4, Int(n)) else { return nil }
            return String(data: bytes, encoding: .utf8)
        }
    }

    static func containsString(_ s: String, in data: Data) -> Bool {
        data.range(of: Data(s.utf8)) != nil
    }
}

// MARK: - LMDB（只读，遍历主库 B 树）

private enum LMDB {
    struct Entry {
        let key: Data
        let value: Data
    }

    static let magic: UInt32 = 0xBEEF_C0DE

    static func isLMDB(_ d: Data) -> Bool { d.u32(16) == magic }

    static func entries(_ d: Data) throws -> [Entry] {
        // 页大小记录在 meta 页 FREE_DBI 的 md_pad 里
        guard let ps32 = d.u32(16 + 24), ps32 >= 512, ps32 <= 65536 else { throw PoopLogImporter.ImportError.corrupted }
        let pageSize = Int(ps32)

        // 两个 meta 页，取 txnid 较大的那个
        var root: UInt64?
        var bestTxn: UInt64 = 0
        for m in 0..<2 {
            let o = m * pageSize + 16
            guard d.u32(o) == magic,
                  let r = d.u64(o + 24 + 48 + 40),
                  let txn = d.u64(o + 24 + 96 + 8) else { continue }
            if root == nil || txn > bestTxn {
                root = r
                bestTxn = txn
            }
        }
        guard let rootPage = root, rootPage != UInt64.max else { throw PoopLogImporter.ImportError.corrupted }

        var result: [Entry] = []
        var visited = Set<UInt64>()
        try walk(page: rootPage, data: d, pageSize: pageSize, visited: &visited, into: &result)
        return result
    }

    private static func walk(page: UInt64, data d: Data, pageSize: Int,
                             visited: inout Set<UInt64>, into result: inout [Entry]) throws {
        guard visited.insert(page).inserted, page < UInt64(d.count / pageSize) else {
            throw PoopLogImporter.ImportError.corrupted
        }
        let base = Int(page) * pageSize
        guard let flags = d.u16(base + 10), let lower = d.u16(base + 12) else { throw PoopLogImporter.ImportError.corrupted }
        let isBranch = flags & 0x01 != 0
        let isLeaf = flags & 0x02 != 0
        let count = max(0, (lower - 16) / 2)

        for i in 0..<count {
            guard let nodeOffset = d.u16(base + 16 + 2 * i) else { continue }
            let n = base + nodeOffset
            guard let lo = d.u16(n), let hi = d.u16(n + 2), let nflags = d.u16(n + 4), let ksize = d.u16(n + 6),
                  let key = d.slice(n + 8, ksize) else { continue }
            if isBranch {
                let child = UInt64(lo) | UInt64(hi) << 16 | UInt64(nflags) << 32
                try walk(page: child, data: d, pageSize: pageSize, visited: &visited, into: &result)
            } else if isLeaf {
                let size = lo | hi << 16
                let value: Data?
                if nflags & 0x01 != 0 {           // F_BIGDATA：数据在溢出页
                    guard let overflow = d.u64(n + 8 + ksize) else { continue }
                    value = d.slice(Int(overflow) * pageSize + 16, size)
                } else if nflags & 0x02 != 0 {    // F_SUBDATA：子库，跳过
                    value = nil
                } else {
                    value = d.slice(n + 8 + ksize, size)
                }
                if let value { result.append(Entry(key: key, value: value)) }
            }
        }
    }
}

// MARK: - ZIP（只读，支持存储和 Deflate）

private enum Zip {
    static func extract(from d: Data, where match: (String) -> Bool) throws -> Data? {
        // 从末尾找 End of Central Directory
        guard d.count >= 22 else { return nil }
        var eocd: Int?
        var i = d.count - 22
        let lowest = max(0, d.count - 22 - 65_535)
        while i >= lowest {
            if d.u32(i) == 0x0605_4B50 { eocd = i; break }
            i -= 1
        }
        guard let e = eocd, let total = d.u16(e + 10), let cdOffset = d.u32(e + 16) else { return nil }

        var p = Int(cdOffset)
        for _ in 0..<total {
            guard d.u32(p) == 0x0201_4B50,
                  let method = d.u16(p + 10),
                  let compSize = d.u32(p + 20),
                  let size = d.u32(p + 24),
                  let nameLen = d.u16(p + 28),
                  let extraLen = d.u16(p + 30),
                  let commentLen = d.u16(p + 32),
                  let localOffset = d.u32(p + 42),
                  let nameData = d.slice(p + 46, nameLen) else { return nil }
            let name = String(decoding: nameData, as: UTF8.self)
            p += 46 + nameLen + extraLen + commentLen
            guard match(name) else { continue }

            let l = Int(localOffset)
            guard d.u32(l) == 0x0403_4B50, let ln = d.u16(l + 26), let le = d.u16(l + 28),
                  let payload = d.slice(l + 30 + ln + le, Int(compSize)) else { return nil }
            switch method {
            case 0: return payload
            case 8: return try inflate(payload, size: Int(size))
            default: throw PoopLogImporter.ImportError.corrupted
            }
        }
        return nil
    }

    /// COMPRESSION_ZLIB 在 Apple 平台上就是原始 Deflate（不带 zlib 头），正好对应 zip
    private static func inflate(_ input: Data, size: Int) throws -> Data {
        guard size > 0 else { return Data() }
        var output = Data(count: size)
        let written = output.withUnsafeMutableBytes { (dst: UnsafeMutableRawBufferPointer) -> Int in
            input.withUnsafeBytes { (src: UnsafeRawBufferPointer) -> Int in
                compression_decode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, size,
                                          src.bindMemory(to: UInt8.self).baseAddress!, input.count,
                                          nil, COMPRESSION_ZLIB)
            }
        }
        guard written == size else { throw PoopLogImporter.ImportError.corrupted }
        return output
    }
}
