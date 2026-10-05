import SwiftUI

struct RootView: View {
    @Environment(RecordStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(SettingsKey.lockEnabled) private var lockEnabled = false
    @State private var locked = UserDefaults.standard.bool(forKey: SettingsKey.lockEnabled)
    @State private var authenticating = false

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            HomeView()
                .tabItem { Label("今天", systemImage: "sun.max.fill") }
                .tag(Router.Tab.home)
            HistoryView()
                .tabItem { Label("日历", systemImage: "calendar") }
                .tag(Router.Tab.history)
            // 中间占位，真正的按钮是下面盖在底栏上的大圆按钮
            Color.clear
                .tabItem { Text(" ") }
                .tag(Router.Tab.record)
            StatsView()
                .tabItem { Label("趋势", systemImage: "chart.bar.fill") }
                .tag(Router.Tab.stats)
            SettingsView()
                .tabItem { Label("我的", systemImage: "person.crop.circle") }
                .tag(Router.Tab.settings)
        }
        .tint(Theme.primary)
        .onChange(of: router.tab) { old, new in
            // 万一点到了占位 tab，退回原来的页面并打开记录
            if new == .record {
                router.tab = old == .record ? .home : old
                router.showNewRecord = true
            }
        }
        .overlay(alignment: .bottom) {
            RecordTabButton {
                Haptics.tap()
                router.showNewRecord = true
            }
        }
        .sheet(isPresented: $router.showNewRecord) {
            RecordEditorView(record: nil)
        }
        .overlay {
            if locked && lockEnabled {
                LockScreen(unlock: unlock)
                    .transition(.opacity)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                store.reloadIfNeeded()
                if locked && lockEnabled { unlock() }
            case .background:
                if lockEnabled { locked = true }
            default:
                break
            }
        }
        .task {
            if locked && lockEnabled { unlock() }
        }
    }

    private func unlock() {
        guard !authenticating else { return }
        authenticating = true
        Task {
            let ok = await AppLock.authenticate()
            authenticating = false
            if ok {
                withAnimation { locked = false }
            }
        }
    }
}

/// 底栏中间凸起的大「＋」按钮
private struct RecordTabButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Color(hex: 0xFFAB76), Theme.primary],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(Circle().strokeBorder(Theme.background, lineWidth: 4))
                    .shadow(color: Theme.primary.opacity(0.4), radius: 8, y: 4)
                Image(systemName: "plus")
                    .font(.system(size: 26, weight: .heavy))
                    .foregroundStyle(.white)
            }
            .frame(width: 64, height: 64)
        }
        .buttonStyle(PressableStyle())
        .padding(.bottom, -6)
        .accessibilityLabel("记录一次")
    }
}

private struct LockScreen: View {
    let unlock: () -> Void

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 20) {
                Mascot(mood: .sleepy)
                    .frame(width: 140)
                Text("噗噗手帐已上锁")
                    .font(.cute(22, .bold))
                    .foregroundStyle(Theme.ink)
                Button(action: unlock) {
                    Label("使用\(AppLock.biometryName)解锁", systemImage: "lock.open.fill")
                        .font(.cute(17, .bold))
                        .padding(.horizontal, 24)
                        .padding(.vertical, 14)
                        .foregroundStyle(.white)
                        .background(Theme.primary, in: Capsule())
                }
            }
        }
    }
}
