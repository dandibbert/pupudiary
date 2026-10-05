import SwiftUI
import UniformTypeIdentifiers
import UserNotifications
import WidgetKit

@MainActor
struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("reminderEnabled") private var reminderEnabled = false
    @AppStorage("reminderHour") private var reminderHour = 20
    @AppStorage("reminderMinute") private var reminderMinute = 0
    @State private var reminderTime = Date()
    @State private var importing = false
    @State private var importData: Data?
    @State private var importSummary = ""
    @State private var confirmImport = false
    @State private var share: ShareFile?
    @State private var dataBusy = false
    @State private var reminderBusy = false
    private var busy: Bool { dataBusy || reminderBusy }
    @State private var busyMessage = "正在处理…"
    @State private var reminderTask: Task<Void, Never>?
    @State private var reminderRevision = UUID()
    @State private var localError: String?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) { Dumpling().frame(width: 61, height: 70); VStack(alignment: .leading, spacing: 5) { Text("噗噗手帐").font(.system(.title2, design: .rounded, weight: .bold)); Text("排便记录与健康观察").font(.caption).foregroundStyle(PupuStyle.muted) } }
                }.listRowBackground(PupuStyle.sage)
                Section("小组件") {
                    Toggle("隐私显示", isOn: Binding(get: { model.discreet }, set: model.setDiscreet))
                    Button("看看小组件") { model.showSettings = false; DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { model.showWidgetPreview = true } }
                    HStack(alignment: .top) { Image(systemName: model.sharedAvailable ? "checkmark.circle" : "info.circle"); Text(model.sharedAvailable ? "已连接共享手帐，支持小组件直接记录" : "当前签名未开放共享空间。App 可正常使用；小组件会打开 App 记录，不会单独保存一份数据。") }.font(.caption).foregroundStyle(PupuStyle.muted)
                }
                Section {
                    Toggle("每日记录提醒", isOn: Binding(get: { reminderEnabled }, set: setReminder))
                    if reminderEnabled {
                        DatePicker("提醒时间", selection: Binding(get: { reminderTime }, set: setReminderTime), displayedComponents: .hourAndMinute)
                    }
                } header: { Text("提醒") } footer: { Text("默认关闭。通知只在本机安排，内容不会显示记录详情。") }
                Section {
                    Button { export(json: false) } label: { Label("导出 CSV 表格", systemImage: "tablecells") }
                    Button { export(json: true) } label: { Label("导出完整 JSON 备份", systemImage: "square.and.arrow.up") }
                    Button { importing = true } label: { Label("从 JSON 备份恢复", systemImage: "square.and.arrow.down") }
                    NavigationLink { DeletedEntriesView() } label: { Label("最近删除", systemImage: "trash") }
                } header: { Text("导出与备份") } footer: { Text("CSV 和 JSON 包含排便记录及已删除记录，删除状态会标明。JSON 可用于完整恢复。导出文件含私人健康信息，请只分享给信任的人。导入只添加新记录，不覆盖已有记录。") }
                Section("隐私与说明") {
                    Label("无需账号，没有广告与分析追踪", systemImage: "person.crop.circle.badge.checkmark")
                    Label("不向开发者上传任何健康记录", systemImage: "lock.shield")
                    Text("数据保存在设备本地，可能随你的 iPhone 系统备份保存。卸载 App 可能丢失本地数据，请定期导出备份。此 App 不提供云同步。").font(.caption).foregroundStyle(PupuStyle.muted)
                    Text("未排便时长与频次按记录计算，默认未记录即未排便；漏记后补记会自动更新。没有首次记录时不计算未排便天数。噗噗手帐不能诊断疾病或代替医护人员的建议。").font(.caption).foregroundStyle(PupuStyle.muted)
                }
                Section("健康信息来源") {
                    Link("NIDDK：便秘的定义与表现", destination: URL(string: "https://www.niddk.nih.gov/health-information/digestive-diseases/constipation/definition-facts")!)
                    Link("NHS：便秘说明", destination: URL(string: "https://www.nhs.uk/conditions/constipation/")!)
                }
                Section { Text("Pupudiary 1.0 · 原生 iOS 17+").font(.caption).foregroundStyle(PupuStyle.muted) }
            }.scrollContentBackground(.hidden).paper().navigationTitle("设置").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .disabled(busy)
            .overlay {
                if busy {
                    ProgressView(busyMessage).padding(22)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                        .accessibilityIdentifier("settings-progress")
                }
            }
            .onAppear {
                reminderTime = Calendar.current.date(bySettingHour: reminderHour, minute: reminderMinute, second: 0, of: Date()) ?? Date()
                refreshReminderStatus()
            }
            .onChange(of: scenePhase) { _, phase in if phase == .active { refreshReminderStatus() } }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json], allowsMultipleSelection: false, onCompletion: readImport)
            .sheet(item: $share) { file in ActivitySheet(url: file.url) }
            .alert("恢复备份", isPresented: $confirmImport) {
                Button("取消", role: .cancel) { importData = nil }
                Button("添加新记录") { restore() }
            } message: { Text(importSummary) }
            .alert("请检查一下", isPresented: Binding(get: { localError != nil }, set: { if !$0 { localError = nil } })) { Button("知道了", role: .cancel) {} } message: { Text(localError ?? "") }
        }.interactiveDismissDisabled(busy)
    }
    private func export(json: Bool) {
        guard !busy else { return }
        guard let store = model.store else { localError = "存储暂不可用，无法导出"; return }
        dataBusy = true
        busyMessage = "正在准备导出…"
        Task { @MainActor in
            defer { dataBusy = false }
            do {
                let url = try await Task.detached(priority: .userInitiated) {
                    let data = try json ? store.exportJSON() : store.exportCSV()
                    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("PupudiaryExports", isDirectory: true)
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    let name = "Pupudiary-\(Date().formatted(.iso8601.year().month().day().dateSeparator(.dash)))" + (json ? ".json" : ".csv")
                    let url = folder.appendingPathComponent(name)
                    try data.write(to: url, options: [.atomic, .completeFileProtection])
                    return url
                }.value
                share = ShareFile(url: url)
            } catch { localError = "导出失败：\(error.localizedDescription)" }
        }
    }
    private func readImport(_ result: Result<[URL], Error>) {
        guard !dataBusy else { return }
        let url: URL
        do {
            guard let selected = try result.get().first else { return }
            url = selected
        } catch {
            if (error as? CocoaError)?.code != .userCancelled {
                localError = "无法读取备份：\(error.localizedDescription)"
            }
            return
        }
        guard let store = model.store else { localError = "存储暂不可用，无法导入"; return }
        dataBusy = true
        busyMessage = "正在检查备份…"
        Task { @MainActor in
            defer { dataBusy = false }
            do {
                let (data, validation) = try await Task.detached(priority: .userInitiated) {
                    // The security scope outlives every background read and closes
                    // on all success/error paths, before presenting confirmation.
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let limit = DiaryStore.maximumBackupBytes
                    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard size <= limit else {
                        throw DiaryStoreError.invalidBackup("备份超过 10 MiB，无法导入")
                    }
                    let handle = try FileHandle(forReadingFrom: url)
                    defer { try? handle.close() }
                    var data = Data()
                    // Reads can be short. Keep a hard limit even for a provider
                    // that omits or changes its reported file size.
                    while data.count <= limit {
                        let chunk = try handle.read(upToCount: min(64 * 1024, limit + 1 - data.count)) ?? Data()
                        if chunk.isEmpty { break }
                        data.append(chunk)
                    }
                    guard data.count <= limit else {
                        throw DiaryStoreError.invalidBackup("备份超过 10 MiB，无法导入")
                    }
                    return (data, store.validateBackup(data))
                }.value
                guard validation.isValid else {
                    localError = "这份备份无法导入：\n" + validation.errors.prefix(3).joined(separator: "\n")
                    return
                }
                importData = data
                importSummary = "已检查 \(validation.entryCount) 条排便记录。将添加 \(validation.newCount) 条，跳过 \(validation.existingCount) 条已有记录。现有内容不会被覆盖。"
                confirmImport = true
            } catch { localError = "无法读取备份：\(error.localizedDescription)" }
        }
    }
    private func restore() {
        guard !dataBusy else { return }
        guard let data = importData, let store = model.store else { localError = "存储暂不可用，尚未导入"; return }
        dataBusy = true
        busyMessage = "正在恢复备份…"
        Task { @MainActor in
            defer { dataBusy = false }
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try store.mergeJSON(data)
                }.value
                importData = nil
                await model.reloadAsync()
                WidgetCenter.shared.reloadAllTimelines()
                localError = "恢复完成：添加 \(result.insertedCount) 条，保留原有 \(result.skippedCount) 条"
            } catch { localError = "没有导入任何记录：\(error.localizedDescription)" }
        }
    }
    private func setReminder(_ value: Bool) {
        guard !dataBusy else { return }
        reminderEnabled = value
        reconcileReminder(requestPermission: value)
    }
    private func setReminderTime(_ value: Date) {
        guard !dataBusy else { return }
        reminderTime = value
        reminderHour = Calendar.current.component(.hour, from: value)
        reminderMinute = Calendar.current.component(.minute, from: value)
        reconcileReminder(requestPermission: false)
    }
    private func refreshReminderStatus() {
        guard !busy, !importing, share == nil, !confirmImport else { return }
        // Re-check OS permission on appearance/foreground; AppStorage alone
        // cannot tell whether the user disabled notifications in iOS Settings.
        reconcileReminder(requestPermission: false)
    }
    private func reconcileReminder(requestPermission: Bool) {
        let enabled = reminderEnabled
        let hour = reminderHour
        let minute = reminderMinute
        let previous = reminderTask
        let revision = UUID()
        reminderRevision = revision
        reminderBusy = true
        busyMessage = "正在更新提醒…"
        // Await the prior operation rather than cancelling an in-flight add:
        // cancellation would not undo the request already sent to the OS.
        reminderTask = Task { @MainActor in
            await previous?.value
            var saved = false
            var failure: String?
            do {
                let center = UNUserNotificationCenter.current()
                if enabled {
                    var settings = await center.notificationSettings()
                    if requestPermission && settings.authorizationStatus == .notDetermined {
                        _ = try await center.requestAuthorization(options: [.alert, .sound])
                        settings = await center.notificationSettings()
                    }
                    guard Self.notificationsAllowed(settings.authorizationStatus) else {
                        center.removePendingNotificationRequests(withIdentifiers: ["pupudiary.daily"])
                        throw ReminderError.permissionDenied
                    }
                    let content = UNMutableNotificationContent()
                    content.title = "噗噗手帐"
                    content.body = "可以补充今天的记录。"
                    content.sound = .default
                    let trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: hour, minute: minute), repeats: true)
                    try await center.add(UNNotificationRequest(identifier: "pupudiary.daily", content: content, trigger: trigger))
                    // Permission may change while the asynchronous add runs.
                    let latest = await center.notificationSettings()
                    guard Self.notificationsAllowed(latest.authorizationStatus) else {
                        center.removePendingNotificationRequests(withIdentifiers: ["pupudiary.daily"])
                        throw ReminderError.permissionDenied
                    }
                    saved = true
                } else {
                    center.removePendingNotificationRequests(withIdentifiers: ["pupudiary.daily"])
                }
            } catch {
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["pupudiary.daily"])
                failure = error.localizedDescription
            }
            // Old completions must not overwrite the newest toggle/time state.
            guard reminderRevision == revision else { return }
            reminderEnabled = saved
            if let failure { localError = "提醒未保存：\(failure)" }
            reminderBusy = false
            reminderTask = nil
        }
    }
    private static func notificationsAllowed(_ status: UNAuthorizationStatus) -> Bool {
        status == .authorized || status == .provisional || status == .ephemeral
    }
    private enum ReminderError: LocalizedError {
        case permissionDenied
        var errorDescription: String? { "通知权限未开启。你可以在 iPhone 设置中为噗噗手帐开启通知。" }
    }
}
private struct ShareFile: Identifiable { let id = UUID(); let url: URL }
private struct ActivitySheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: [url], applicationActivities: nil) }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
struct DeletedEntriesView: View {
    @EnvironmentObject private var model: AppModel
    @State private var deleted: [LogEntry] = []
    @State private var error: String?
    var body: some View {
        List {
            Section { Text("删除的记录保留在这里，直到你选择恢复。不会自动清空，也没有不可撤销的永久删除。").font(.caption).foregroundStyle(PupuStyle.muted) }
            if deleted.isEmpty { Text("这里空空的").foregroundStyle(PupuStyle.muted) }
            ForEach(deleted) { entry in
                HStack {
                    VStack(alignment: .leading) { Text(entry.occurredAt.formatted(date: .abbreviated, time: .shortened)); Text(entry.note ?? "无备注").font(.caption).foregroundStyle(PupuStyle.muted).lineLimit(1) }
                    Spacer()
                    Button("恢复") {
                        do { try model.store?.restoreDeleted(id: entry.id); model.changed(); refresh() } catch { self.error = error.localizedDescription }
                    }.buttonStyle(.bordered)
                }
            }
        }.scrollContentBackground(.hidden).paper().navigationTitle("最近删除").onAppear(perform: refresh)
        .alert("恢复失败", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("知道了") {} } message: { Text(error ?? "") }
    }
    private func refresh() { do { deleted = try model.store?.entries(includeDeleted: true).filter { $0.deletedAt != nil } ?? [] } catch { self.error = error.localizedDescription } }
}
struct WidgetPreview: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    Text("排便记录小组件").font(.system(.largeTitle, design: .rounded, weight: .bold))
                    Text(model.sharedAvailable ? "查看上次排便，一键记录" : "当前签名仅支持打开 App 记录").foregroundStyle(PupuStyle.muted)
                    VStack(alignment: .leading, spacing: 14) {
                        PupuWidgetContent(count: model.today.count, last: model.entries.first?.occurredAt, discreet: !model.sharedAvailable, sharedAvailable: model.sharedAvailable, lastBristol: model.entries.first?.bristol, lastEffort: model.entries.first?.effort)
                        Label(model.sharedAvailable ? "记录排便" : "打开 App 记录", systemImage: "plus").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(11).background(PupuStyle.green, in: Capsule()).foregroundStyle(PupuStyle.onGreen)
                    }.padding(20).background(PupuStyle.sage, in: RoundedRectangle(cornerRadius: 27))
                    HStack {
                        VStack(alignment: .leading, spacing: 16) {
                            PupuWidgetContent(count: 0, last: nil, discreet: true, sharedAvailable: model.sharedAvailable, compact: true)
                            Image(systemName: "plus").font(.title2).foregroundStyle(PupuStyle.onGreen).frame(width: 44, height: 44).background(PupuStyle.green, in: Circle())
                        }.padding(20).frame(maxWidth: 175, alignment: .leading).background(PupuStyle.peach, in: RoundedRectangle(cornerRadius: 27))
                        VStack(alignment: .leading, spacing: 7) { Image(systemName: "eye.slash"); Text("隐私显示").font(.headline); Text("隐私模式隐藏次数与时间").font(.caption).foregroundStyle(PupuStyle.muted) }.padding(.leading, 9)
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        Text("放到主屏幕").font(.headline)
                        Text("1  长按主屏幕空白处\n2  点“编辑”或“＋”，添加小组件\n3  搜索“噗噗手帐”，选择尺寸").font(.subheadline).lineSpacing(10)
                    }.diaryCard()
                    Text("这是 App 内的原生外观预览。桌面小组件需要签名时保留扩展及共享 App Group；不可共享时仅打开 App 记录。锁屏状态下可能需要解锁。").font(.caption).foregroundStyle(PupuStyle.muted)
                }.padding(24)
            }.paper().toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}
