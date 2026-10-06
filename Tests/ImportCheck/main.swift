// 在 macOS 上用 swiftc 编译运行，检查 PoopLog 导入（CI 里自动执行）
import Foundation

func check(_ ok: Bool, _ message: String) {
    if !ok {
        print("❌ \(message)")
        exit(1)
    }
    print("✅ \(message)")
}

let path = CommandLine.arguments[1]
let data = try Data(contentsOf: URL(fileURLWithPath: path))
check(PoopLogImporter.isPoopLogBackup(data), "识别为 PoopLog 备份")

let records = try PoopLogImporter.records(from: data).sorted { $0.timestamp < $1.timestamp }
check(records.count == 4, "读出 4 条（跳过「没有排便」和日记条目），实际 \(records.count)")

let r1 = records[0], r2 = records[1], r3 = records[2], r5 = records[3]
check(r1.timestamp == Date(timeIntervalSince1970: 1_720_702_980), "时间正确")
check(r1.bristol == .t1 && r2.bristol == .t4 && r3.bristol == .t7, "类型 0/3/6 → 第 1/4/7 型")
check(r1.ease == .hard && r2.ease == .easy, "Difficult → 费力，Easy → 轻松")
check(r3.symptoms.contains(.incomplete) && r3.symptoms.contains(.blood), "Incomplete 和出血 → 不适症状")
check(r1.amount == .small && r2.amount == .medium && r3.amount == .large, "分量映射")
check(r1.durationMinutes == 15 && r2.durationMinutes == 3 && r3.durationMinutes == 8, "用时档位映射")
check(r1.note.contains("泻药") && r2.note == "火锅", "泻药和备注")
check(r5.note.contains("其他"), "Other 类型带备注")
check(r1.color == .brown, "颜色映射")

let again = try PoopLogImporter.records(from: data)
check(Set(again.map(\.id)) == Set(records.map(\.id)), "重复导入 id 一致")

print("🎉 PoopLog 导入测试通过")
