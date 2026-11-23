// macOS 独立存储回归测试；无需模拟器和开发者签名。
import Foundation

func check(_ condition: Bool, _ label: String) {
    guard condition else {
        fputs("❌ \(label)\n", stderr)
        exit(1)
    }
    print("✅ \(label)")
}

// 事故复现：描述文件顺序是 .5,.4,.1；旧 App 选 .1，重签脚本选 .5。
// 选择必须仅由完整授权集合决定，不能由 Info.plist 或容器瞬时可访问状态决定。
let groups = [
    "group.a4cb01159be1f588.5",
    "group.a4cb01159be1f588.4",
    "group.a4cb01159be1f588.1",
    "group.a4cb01159be1f588.3",
    "group.a4cb01159be1f588.2"
]
let preferred = "group.a4cb01159be1f588.1"
check(AppGroup.preferredIdentifier(configured: "group.a4cb01159be1f588.5", declaredGroups: groups) == preferred,
      "重签名修改 Info.plist 后仍选原来的 .1")
check(AppGroup.preferredIdentifier(configured: "group.com.pupudiary.app", declaredGroups: groups.reversed()) == preferred,
      "授权列表重新排序不改变数据容器")
check(AppGroup.preferredIdentifier(configured: "group.personal", declaredGroups: []) == "group.personal",
      "没有描述文件时保留已配置的组")

let fm = FileManager.default
let root = fm.temporaryDirectory.appendingPathComponent("pupudiary-storage-\(UUID().uuidString)", isDirectory: true)
defer { try? fm.removeItem(at: root) }
RecordStorage.testDirectory = root
check((try RecordStorage.load()).isEmpty, "首次启动时允许空数据")

let first = PoopRecord(timestamp: Date(timeIntervalSince1970: 1_760_000_000), bristol: .t4)
let second = PoopRecord(timestamp: Date(timeIntervalSince1970: 1_760_100_000), bristol: .t1)

_ = try RecordStorage.mutate { $0.append(first) }
check((try RecordStorage.load()).count == 1, "首次写入后可读取一条")
let firstSnapshots = try RecordStorage.snapshots()
check(firstSnapshots.contains(where: { $0.count == 1 && $0.source == "当前 App Group" }),
      "首次保存即产生共享数据完整快照")
check(firstSnapshots.contains(where: { $0.count == 1 && $0.source == "本 App 私有备份" }),
      "首次保存即产生独立私有数据快照")
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
try fm.removeItem(at: blocker)
try Data("not a directory".utf8).write(to: blocker)
do {
    _ = try RecordStorage.mutate { $0.append(second) }
    check(false, "备份无法创建时必须阻止保存")
} catch {
    check(true, "备份失败抛出异常")
}
check(try Data(contentsOf: RecordStorage.fileURL) == prior, "备份失败也不修改主文件")
// 故障复现：当前 Group 和主库一起消失，但 App 私有备份仍可恢复。
let root3 = fm.temporaryDirectory.appendingPathComponent("pupudiary-mirror-\(UUID().uuidString)")
defer { try? fm.removeItem(at: root3) }
RecordStorage.testDirectory = root3
_ = try RecordStorage.mutate { $0.append(first) }
try fm.removeItem(at: root3.appendingPathComponent("Backups"))
try fm.removeItem(at: RecordStorage.fileURL)
let privateOnly = try RecordStorage.snapshots().filter { $0.source == "本 App 私有备份" }
check(privateOnly.count == 1 && privateOnly[0].count == 1, "共享容器丢失后仍能发现私有备份")
do {
    _ = try RecordStorage.mutate { $0.append(second) }
    check(false, "主文件意外消失且私有备份存在时应阻止新写入")
} catch {
    check(error is RecordStorageError, "已有备份时主文件意外消失会报错")
}
let privateRecovered = try RecordStorage.restoreMissingRecords(from: privateOnly[0].id)
let privateRecoveredCount = try RecordStorage.load().count
check(privateRecovered == 1 && privateRecoveredCount == 1, "能从私有备份恢复丢失记录")

print("🎉 JSON 存储安全测试通过")
