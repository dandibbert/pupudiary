import SwiftUI
import WidgetKit

struct SettingsView: View {
    @Environment(RecordStore.self) private var store
    @AppStorage(SettingsKey.reminderEnabled) private var reminderEnabled = false
    @AppStorage(SettingsKey.reminderMinutes) private var reminderMinutes = 21 * 60
    @AppStorage(SettingsKey.lockEnabled) private var lockEnabled = false
    @AppStorage(SettingsKey.hapticsEnabled) private var hapticsEnabled = true
    @AppStorage(SharedSettings.quickTypeKey, store: AppGroup.defaults) private var quickTypeRaw = BristolType.t4.rawValue
    @State private var confirmClear = false
    @State private var showGuide = false
    @State private var showWidgetGuide = false
    @State private var notificationDenied = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    header
                    profileCard
                    quickTypeCard
                    widgetCard
                    preferencesCard
                    dataCard
                    aboutCard
                    Text("本 App 仅用于日常记录，不能代替专业医疗建议")
                        .font(.cute(11, .medium))
                        .foregroundStyle(Theme.subtle)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 90)
            }
            .background(Theme.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .confirmationDialog("确定清空全部 \(store.records.count) 条记录吗？此操作无法撤销。",
                                isPresented: $confirmClear, titleVisibility: .visible) {
                Button("清空", role: .destructive) { store.deleteAll() }
            }
            .alert("没有通知权限", isPresented: $notificationDenied) {
                Button("好的", role: .cancel) {}
            } message: {
                Text("请到 系统设置 › 通知 › 噗噗手帐 中允许通知。")
            }
            .sheet(isPresented: $showGuide) { BristolGuideView() }
            .sheet(isPresented: $showWidgetGuide) { WidgetGuideView() }
        }
    }

    // MARK: 顶部

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("设置与数据")
                    .font(.cute(14, .medium))
                    .foregroundStyle(Theme.subtle)
                Text("我的")
                    .font(.cute(26, .heavy))
                    .foregroundStyle(Theme.ink)
            }
            Spacer()
        }
        .padding(.top, 8)
    }

    private var profileCard: some View {
        let stats = store.stats
        let first = store.records.last?.timestamp
        return HStack(spacing: 14) {
            Mascot(mood: .happy).frame(width: 72, height: 72)
            VStack(alignment: .leading, spacing: 6) {
                Text("噗噗手帐").font(.cute(20, .heavy)).foregroundStyle(Theme.ink)
                if let first {
                    Text("从 \(first.formatted(.dateTime.year().month().day())) 开始")
                        .font(.cute(13, .medium)).foregroundStyle(Theme.subtle)
                    HStack(spacing: 8) {
                        pill("共 \(store.records.count) 次", color: Theme.primary)
                        pill("连续 \(stats.streak) 天 🔥", color: GutStatus.dry.color)
                    }
                } else {
                    Text("还没有记录，从今天开始吧～").font(.cute(13, .medium)).foregroundStyle(Theme.subtle)
                }
            }
            Spacer(minLength: 0)
        }
        .cardStyle()
    }

    private func pill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.cute(12, .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.14), in: Capsule())
    }

    // MARK: 一键记录默认类型

    private var quickTypeCard: some View {
        let selected = BristolType(rawValue: quickTypeRaw) ?? .t4
        return VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "一键记录记成什么", symbol: "sparkles")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                ForEach(BristolType.allCases) { t in
                    let on = t == selected
                    Button {
                        quickTypeRaw = t.rawValue
                        WidgetCenter.shared.reloadAllTimelines()
                        Haptics.tap()
                    } label: {
                        VStack(spacing: 2) {
                            BristolIcon(type: t, showFace: false)
                                .frame(width: 28, height: 28)
                            Text("\(t.rawValue)")
                                .font(.cute(11, .bold))
                                .foregroundStyle(on ? Theme.ink : Theme.subtle)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(on ? t.status.softColor : Theme.cardAlt.opacity(0.5),
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(on ? t.status.color : .clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(t.label) \(t.nickname)")
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            HStack(spacing: 6) {
                StatusChip(status: selected.status)
                Text("\(selected.label) · \(selected.nickname)")
                    .font(.cute(13, .bold))
                    .foregroundStyle(Theme.ink)
            }
            Text("首页大按钮、小组件、控制中心和 Siri 一键记录时用这个类型，之后可以随时补充细节。")
                .font(.cute(12, .medium))
                .foregroundStyle(Theme.subtle)
                .fixedSize(horizontal: false, vertical: true)
        }
        .cardStyle()
    }

    // MARK: 小组件

    private var widgetCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionTitle(title: "小组件", symbol: "square.grid.2x2.fill")
                .padding(.bottom, 6)
            SettingRow(icon: AppGroup.isShared ? "link" : "link.badge.plus",
                       color: AppGroup.isShared ? GutStatus.ideal.color : Theme.warning,
                       title: "和 App 数据互通",
                       subtitle: AppGroup.isShared ? AppGroup.identifier : "签名里没有可用的 App Group") {
                Text(AppGroup.isShared ? "已互通" : "未互通")
                    .font(.cute(12, .bold))
                    .foregroundStyle(AppGroup.isShared ? GutStatus.ideal.color : Theme.warning)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background((AppGroup.isShared ? GutStatus.ideal.color : Theme.warning).opacity(0.14), in: Capsule())
            }
            Divider().padding(.leading, 44)
            Button { showWidgetGuide = true } label: {
                SettingRow(icon: "questionmark", color: GutStatus.loose.color,
                           title: "添加小组件 / 控制中心 / Siri") { Chevron() }
            }
            .buttonStyle(.plain)
        }
        .cardStyle()
    }

    // MARK: 提醒与隐私

    private var preferencesCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionTitle(title: "提醒与隐私", symbol: "bell.fill")
                .padding(.bottom, 6)
            SettingRow(icon: "bell.fill", color: GutStatus.soft.color, title: "每日提醒",
                       subtitle: reminderEnabled ? "每天提醒你记录一次" : nil) {
                Toggle("", isOn: $reminderEnabled).labelsHidden().tint(Theme.primary)
            }
            .onChange(of: reminderEnabled) { _, on in
                Task { await updateReminder(on) }
            }
            if reminderEnabled {
                SettingRow(icon: "clock.fill", color: GutStatus.soft.color.opacity(0.7), title: "提醒时间") {
                    DatePicker("", selection: reminderDate, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .tint(Theme.primary)
                }
                .onChange(of: reminderMinutes) { _, m in ReminderService.schedule(minutes: m) }
            }
            Divider().padding(.leading, 44)
            SettingRow(icon: "lock.fill", color: Theme.primary, title: "\(AppLock.biometryName)锁",
                       subtitle: "打开 App 时需要验证") {
                Toggle("", isOn: $lockEnabled).labelsHidden().tint(Theme.primary)
                    .disabled(!AppLock.canUseBiometrics && !lockEnabled)
            }
            .onChange(of: lockEnabled) { _, on in
                if on {
                    Task { if !(await AppLock.authenticate()) { lockEnabled = false } }
                }
            }
            Divider().padding(.leading, 44)
            SettingRow(icon: "hand.tap.fill", color: GutStatus.ideal.color, title: "触感反馈") {
                Toggle("", isOn: $hapticsEnabled).labelsHidden().tint(Theme.primary)
            }
        }
        .cardStyle()
    }

    // MARK: 数据

    private var dataCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionTitle(title: "数据", symbol: "externaldrive.fill")
                .padding(.bottom, 6)
            NavigationLink { ExportView() } label: {
                SettingRow(icon: "square.and.arrow.up.fill", color: Theme.primary,
                           title: "导出记录", subtitle: "PDF 报告 / CSV 表格 / JSON 备份") { Chevron() }
            }
            .buttonStyle(.plain)
            Divider().padding(.leading, 44)
            NavigationLink { ImportView() } label: {
                SettingRow(icon: "square.and.arrow.down.fill", color: GutStatus.loose.color,
                           title: "导入数据", subtitle: "PoopLog 备份 / 噗噗手帐备份") { Chevron() }
            }
            .buttonStyle(.plain)
            Divider().padding(.leading, 44)
            Button { confirmClear = true } label: {
                SettingRow(icon: "trash.fill", color: Theme.warning, title: "清空所有记录") { EmptyView() }
            }
            .buttonStyle(.plain)
            .disabled(store.records.isEmpty)
            .opacity(store.records.isEmpty ? 0.5 : 1)
            Text("数据只保存在这台手机上。重新签名安装前，记得先导出 JSON 备份。")
                .font(.cute(12, .medium))
                .foregroundStyle(Theme.subtle)
                .padding(.top, 6)
        }
        .cardStyle()
    }

    // MARK: 关于

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button { showGuide = true } label: {
                SettingRow(icon: "book.fill", color: GutStatus.dry.color, title: "七种类型怎么分") { Chevron() }
            }
            .buttonStyle(.plain)
            Divider().padding(.leading, 44)
            SettingRow(icon: "info", color: Theme.subtle, title: "版本") {
                Text(appVersion).font(.cute(14, .medium)).foregroundStyle(Theme.subtle)
            }
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
                notificationDenied = true
            }
        } else {
            ReminderService.cancel()
        }
    }
}

