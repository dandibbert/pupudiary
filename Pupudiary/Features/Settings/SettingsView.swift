import SwiftUI
import UniformTypeIdentifiers
import WidgetKit

struct SettingsView: View {
    @Environment(RecordStore.self) private var store
    @AppStorage(SettingsKey.reminderEnabled) private var reminderEnabled = false
    @AppStorage(SettingsKey.reminderMinutes) private var reminderMinutes = 21 * 60
    @AppStorage(SettingsKey.lockEnabled) private var lockEnabled = false
    @AppStorage(SettingsKey.hapticsEnabled) private var hapticsEnabled = true
    @AppStorage(SharedSettings.quickTypeKey, store: AppGroup.defaults) private var quickTypeRaw = BristolType.t4.rawValue
    @State private var importing = false
    @State private var confirmClear = false
    @State private var showGuide = false
    @State private var showWidgetGuide = false
    @State private var alert: AlertInfo?

    struct AlertInfo: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    profileHeader
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                Section {
                    Picker(selection: $quickTypeRaw) {
                        ForEach(BristolType.allCases) { t in
                            Text("\(t.label) · \(t.nickname)（\(t.status.title)）").tag(t.rawValue)
                        }
                    } label: {
                        Label("默认类型", systemImage: "sparkles")
                    }
                    .onChange(of: quickTypeRaw) { _, _ in
                        WidgetCenter.shared.reloadAllTimelines()
                    }
                    Button {
                        showWidgetGuide = true
                    } label: {
                        Label("小组件 / 控制中心 / Siri 使用方法", systemImage: "square.grid.2x2.fill")
                    }
                } header: {
                    Text("一键记录")
                } footer: {
                    Text("首页大按钮、桌面小组件、控制中心和 Siri 一键记录时使用这个类型，之后可以随时补充细节。")
                }

                Section("提醒") {
                    Toggle(isOn: $reminderEnabled) {
                        Label("每日提醒", systemImage: "bell.fill")
                    }
                    .onChange(of: reminderEnabled) { _, on in
                        Task { await updateReminder(on) }
                    }
                    if reminderEnabled {
                        DatePicker(selection: reminderDate, displayedComponents: .hourAndMinute) {
                            Label("提醒时间", systemImage: "clock")
                        }
                        .onChange(of: reminderMinutes) { _, m in
                            ReminderService.schedule(minutes: m)
                        }
                    }
                }

                Section("隐私与体验") {
                    Toggle(isOn: $lockEnabled) {
                        Label("\(AppLock.biometryName)锁", systemImage: "lock.fill")
                    }
                    .disabled(!AppLock.canUseBiometrics && !lockEnabled)
                    .onChange(of: lockEnabled) { _, on in
                        if on {
                            Task {
                                if !(await AppLock.authenticate()) { lockEnabled = false }
                            }
                        }
                    }
                    Toggle(isOn: $hapticsEnabled) {
                        Label("触感反馈", systemImage: "hand.tap.fill")
                    }
                }

                Section {
                    NavigationLink {
                        ExportView()
                    } label: {
                        Label("导出记录", systemImage: "square.and.arrow.up.fill")
                    }
                    Button {
                        importing = true
                    } label: {
                        Label("从备份导入", systemImage: "square.and.arrow.down.fill")
                    }
                    Button(role: .destructive) {
                        confirmClear = true
                    } label: {
                        Label("清空所有记录", systemImage: "trash.fill")
                            .foregroundStyle(Theme.warning)
                    }
                    .disabled(store.records.isEmpty)
                } header: {
                    Text("数据")
                } footer: {
                    Text("所有数据只保存在这台手机上，不会上传。重新安装或更换签名前，记得先导出 JSON 备份。")
                }

