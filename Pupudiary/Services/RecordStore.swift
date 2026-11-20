import Foundation
import Observation

/// App 内的数据源。底层存储失败时保留内存中的旧记录，并向用户报告错误。
@Observable
@MainActor
final class RecordStore {
    private(set) var records: [PoopRecord] = []
    private var loadedAt: TimeInterval = 0
    var storageError: String?

    init() {
        CrashCatcher.install()
        DiagLog.log("App 启动 \(DiagLog.environmentSummary)")
        var migrationFailure: Error?
        do { try RecordStorage.migrateLocalDataIfNeeded() }
        catch { migrationFailure = error }
        reload()
        if let migrationFailure { report(migrationFailure) }
    }

    var stats: GutStats { GutStats(records: records) }

    func reload() {
        do {
            let latest = try RecordStorage.load()
            records = latest
            loadedAt = RecordStorage.lastChange
            storageError = nil
        } catch {
            // 绝不把磁盘读取失败当成空记录，也不覆盖当前视图里的旧内容。
            report(error)
        }
    }

    func reloadIfNeeded() {
        if RecordStorage.lastChange != loadedAt || storageError != nil {
            reload()
        }
    }

    func dismissStorageError() { storageError = nil }

    @discardableResult
    func quickLog(_ type: BristolType? = nil) -> PoopRecord? {
        let record = PoopRecord(timestamp: Date(), bristol: type ?? SharedSettings.quickDefaultType, isQuick: true)
        return save(record) ? record : nil
    }

    @discardableResult
    func save(_ record: PoopRecord) -> Bool {
        apply { list in
            if let idx = list.firstIndex(where: { $0.id == record.id }) {
                list[idx] = record
            } else {
                list.append(record)
            }
        }
    }

    @discardableResult
    func delete(_ record: PoopRecord) -> Bool {
        apply { $0.removeAll { $0.id == record.id } }
    }

    @discardableResult
    func deleteAll() -> Bool {
        apply { $0.removeAll() }
    }

    /// 导入失败时返回 nil，不允许 UI 假报「导入成功」。
    @discardableResult
    func merge(_ incoming: [PoopRecord]) -> Int? {
        var added = 0
        let saved = apply { list in
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
        return saved ? added : nil
    }

    func record(id: UUID) -> PoopRecord? {
        records.first { $0.id == id }
    }

    private func apply(_ change: (inout [PoopRecord]) -> Void) -> Bool {
        do {
            let updated = try RecordStorage.mutate(change)
            records = updated
            loadedAt = RecordStorage.lastChange
            storageError = nil
            return true
        } catch {
            report(error)
            return false
        }
    }

    private func report(_ error: Error) {
        storageError = error.localizedDescription
        DiagLog.log("‼️ 数据存储失败（已阻止写入）：\(error.localizedDescription)")
    }
}