/// 设置里的一行：彩色小图标 + 标题 + 右侧内容
struct SettingRow<Trailing: View>: View {
    let icon: String
    let color: Color
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(color, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.cute(16, .semibold)).foregroundStyle(Theme.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(.cute(12, .medium))
                        .foregroundStyle(Theme.subtle)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

struct Chevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(Theme.subtle.opacity(0.6))
    }
}

// MARK: - 小组件使用说明

struct WidgetGuideView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    step(1, "桌面小组件", "长按桌面空白处 → 左上角「＋」→ 搜索「噗噗手帐」。小号有一个「噗！」按钮；中号可以按状态一键记录；大号还能看到 7 天概览和今天的记录。都不用打开 App。")
                    step(2, "锁屏小组件", "长按锁屏 → 自定 → 锁定屏幕 → 添加小组件，可以随时看到今天的次数。")
                    step(3, "控制中心（iOS 18+）", "下拉控制中心 → 左上角「＋」→ 添加控制 → 搜索「噗噗手帐」。")
                    step(4, "Siri / 操作按钮", "对 Siri 说「用噗噗手帐记一下」。iPhone 15 Pro 及以上可以在 设置 › 操作按钮 › 快捷指令 里选择「噗！记一下」。")
                    if !AppGroup.isShared {
                        Label("当前签名没有可用的 App Group，小组件和 App 的数据不互通。请用带 App Group 的证书重新签名，并保留小组件插件（详见 README）。",
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