                Section("关于") {
                    Button {
                        showGuide = true
                    } label: {
                        Label("七种类型怎么分", systemImage: "book.fill")
                    }
                    LabeledContent {
                        Text(appVersion)
                    } label: {
                        Label("版本", systemImage: "info.circle.fill")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("我的")
            .tint(Theme.primary)
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                handleImport(result)
            }
            .confirmationDialog("确定清空全部 \(store.records.count) 条记录吗？此操作无法撤销。",
                                isPresented: $confirmClear, titleVisibility: .visible) {
                Button("清空", role: .destructive) { store.deleteAll() }
            }
            .alert(item: $alert) { info in
                Alert(title: Text(info.title), message: Text(info.message), dismissButton: .default(Text("好的")))
            }
            .sheet(isPresented: $showGuide) { BristolGuideView() }
            .sheet(isPresented: $showWidgetGuide) { WidgetGuideView() }
        }
    }

    private var profileHeader: some View {
        let stats = store.stats
        let first = store.records.last?.timestamp
        return HStack(spacing: 14) {
            Mascot(mood: .happy).frame(width: 70, height: 70)
            VStack(alignment: .leading, spacing: 4) {
                Text("噗噗手帐").font(.cute(20, .heavy)).foregroundStyle(Theme.ink)
                if let first {
                    Text("从 \(first.formatted(.dateTime.year().month().day())) 开始，共记录 \(store.records.count) 次")
                        .font(.cute(13, .medium)).foregroundStyle(Theme.subtle)
                    Text("已连续记录 \(stats.streak) 天 🔥")
                        .font(.cute(13, .bold)).foregroundStyle(Theme.primary)
                } else {
                    Text("还没有记录，从今天开始吧～").font(.cute(13, .medium)).foregroundStyle(Theme.subtle)
                }
            }
            Spacer(minLength: 0)
        }
        .cardStyle()
    }

    private var reminderDate: Binding<Date> {
        Binding {
            Calendar.current.date(bySettingHour: reminderMinutes / 60, minute: reminderMinutes % 60, second: 0, of: Date()) ?? Date()
        } set: { d in
            let c = Calendar.current.dateComponents([.hour, .minute], from: d)
            reminderMinutes = (c.hour ?? 21) * 60 + (c.minute ?? 0)
        }
    }

    private var appVersion: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(v) (\(b))"
    }

    private func updateReminder(_ on: Bool) async {
        if on {
            if await ReminderService.requestPermission() {
                ReminderService.schedule(minutes: reminderMinutes)
            } else {
                reminderEnabled = false
                alert = AlertInfo(title: "没有通知权限", message: "请到 系统设置 › 通知 › 噗噗手帐 中允许通知。")
            }
        } else {
            ReminderService.cancel()
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                let records = try Exporter.importJSON(data)
                let added = store.merge(records)
                alert = AlertInfo(title: "导入成功", message: "读取到 \(records.count) 条记录，新增 \(added) 条。")
            } catch {
                alert = AlertInfo(title: "导入失败", message: "文件格式不对，请选择噗噗手帐导出的 JSON 备份。")
            }
        case .failure:
            alert = AlertInfo(title: "导入失败", message: "无法读取这个文件。")
        }
    }
}

// MARK: - 小组件使用说明

struct WidgetGuideView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    step(1, "桌面小组件", "长按桌面空白处 → 左上角「＋」→ 搜索「噗噗手帐」。小号组件有一个「噗！」按钮，中号组件可以按状态一键记录，不用打开 App。")
                    step(2, "锁屏小组件", "长按锁屏 → 自定 → 锁定屏幕 → 添加小组件，可以随时看到今天的次数。")
                    step(3, "控制中心（iOS 18+）", "下拉控制中心 → 左上角「＋」→ 添加控制 → 搜索「噗噗手帐」。")
                    step(4, "Siri / 操作按钮", "对 Siri 说「用噗噗手帐记一下」。iPhone 15 Pro 及以上可以在 设置 › 操作按钮 › 快捷指令 里选择「噗！记一下」。")
                    if !AppGroup.isShared {
                        Label("当前签名没有包含 App Group，小组件可能无法读取 App 里的数据。请使用带 App Group 的描述文件重新签名（详见 README）。",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.cute(13, .medium))
                            .foregroundStyle(Theme.warning)
                            .cardStyle()
                    }
                }
                .padding(16)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("一键记录的几种方式")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("好的") { dismiss() } }
            }
        }
    }

    private func step(_ n: Int, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)")
                .font(.cute(16, .heavy))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Theme.primary, in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.cute(16, .bold)).foregroundStyle(Theme.ink)
                Text(text).font(.cute(14, .medium)).foregroundStyle(Theme.subtle)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .cardStyle()
    }
}
