import SwiftUI
import UIKit
import WidgetKit

/// 诊断信息：自动检查签名 / 扩展 / App Group / 系统登记情况，并显示 App 和扩展的运行日志。
/// 出问题时，按页面上的步骤操作一遍，然后把报告复制发给开发者。
struct DiagnosticsView: View {
    @State private var report = DiagReport()
    @State private var loading = true
    @State private var copied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                stepsCard
                checksCard
                actionsCard
                rawCard
            }
            .padding(16)
            .padding(.bottom, 40)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("诊断信息")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task { await refresh() }
        .refreshable { await refresh() }
    }

    private func refresh() async {
        loading = true
        report = await DiagReport.collect()
        loading = false
    }

    // MARK: 卡片

    private var stepsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(title: "控制中心按钮出问题时", symbol: "stethoscope")
            Text("1. 点下面「清空日志」\n2. 在控制中心删掉噗噗手帐的按钮，再重新添加\n3. 点一下那个按钮\n4. 回到这里下拉刷新，点「复制报告」发给开发者")
                .font(.cute(13, .medium))
                .foregroundStyle(Theme.subtle)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var checksCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "自动检查", symbol: "checklist", trailing: loading ? "检查中…" : nil)
            ForEach(report.checks) { c in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: c.symbol)
                        .foregroundStyle(c.color)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c.title).font(.cute(14, .bold)).foregroundStyle(Theme.ink)
                        if !c.detail.isEmpty {
                            Text(c.detail).font(.cute(12, .medium)).foregroundStyle(Theme.subtle)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .cardStyle()
    }

    private var actionsCard: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                actionButton("复制报告", symbol: copied ? "checkmark" : "doc.on.doc.fill", color: Theme.primary) {
                    UIPasteboard.general.string = report.text
                    copied = true
                    Haptics.success()
                }
                ShareLink(item: report.text) {
                    label("分享报告", symbol: "square.and.arrow.up.fill", color: GutStatus.loose.color)
                }
                .buttonStyle(PressableStyle())
            }
            HStack(spacing: 10) {
                actionButton("刷新控制和小组件", symbol: "arrow.clockwise", color: GutStatus.ideal.color) {
                    DiagLog.log("手动刷新控制中心和小组件")
                    WidgetCenter.shared.reloadAllTimelines()
                    if #available(iOS 18.0, *) {
                        ControlCenter.shared.reloadAllControls()
                    }
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        await refresh()
                    }
                }
                actionButton("清空日志", symbol: "trash.fill", color: Theme.subtle) {
                    DiagLog.clear()
                    copied = false
                    Task { await refresh() }
                }
            }
        }
    }

    private func actionButton(_ title: String, symbol: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) { label(title, symbol: symbol, color: color) }
            .buttonStyle(PressableStyle())
    }

    private func label(_ title: String, symbol: String, color: Color) -> some View {
        Label(title, systemImage: symbol)
            .font(.cute(14, .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(color, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var rawCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(title: "完整报告", symbol: "doc.text.fill")
            Text(report.text)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.ink)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}

// MARK: - 报告

struct DiagReport {
    struct Check: Identifiable {
        enum Level { case ok, warn, info }
        let id = UUID()
        let level: Level
        let title: String
        let detail: String

        var symbol: String {
            switch level {
            case .ok: return "checkmark.circle.fill"
            case .warn: return "exclamationmark.triangle.fill"
            case .info: return "info.circle.fill"
            }
        }

        var color: Color {
            switch level {
            case .ok: return GutStatus.ideal.color
            case .warn: return Theme.warning
            case .info: return GutStatus.loose.color
            }
        }
    }

    var checks: [Check] = []
    var text = ""

    struct Profile {
        let name: String
        let team: String
        let appID: String
        let groups: [String]
        let expires: Date?
        let getTaskAllow: Bool

        init?(url: URL) {
            guard let p = AppGroup.profile(at: url) else { return nil }
            let ent = p["Entitlements"] as? [String: Any] ?? [:]
            name = p["Name"] as? String ?? "?"
            team = (p["TeamIdentifier"] as? [String])?.first ?? "?"
            appID = ent["application-identifier"] as? String ?? "?"
            groups = ent["com.apple.security.application-groups"] as? [String] ?? []
            expires = p["ExpirationDate"] as? Date
            getTaskAllow = ent["get-task-allow"] as? Bool ?? false
        }

        var summary: String {
            let exp = expires.map { $0.formatted(.dateTime.year().month().day()) } ?? "?"
            return "name=\(name) team=\(team) appid=\(appID) groups=\(groups.joined(separator: ",")) expires=\(exp) debug=\(getTaskAllow)"
        }
    }

    @MainActor
    static func collect() async -> DiagReport {
        var r = DiagReport()
        var lines: [String] = []
        let fm = FileManager.default

        // 基本信息
        let device = UIDevice.current
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        lines.append("== 基本 ==")
        lines.append("iOS \(device.systemVersion) · \(device.model) · App \(version)(\(build))")

        // App
        let appURL = Bundle.main.bundleURL
        let appID = Bundle.main.bundleIdentifier ?? "?"
        let appProfile = Profile(url: appURL.appendingPathComponent("embedded.mobileprovision"))
        lines.append("== App ==")
        lines.append("bundle=\(appID)")
        lines.append("Info.plist AppGroupID=\(AppGroup.configuredIdentifier)")
        lines.append("profile: \(appProfile?.summary ?? "无")")
        lines.append("Metadata.appintents: \(fm.fileExists(atPath: appURL.appendingPathComponent("Metadata.appintents").path))")

        // 扩展
        let plugins = appURL.appendingPathComponent("PlugIns")
        let appexURL = (try? fm.contentsOfDirectory(at: plugins, includingPropertiesForKeys: nil))?
            .first { $0.pathExtension == "appex" }
        lines.append("== 小组件扩展 ==")
        var appexID = "?"
        var appexProfile: Profile?
        var appexHasMetadata = false
        if let appexURL {
            let info = NSDictionary(contentsOf: appexURL.appendingPathComponent("Info.plist")) as? [String: Any] ?? [:]
            appexID = info["CFBundleIdentifier"] as? String ?? "?"
            let point = (info["NSExtension"] as? [String: Any])?["NSExtensionPointIdentifier"] as? String ?? "?"
            appexProfile = Profile(url: appexURL.appendingPathComponent("embedded.mobileprovision"))
            appexHasMetadata = fm.fileExists(atPath: appexURL.appendingPathComponent("Metadata.appintents").path)
            lines.append("name=\(appexURL.lastPathComponent) bundle=\(appexID) point=\(point)")
            lines.append("Info.plist AppGroupID=\(info["AppGroupID"] as? String ?? "?")")
            lines.append("profile: \(appexProfile?.summary ?? "无")")
            lines.append("Metadata.appintents: \(appexHasMetadata)")
        } else {
            lines.append("未找到扩展（PlugIns 为空）")
        }

        // App Group
        lines.append("== App Group ==")
        lines.append("使用=\(AppGroup.identifier) shared=\(AppGroup.isShared) 描述文件中=\(AppGroup.profileGroups.joined(separator: ","))")

        // 系统登记
        lines.append("== 系统登记 ==")
        let widgets = await currentWidgets()
        lines.append("桌面/锁屏小组件: \(widgets.isEmpty ? "无" : widgets.joined(separator: "; "))")
        var controls: [String]? = nil
        if #available(iOS 18.0, *) {
            do {
                let infos = try await ControlCenter.shared.currentControls()
                controls = infos.map { String(describing: $0) }
                lines.append("控制中心: \(infos.isEmpty ? "无" : controls!.joined(separator: "; "))")
            } catch {
                lines.append("控制中心: 读取失败 \(error)")
            }
        } else {
            lines.append("控制中心: iOS 18 以下不支持")
        }

        // 日志
        let log = DiagLog.read()
        lines.append("== 最近日志（\(log.count) 条）==")
        lines.append(contentsOf: log.suffix(80))

        // 自动检查
        var checks: [Check] = []
        if appexURL == nil {
            checks.append(Check(level: .warn, title: "安装包里没有小组件扩展", detail: "签名工具可能删掉了插件，请签名时保留扩展。"))
        } else {
            checks.append(Check(level: .ok, title: "小组件扩展存在", detail: appexID))
            if !appexID.hasPrefix(appID + ".") {
                checks.append(Check(level: .warn, title: "扩展的 Bundle ID 不在 App 名下",
                                    detail: "App=\(appID)，扩展=\(appexID)。iOS 要求扩展 ID 以「App ID.」开头，否则控制中心可能无法加载。"))
            }
            if appexProfile == nil {
                checks.append(Check(level: .info, title: "扩展里没有描述文件", detail: "部分签名工具只给 App 嵌入描述文件。"))
            } else if let a = appexProfile, let b = appProfile, a.team != b.team {
                checks.append(Check(level: .warn, title: "App 和扩展的 Team 不一致", detail: "App=\(b.team)，扩展=\(a.team)"))
            }
            if let a = appexProfile, AppGroup.isShared, !a.groups.contains(AppGroup.identifier) {
                checks.append(Check(level: .warn, title: "扩展的描述文件不含当前 App Group",
                                    detail: "当前使用 \(AppGroup.identifier)，扩展描述文件里是 \(a.groups.joined(separator: ", "))"))
            }
            if !appexHasMetadata {
                checks.append(Check(level: .warn, title: "扩展缺少 App Intents 元数据", detail: "控制中心按钮需要它来找到「记一下」动作。"))
            }
        }
        checks.append(AppGroup.isShared
                      ? Check(level: .ok, title: "App 和小组件数据互通", detail: AppGroup.identifier)
                      : Check(level: .warn, title: "App 和小组件数据不互通", detail: "签名里没有可用的 App Group"))
        if let p = appProfile, let exp = p.expires, exp < Date().addingTimeInterval(7 * 86_400) {
            checks.append(Check(level: .warn, title: "证书快过期了", detail: exp.formatted(.dateTime.year().month().day())))
        }
        if let controls {
            let ours = controls.contains { $0.contains("PupudiaryQuickLogControl") }
            checks.append(ours
                          ? Check(level: .ok, title: "系统登记了控制中心按钮", detail: "")
                          : Check(level: .info, title: "系统里没有登记噗噗手帐的控制中心按钮", detail: "如果已经添加过按钮，说明系统没把它和本 App 关联上。"))
        }
        let requested = log.contains { $0.contains("系统请求按钮样式") }
        let performed = log.contains { $0.contains("控制中心动作") }
        let extensionRan = log.contains { $0.contains("[扩展]") }
        checks.append(extensionRan
                      ? Check(level: .ok, title: "扩展运行过", detail: "")
                      : Check(level: .info, title: "日志里还没有扩展的记录", detail: "添加或刷新一下小组件后再看。"))
        checks.append(requested
                      ? Check(level: .ok, title: "系统向扩展请求过控制中心按钮", detail: "")
                      : Check(level: .info, title: "系统没有向扩展请求过控制中心按钮",
                              detail: "图标为空且这一项一直没有出现，说明系统根本没加载按钮，问题在签名 / 系统登记，而不是代码。"))
        checks.append(performed
                      ? Check(level: .ok, title: "控制中心动作执行过", detail: "")
                      : Check(level: .info, title: "控制中心动作还没有执行过", detail: "点一下控制中心按钮后再刷新。"))

        r.checks = checks
        r.text = lines.joined(separator: "\n")
        return r
    }

    private static func currentWidgets() async -> [String] {
        await withCheckedContinuation { cont in
            WidgetCenter.shared.getCurrentConfigurations { result in
                switch result {
                case .success(let infos):
                    cont.resume(returning: infos.map { "\($0.kind)/\($0.family)" })
                case .failure(let error):
                    cont.resume(returning: ["读取失败 \(error)"])
                }
            }
        }
    }
}
