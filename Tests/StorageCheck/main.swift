// macOS 独立存储回归测试；无需模拟器和开发者签名。
import Foundation

func check(_ condition: @autoclosure () -> Bool, _ label: String) {
    guard condition() else {
        fputs("❌ \(label)\n", stderr)
        exit(1)
    }
    print("✅ \(label)")
}

let fm = FileManager.default
let root = fm.temporaryDirectory.appendingPathComponent("pupudiary-storage-\(UUID().uuidString)", isDirectory: true)
defer { try? fm.removeItem(at: root) }
RecordStorage.testDirectory = root
check((try RecordStorage.load()).isEmpty, "首次启动时允许空数据")

let first = PoopRecord(timestamp: Date(timeIntervalSince1970: 1_760_000_000), bristol: .t4)
let second = PoopRecord(timestamp: Date(timeIntervalSince1970: 1_760_100_000), bristol: .t1)

_ = try RecordStorage.mutate { $0.append(first) }
check((try RecordStorage.load()).count == 1, "首次写入后可读取一条")
_ = try RecordStorage.mutate { $0.append(second) }
check((try RecordStorage.load()).count == 2, "再次写入保留旧数据")
let snapshots = try RecordStorage.snapshots()
check(snapshots.contains(where: { $0.count == 1 }), "保存前存在包含旧记录的快照")
let recoverID = snapshots.first(where: { $0.count == 1 })!.id

let corrupt = Data("{broken JSON".utf8)
try corrupt.write(to: RecordStorage.fileURL, options: .atomic)
do {
    _ = try RecordStorage.mutate { $0.append(PoopRecord(bristol: .t7)) }
    check(false, "损坏 JSON 必须拒绝写入")
} catch {
    check(error is RecordStorageError, "损坏 JSON 传递明确错误")
}
check(try Data(contentsOf: RecordStorage.fileURL) == corrupt, "写入失败保留损坏文件原样")

let recovered = try RecordStorage.restoreMissingRecords(from: recoverID)
check(recovered == 1, "明确恢复旧备份可补回记录")
check((try RecordStorage.load()).count == 1, "恢复后 JSON 可正常读取")
let damaged = try fm.contentsOfDirectory(atPath: root.appendingPathComponent("Backups").path)
check(damaged.contains(where: { $0.hasPrefix("damaged-") }), "修复前留存损坏原件")

try fm.removeItem(at: RecordStorage.fileURL)
do {
    _ = try RecordStorage.mutate { $0.append(second) }
    check(false, "曾有数据的主文件消失时必须拒绝重新创建")
} catch {
    check(error is RecordStorageError, "意外丢文件返回明确错误")
}
check(!fm.fileExists(atPath: RecordStorage.fileURL.path), "丢文件后未偷偷新建空库")

// 备份失败时不能继续覆盖主文件。
let root2 = fm.temporaryDirectory.appendingPathComponent("pupudiary-backupfail-\(UUID().uuidString)")
defer { try? fm.removeItem(at: root2) }
RecordStorage.testDirectory = root2
_ = try RecordStorage.mutate { $0.append(first) }
let prior = try Data(contentsOf: RecordStorage.fileURL)
let blocker = root2.appendingPathComponent("Backups")
try Data("not a directory".utf8).write(to: blocker)
do {
    _ = try RecordStorage.mutate { $0.append(second) }
    check(false, "备份无法创建时必须阻止保存")
} catch {
    check(true, "备份失败抛出异常")
}
check(try Data(contentsOf: RecordStorage.fileURL) == prior, "备份失败也不修改主文件")
print("🎉 JSON 存储安全测试通过")
