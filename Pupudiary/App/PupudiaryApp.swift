import SwiftUI
import AppIntents

@main
struct PupudiaryApp: App {
    @State private var store = RecordStore()
    @State private var router = Router()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(router)
                .onOpenURL { router.handle($0) }
        }
    }
}

/// 页面跳转（小组件 / 深链接）
@Observable
@MainActor
final class Router {
    enum Tab: Hashable { case home, history, stats, settings }

    var tab: Tab = .home
    /// 弹出新建记录
    var showNewRecord = false

    func handle(_ url: URL) {
        guard url.scheme == "pupudiary" else { return }
        switch url.host {
        case "record":
            tab = .home
            showNewRecord = true
        case "stats":
            tab = .stats
        case "history":
            tab = .history
        default:
            tab = .home
        }
    }
}

/// Siri / 快捷指令 / 操作按钮
struct PupudiaryShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: QuickLogIntent(),
                    phrases: ["用\(.applicationName)记一下",
                              "\(.applicationName)记录噗噗",
                              "Log poop in \(.applicationName)"],
                    shortTitle: "噗！记一下",
                    systemImageName: "sparkles")
    }
}
