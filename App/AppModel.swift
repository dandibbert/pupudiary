import SwiftUI
import WidgetKit
import UserNotifications

@MainActor final class AppModel: ObservableObject {
    @Published var entries: [LogEntry] = []
    @Published var error: String?
    @Published var toast: String?
    @Published var undoID: UUID?
    @Published var sharedAvailable = false
    @Published var selectedTab = 0
    @Published var showRecord = false
    @Published var showSettings = false
    @Published var showWidgetPreview = false
    @Published var editing: LogEntry?
    @Published var discreet = StorageLocation.sharedPreferences?.bool(forKey: "discreet") ?? false
    private(set) var store: DiaryStore?
    let isUITesting: Bool
    var today: [LogEntry] { entries.filter { Calendar.current.isDateInToday($0.occurredAt) } }
    init() {
        #if targetEnvironment(simulator)
        isUITesting = ProcessInfo.processInfo.arguments.contains("--uitesting")
        #else
        isUITesting = false
        #endif
        do {
            sharedAvailable = StorageLocation.sharedDirectory != nil
            let directory: URL
            if isUITesting {
                directory = FileManager.default.temporaryDirectory.appendingPathComponent("pupu-ui-\(UUID().uuidString)")
            } else {
                if !sharedAvailable && UserDefaults.standard.bool(forKey: "hasUsedSharedStorage") {
                    throw NSError(domain: "Pupudiary", code: 1, userInfo: [NSLocalizedDescriptionKey: "原来的共享手帐暂时无法访问。为避免生成不一致的数据，请恢复带 App Group 的签名后重试。"])
                }
                directory = StorageLocation.sharedDirectory ?? StorageLocation.privateDirectory
            }
            store = try DiaryStore(url: StorageLocation.database(in: directory))
            if !isUITesting, sharedAvailable {
                UserDefaults.standard.set(true, forKey: "hasUsedSharedStorage")
                if !UserDefaults.standard.bool(forKey: "privateMigrationCompleted") {
                    do {
                        let oldURL = StorageLocation.privateDirectory.appendingPathComponent("diary.sqlite")
                        if FileManager.default.fileExists(atPath: oldURL.path) {
                            let old = try DiaryStore(url: oldURL)
                            _ = try store?.mergeJSON(old.exportJSON())
                        }
                        UserDefaults.standard.set(true, forKey: "privateMigrationCompleted")
                    } catch {
                        self.error = "当前手帐仍可使用，旧的本机记录尚未迁移：\(error.localizedDescription)"
                    }
                }
            }
            if isUITesting { try seed() }
            reload()
            if let index = ProcessInfo.processInfo.arguments.firstIndex(of: "--screen"), ProcessInfo.processInfo.arguments.count > index + 1, isUITesting {
                switch ProcessInfo.processInfo.arguments[index + 1] {
                case "record": showRecord = true
                case "widget-preview": showWidgetPreview = true
                case "history": selectedTab = 1
                case "trends": selectedTab = 2
                default: break
                }
            }
        } catch { self.error = "手帐暂时无法打开：\(error.localizedDescription)" }
    }
    func reload() {
        do { entries = try store?.entries() ?? [] } catch { self.error = "读取失败：\(error.localizedDescription)" }
    }
    func changed() { reload(); WidgetCenter.shared.reloadAllTimelines() }
    func quickSave() {
        do {
            guard let store else { self.error = "手帐存储暂不可用，请检查设置中的共享空间状态"; return }
            let result = try store.quickLog()
            undoID = result.entry.id
            toast = result.wasInserted ? "记好啦，详情可以慢慢补" : "刚刚已经记下啦"
            changed()
        } catch { self.error = "没有保存成功，请重试：\(error.localizedDescription)" }
    }
    func undoSave() {
        guard let id = undoID, let store else { return }
        do { try store.softDelete(id: id); undoID = nil; toast = "已撤销，可在最近删除中恢复"; changed() }
        catch { self.error = error.localizedDescription }
    }
    func save(_ entry: LogEntry, existing: Bool) -> Bool {
        do {
            guard let store else { throw CocoaError(.fileNoSuchFile) }
            if existing { try store.update(entry) } else { try store.insert(entry) }
            undoID = existing ? nil : entry.id
            toast = existing ? "修改已保存" : "这一刻，记好啦"
            changed(); return true
        } catch { self.error = "没有保存成功：\(error.localizedDescription)"; return false }
    }
    func delete(_ entry: LogEntry) {
        guard let store else { error = "存储暂不可用"; return }
        do { try store.softDelete(id: entry.id); toast = "移入最近删除，随时可以恢复"; changed() }
        catch { self.error = error.localizedDescription }
    }
    func setDiscreet(_ value: Bool) {
        discreet = value; StorageLocation.sharedPreferences?.set(value, forKey: "discreet"); WidgetCenter.shared.reloadAllTimelines()
    }
    func seed() throws {
        let calendar = Calendar.current
        for offset in [0, 1, 2, 3, 5, 6, 8, 9, 11, 13] {
            let date = calendar.date(bySettingHour: 8 + offset % 3, minute: 20 + offset, second: 0, of: calendar.date(byAdding: .day, value: -offset, to: Date())!)!
            try store?.insert(LogEntry(occurredAt: date, bristol: offset == 0 ? 4 : 3 + offset % 3, effort: "轻松", note: offset == 0 ? "早餐后，留一点时间给自己" : nil))
        }
    }
}
