import SwiftUI

struct HomeView: View {
    @Environment(RecordStore.self) private var store
    @Environment(Router.self) private var router
    @State private var editing: PoopRecord?
    @State private var creating = false
    @State private var toast: Toast?
    @State private var toastTask: Task<Void, Never>?
    @State private var bounce = false
    @AppStorage(SharedSettings.quickTypeKey, store: AppGroup.defaults) private var quickTypeRaw = BristolType.t4.rawValue

    var body: some View {
        let stats = store.stats
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    header
                    heroCard(stats)
                    quickLogCard
                    weekCard(stats)
                    todayCard(stats)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 90)
            }
            .background(Theme.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
        .overlay(alignment: .bottom) {
            if let toast {
                ToastView(toast: toast, action: toastAction(toast))
                .padding(.bottom, 12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sheet(item: $editing) { RecordEditorView(record: $0) }
        .sheet(isPresented: $creating) { RecordEditorView(record: nil) }
    }

    // MARK: 顶部问候

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Date(), format: .dateTime.month().day().weekday(.wide))
                    .font(.cute(14, .medium))
                    .foregroundStyle(Theme.subtle)
                Text(greeting)
                    .font(.cute(26, .heavy))
                    .foregroundStyle(Theme.ink)
            }
            Spacer()
        }
        .padding(.top, 8)
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<11: return "早上好呀 ☀️"
        case 11..<14: return "中午好 🍱"
        case 14..<18: return "下午好 🍵"
        case 18..<23: return "晚上好 🌙"
        default: return "夜深啦 💤"
        }
    }

    // MARK: 今日概览

    private func heroCard(_ stats: GutStats) -> some View {
        let headline = stats.headline
        return VStack(spacing: 14) {
            HStack(spacing: 14) {
                Mascot(mood: stats.records.isEmpty ? .calm : headline.level.mood)
                    .frame(width: 92, height: 92)
                    .scaleEffect(bounce ? 1.12 : 1)
                    .animation(.spring(response: 0.3, dampingFraction: 0.45), value: bounce)
                HStack(spacing: 0) {
                    metric(value: "\(stats.today.count)", unit: "次", caption: "今天")
                    Divider().frame(height: 40)
                    metric(value: stats.hoursSinceLast.map { $0.friendlyDuration } ?? "--",
                           unit: "", caption: "距上次")
                    Divider().frame(height: 40)
                    metric(value: "\(stats.streak)", unit: "天", caption: "连续记录")
                }
            }
            InsightCard(insight: headline)
        }
        .cardStyle()
    }

    private func metric(value: String, unit: String, caption: String) -> some View {
        VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(value)
                    .font(.cute(22, .heavy))
                    .foregroundStyle(Theme.ink)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                if !unit.isEmpty {
                    Text(unit).font(.cute(12, .bold)).foregroundStyle(Theme.subtle)
                }
            }
            Text(caption).font(.cute(12, .medium)).foregroundStyle(Theme.subtle)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: 一键记录

    private var quickLogCard: some View {
        VStack(spacing: 12) {
            Button {
                quickLog(nil)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles").font(.system(size: 22, weight: .bold))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("噗！一键记录").font(.cute(20, .heavy))
                        Text("记为 \(quickType.label) · \(quickType.nickname)")
                            .font(.cute(12, .medium))
                            .opacity(0.85)
                    }
                    Spacer()
                    Image(systemName: "hand.tap.fill").font(.system(size: 22))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(colors: [Theme.primary, Color(hex: 0xFFAB76)], startPoint: .leading, endPoint: .trailing),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                )
                .shadow(color: Theme.primary.opacity(0.35), radius: 10, y: 5)
            }
            .buttonStyle(PressableStyle())

            VStack(alignment: .leading, spacing: 8) {
                Text("或者按状态一键记：")
                    .font(.cute(12, .medium))
                    .foregroundStyle(Theme.subtle)
                HStack(spacing: 8) {
                    ForEach(GutStatus.allCases) { s in
                        Button {
                            quickLog(s.representative)
                        } label: {
                            VStack(spacing: 4) {
                                BristolIcon(type: s.representative, showFace: true)
                                    .frame(width: 30, height: 30)
                                Text(s.title).font(.cute(13, .bold)).foregroundStyle(Theme.ink)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(s.softColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(PressableStyle())
                        .accessibilityLabel("一键记录：\(s.title)")
                    }
                }
            }

            Button {
                creating = true
            } label: {
                Label("详细记录", systemImage: "square.and.pencil")
                    .font(.cute(15, .bold))
                    .foregroundStyle(Theme.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Theme.primarySoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(PressableStyle())
        }
        .cardStyle()
    }

    private func toastAction(_ t: Toast) -> (() -> Void)? {
        guard let id = t.recordID else { return nil }
        return {
            if let r = store.record(id: id) { editing = r }
            toast = nil
        }
    }

    private var quickType: BristolType { BristolType(rawValue: quickTypeRaw) ?? .t4 }

    private func quickLog(_ type: BristolType?) {
        let r = store.quickLog(type ?? quickType)
        Haptics.success()
        bounce.toggle()
        showToast(Toast(message: "已记录 · \(r.bristol.nickname)", recordID: r.id))
    }

    private func showToast(_ t: Toast) {
        toastTask?.cancel()
        withAnimation(.spring) { toast = t }
        toastTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut) { toast = nil }
        }
    }

    // MARK: 最近 7 天

    private func weekCard(_ stats: GutStats) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "最近 7 天", symbol: "calendar")
            WeekStrip(days: stats.days(7)) { _ in router.tab = .history }
            StatusLegend()
                .frame(maxWidth: .infinity)
        }
        .cardStyle()
    }

    // MARK: 今天的记录

    private func todayCard(_ stats: GutStats) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "今天的记录", symbol: "list.bullet", trailing: stats.today.isEmpty ? nil : "\(stats.today.count) 条")
            if stats.today.isEmpty {
                EmptyHint(title: "今天还没有记录哦", subtitle: "噗完了就点上面的按钮，一下就好～")
            } else {
                ForEach(stats.today) { r in
                    Button { editing = r } label: { RecordRow(record: r) }
                        .buttonStyle(.plain)
                    if r.id != stats.today.last?.id { Divider() }
                }
            }
        }
        .cardStyle()
    }
}

/// 按下时轻轻缩小
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
