import Foundation
import Observation

/// App 内的数据源。真正的存取交给 RecordStorage（App Group 里的 JSON 文件）
@Observable
@MainActor
final class RecordStore {
    private(set) var records: [PoopRecord] = []
    private var loadedAt: TimeInterval = 0

    init() {
        reload()
    }

    var stats: GutStats { GutStats(records: records) }

    func reload() {
        records = RecordStorage.load()
        loadedAt = RecordStorage.lastChange
    }

    /// 回到前台时，如果小组件 / 快捷指令写过数据就重新读取
    func reloadIfNeeded() {
        if RecordStorage.lastChange != loadedAt {
            reload()
        }
    }

    @discardableResult
    func quickLog(_ type: BristolType? = nil) -> PoopRecord {
        let record = PoopRecord(timestamp: Date(), bristol: type ?? SharedSettings.quickDefaultType, isQuick: true)
        save(record)
        return record
    }

    func save(_ record: PoopRecord) {
        apply { list in
            if let idx = list.firstIndex(where: { $0.id == record.id }) {
                list[idx] = record
            } else {
                list.append(record)
            }
        }
    }

    func delete(_ record: PoopRecord) {
        apply { $0.removeAll { $0.id == record.id } }
    }

    func deleteAll() {
        apply { $0.removeAll() }
    }

    /// 导入：按 id 合并，已有的记录会被覆盖
    @discardableResult
    func merge(_ incoming: [PoopRecord]) -> Int {
        var added = 0
        apply { list in
            var index = Dictionary(list.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
            for r in incoming {
                if let i = index[r.id] {
                    list[i] = r
                } else {
                    index[r.id] = list.count
                    list.append(r)
                    added += 1
                }
            }
        }
        return added
    }

    func record(id: UUID) -> PoopRecord? {
        records.first { $0.id == id }
    }

    private func apply(_ change: (inout [PoopRecord]) -> Void) {
        records = RecordStorage.mutate(change)
        loadedAt = RecordStorage.lastChange
    }
}
