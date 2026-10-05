import SwiftUI
import WidgetKit
import UserNotifications

@MainActor final class AppModel: ObservableObject {
    @Published var entries: [LogEntry] = []
    @Published var dayStatuses: [DayStatus] = []
    @Published var recordDate: Date?
    @Published var isLoading = false
    private var reloadGeneration = 0
    @Published var error: String?
    @Published var toast: String?
    @Published var undoID: UUID?
    @Published var sharedAvailable = false
    @Published var selectedTab = 0
    @Published var showRecord = false
    @Published var showSettings = false
    @Published var showWidgetPreview = false
    @Published var editing: LogEntry?
    @Published var discreet = UserDefaults.standard.bool(forKey: "discreet")
    private(set) var store: DiaryStore?
    let isUITesting: Bool
    let isUnitTesting: Bool
    var today: [LogEntry] { entries.filter { Calendar.current.isDateInToday($0.occurredAt) } }
    init(testingDirectory: URL? = nil) {
        #if targetEnvironment(simulator)
        isUITesting = ProcessInfo.processInfo.arguments.contains("--uitesting")
        isUnitTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil || testingDirectory != nil
        #else
        isUITesting = false
        isUnitTesting = false
        #endif
        do {
            sharedAvailable = StorageLocation.sharedDirectory != nil
            let directory: URL
            if isUITesting || isUnitTesting {
                directory = testingDirectory ?? FileManager.default.temporaryDirectory.appendingPathComponent("pupu-ui-\(UUID().uuidString)")
            } else {
                if !sharedAvailable && UserDefaults.standard.bool(forKey: "hasUsedSharedStorage") {
                    throw NSError(domain: "Pupudiary", code: 1, userInfo: [NSLocalizedDescriptionKey: "原来的共享手帐暂时无法访问。为避免生成不一致的数据，请恢复带 App Group 的签名后重试。"])
                }
                directory = StorageLocation.sharedDirectory ?? StorageLocation.privateDirectory
            }
            store = try DiaryStore(url: StorageLocation.database(in: directory))
            if !isUITesting, !isUnitTesting, sharedAvailable {
                UserDefaults.standard.set(true, forKey: "hasUsedSharedStorage")
                StorageLocation.sharedPreferences?.set(discreet, forKey: "discreet")
                if !UserDefaults.standard.bool(forKey: "privateMigrationCompleted"), let store {
                    let oldURL = StorageLocation.privateDirectory.appendingPathComponent("diary.sqlite")
                    Task { [weak self] in
                        let warning = await Task.detached(priority: .userInitiated) { () -> String? in
                            do {
                                if FileManager.default.fileExists(atPath: oldURL.path) {
                                    let old = try DiaryStore(url: oldURL)
                                    _ = try store.mergeJSON(old.exportJSON())
                                }
                                UserDefaults.standard.set(true, forKey: "privateMigrationCompleted")
                                return nil
                            } catch { return error.localizedDescription }
                        }.value
                        if let warning { self?.error = "当前手帐仍可使用，旧的本机记录尚未迁移：\(warning)" }
                        await self?.reloadAsync()
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
    func reload() { Task { await reloadAsync() } }
    func reloadAsync() async {
        guard let store else { return }
        reloadGeneration += 1
        let generation = reloadGeneration
        isLoading = true
        let result = await Task.detached(priority: .userInitiated) { () -> Result<([LogEntry], [DayStatus]), Error> in
            Result { (try store.entries(), try store.dayStatuses()) }
        }.value
        guard generation == reloadGeneration else { return }
        isLoading = false
        switch result {
        case .success(let (records, statuses)): entries = records; dayStatuses = statuses
        case .failure(let failure): error = "读取失败：\(failure.localizedDescription)"
        }
    }
    func openDetailedRecord() {
        if let id = undoID {
            guard let entry = entries.first(where: { $0.id == id }) else {
                error = "记录正在更新，请稍候再补充"
                return
            }
            editing = entry
        } else { recordDate = nil; showRecord = true }
    }
    func changed() { reload(); WidgetCenter.shared.reloadAllTimelines() }
    func quickSave() {
        do {
            guard let store else { self.error = "手帐存储暂不可用，请检查设置中的共享空间状态"; return }
            let result = try store.quickLog()
            undoID = result.entry.id
            toast = result.wasInserted ? "排便时间已记录" : "刚刚已记录，未重复添加"
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
            toast = existing ? "修改已保存" : "排便记录已保存"
            changed(); return true
        } catch { self.error = "没有保存成功：\(error.localizedDescription)"; return false }
    }
    func delete(_ entry: LogEntry) -> Bool {
        guard let store else { error = "存储暂不可用"; return false }
        do { try store.softDelete(id: entry.id); undoID = nil; toast = "移入最近删除，随时可以恢复"; changed(); return true }
        catch { self.error = error.localizedDescription; return false }
    }
    func setDiscreet(_ value: Bool) {
        discreet = value; UserDefaults.standard.set(value, forKey: "discreet"); StorageLocation.sharedPreferences?.set(value, forKey: "discreet"); WidgetCenter.shared.reloadAllTimelines()
    }
    func hasNoBowelMovement(on day: Date) -> Bool {
        dayStatuses.contains { !$0.isCancelled && $0.matches(date: day, calendar: .current) }
    }
    func confirmNoBowelMovement(on day: Date) {
        guard let store else { error = "存储暂不可用"; return }
        do {
            _ = try store.markNoBowelMovement(on: day, calendar: .current)
            undoID = nil
            toast = Calendar.current.isDateInToday(day) ? "已确认今天截至现在未排便" : "已确认当天未排便"
            changed()
        } catch { self.error = "确认未保存：\(error.localizedDescription)" }
    }
    func clearNoBowelMovement(on day: Date) {
        guard let store else { error = "存储暂不可用"; return }
        do { try store.clearNoBowelMovement(on: day, calendar: .current); toast = "已取消未排便确认"; changed() }
        catch { self.error = "取消未保存：\(error.localizedDescription)" }
    }
    func seed() throws {
        let calendar = Calendar.current
        for offset in [2, 3, 5, 6, 8, 9, 11, 13] {
            let date = calendar.date(bySettingHour: 8 + offset % 2, minute: 20, second: 0, of: calendar.date(byAdding: .day, value: -offset, to: Date())!)!
            try store?.insert(LogEntry(occurredAt: date, bristol: offset == 2 ? 1 : (offset == 3 ? 2 : 4), effort: offset == 2 ? "很费力" : (offset == 3 ? "有点费力" : "轻松"), symptoms: offset == 2 ? ["腹胀"] : nil))
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: Date()) {
            _ = try store?.markNoBowelMovement(on: yesterday, calendar: calendar)
        }
    }
}
