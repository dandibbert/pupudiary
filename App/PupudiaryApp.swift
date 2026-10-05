import SwiftUI
import UIKit

@main struct PupudiaryApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(model)
                .tint(PupuStyle.green)
                .preferredColorScheme(model.isUITesting ? (ProcessInfo.processInfo.arguments.contains("--dark-mode") ? .dark : .light) : nil)
                .environment(\.locale, Locale(identifier: "zh_Hans_CN"))
                .modifier(TestTypography(enabled: model.isUITesting && ProcessInfo.processInfo.arguments.contains("--large-type")))
                .onChange(of: scenePhase) { _, phase in if phase == .active { model.reload() } }
                .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged).receive(on: RunLoop.main)) { _ in model.changed() }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification).receive(on: RunLoop.main)) { _ in model.changed() }
                .onOpenURL { url in
                    guard url.scheme == "pupudiary" else { return }
                    if url.host == "record" { model.showRecord = true }
                    if url.host == "home" { model.selectedTab = 0 }
                }
        }
    }
}
struct RootView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        TabView(selection: $model.selectedTab) {
            HomeView().tabItem { Label("今天", systemImage: "sun.max") }.tag(0)
            HistoryView().tabItem { Label("记录", systemImage: "calendar") }.tag(1)
            TrendsView().tabItem { Label("趋势", systemImage: "chart.bar.xaxis") }.tag(2)
        }
        .overlay(alignment: .top) {
            if model.isLoading && model.entries.isEmpty {
                ProgressView("正在读取手帐…").font(.caption).padding(12).background(PupuStyle.card, in: Capsule()).padding(.top, 8)
            }
        }
        .sheet(isPresented: $model.showRecord) { RecordView(entry: nil) }
        .sheet(item: $model.editing) { entry in RecordView(entry: entry) }
        .sheet(isPresented: $model.showSettings) { SettingsView() }
        .sheet(isPresented: $model.showWidgetPreview) { WidgetPreview() }
        .alert("温柔提醒", isPresented: Binding(get: { model.error != nil && !model.showRecord && model.editing == nil && !model.showSettings && !model.showWidgetPreview }, set: { if !$0 { model.error = nil } })) {
            Button("知道了", role: .cancel) { model.error = nil }
        } message: { Text(model.error ?? "") }
    }
}
struct PaperBackground: ViewModifier {
    func body(content: Content) -> some View { content.background(PupuStyle.paper).foregroundStyle(PupuStyle.ink) }
}
extension View {
    func paper() -> some View { modifier(PaperBackground()) }
    func diaryCard(_ color: Color = PupuStyle.card) -> some View {
        padding(18).background(color, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
struct SectionHeading: View {
    let title: String
    var detail: String? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(.headline, design: .rounded))
            Spacer()
            if let detail { Text(detail).font(.caption).foregroundStyle(PupuStyle.muted) }
        }
    }
}
struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 23) {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(Date(), format: .dateTime.month(.wide).day().weekday(.wide)).font(.caption.weight(.medium)).foregroundStyle(PupuStyle.muted)
                            Text("今天，也照顾好自己").font(.system(.title2, design: .rounded, weight: .bold))
                        }
                        Spacer()
                        Button { model.showSettings = true } label: { Image(systemName: "slider.horizontal.3").font(.title3).frame(width: 44, height: 44).background(PupuStyle.card, in: Circle()) }.accessibilityLabel("设置")
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("我的小小日常").font(.subheadline.weight(.medium)).foregroundStyle(PupuStyle.muted)
                                HStack(alignment: .firstTextBaseline, spacing: 7) {
                                    Text("\(model.today.count)").font(.system(size: 52, weight: .semibold, design: .rounded)).accessibilityIdentifier("entry-count")
                                    Text("次记录").font(.subheadline).foregroundStyle(PupuStyle.muted)
                                }
                                Text(model.today.isEmpty ? "每个人都有自己的节奏" : "不赶时间，按自己的节奏").font(.subheadline).foregroundStyle(PupuStyle.muted)
                            }
                            Spacer(minLength: 0)
                            if !typeSize.isAccessibilitySize { Dumpling().frame(width: 125, height: 142) }
                        }
                        Divider().overlay(PupuStyle.green.opacity(0.10))
                        HStack(spacing: 7) {
                            Image(systemName: "clock")
                            if let last = model.entries.first {
                                Text("最近一次"); Text(last.occurredAt, format: .dateTime.month().day().hour().minute())
                            } else { Text("还没有记录，从这一刻开始吧") }
                        }.font(.caption).foregroundStyle(PupuStyle.muted)
                    }.diaryCard(PupuStyle.sage)
                    VStack(spacing: 12) {
                        Button { model.quickSave() } label: {
                            HStack { Image(systemName: "plus").font(.title3.weight(.bold)); Text("记下此刻").font(.headline); Spacer(); Image(systemName: "arrow.up.right") }
                                .padding(.horizontal, 22).frame(minHeight: 60).foregroundStyle(PupuStyle.onGreen).background(PupuStyle.green, in: Capsule())
                        }.disabled(model.isLoading).accessibilityIdentifier("quick-save")
                        HStack {
                            Text("只记时间，其他都可以晚点补").font(.caption).foregroundStyle(PupuStyle.muted)
                            Spacer()
                            Button(model.undoID == nil ? "详细记录" : "补充刚才记录") { model.openDetailedRecord() }.font(.subheadline.weight(.semibold)).disabled(model.isLoading).accessibilityIdentifier("open-record")
                        }
                    }
                    if let toast = model.toast {
                        HStack(alignment: .center) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(PupuStyle.green)
                            Text(toast).font(.caption)
                            Spacer(minLength: 2)
                            if model.undoID != nil { Button("撤销") { model.undoSave() }.font(.subheadline.weight(.semibold)).accessibilityIdentifier("undo-save") }
                            else { Button { model.toast = nil } label: { Image(systemName: "xmark").frame(width: 32, height: 32) }.accessibilityLabel("关闭提示") }
                        }.padding(13).background(PupuStyle.sage.opacity(0.7), in: RoundedRectangle(cornerRadius: 14)).accessibilityElement(children: .contain)
                    }
                    VStack(alignment: .leading, spacing: 15) {
                        SectionHeading(title: "这一周的小脚印", detail: "有记录的日子")
                        WeekStrip(entries: model.entries)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeading(title: "今天的手帐", detail: "\(model.today.count) 条")
                        if model.today.isEmpty {
                            HStack(spacing: 13) {
                                Image(systemName: "book.closed").font(.title2).foregroundStyle(PupuStyle.green)
                                VStack(alignment: .leading, spacing: 4) { Text("空白也是日常").font(.subheadline.weight(.semibold)); Text("想记的时候，我们在这里").font(.caption).foregroundStyle(PupuStyle.muted) }
                            }.frame(maxWidth: .infinity, alignment: .leading).diaryCard()
                        } else {
                            ForEach(model.today.prefix(4)) { entry in Button { model.editing = entry } label: { EntryRow(entry: entry) }.buttonStyle(.plain) }
                        }
                    }
                    HStack(spacing: 6) { Image(systemName: "lock.shield"); Text("无需账号 · 记录保存在本机") }.font(.caption2).foregroundStyle(PupuStyle.muted).frame(maxWidth: .infinity)
                }.padding(.horizontal, 22).padding(.top, 16).padding(.bottom, 28)
            }.paper().toolbar(.hidden, for: .navigationBar)
        }
    }
}
struct WeekStrip: View {
    let entries: [LogEntry]
    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<7) { offset in
                let day = Calendar.current.date(byAdding: .day, value: offset - 6, to: Date())!
                let hasEntry = entries.contains { Calendar.current.isDate($0.occurredAt, inSameDayAs: day) }
                VStack(spacing: 10) {
                    Text(day, format: .dateTime.weekday(.narrow)).font(.caption).foregroundStyle(PupuStyle.muted)
                    ZStack {
                        Circle().fill(hasEntry ? PupuStyle.sage : PupuStyle.card).frame(width: 34, height: 34)
                        if hasEntry { Image(systemName: "leaf.fill").font(.caption).foregroundStyle(PupuStyle.green) }
                        else { Text(day, format: .dateTime.day()).font(.caption).foregroundStyle(PupuStyle.muted) }
                    }.overlay { if offset == 6 { Circle().stroke(PupuStyle.green, lineWidth: 1.5).frame(width: 40, height: 40) } }
                }.frame(maxWidth: .infinity).accessibilityLabel("\(day.formatted(date: .abbreviated, time: .omitted))，\(hasEntry ? "有记录" : "无记录")")
            }
        }
    }
}
struct EntryRow: View {
    let entry: LogEntry
    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: entry.bristol == nil ? "leaf" : "leaf.fill").font(.title3).foregroundStyle(PupuStyle.green).frame(width: 44, height: 48).background(PupuStyle.sage, in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 5) {
                HStack { Text(entry.occurredAt, style: .time).font(.system(.headline, design: .rounded)); if let type = entry.bristol { Text("类型 \(type)").font(.caption).foregroundStyle(PupuStyle.muted) } }
                Text(entry.note?.isEmpty == false ? entry.note! : (entry.effort ?? "只记了时间，也很好")).font(.caption).foregroundStyle(PupuStyle.muted).lineLimit(2)
            }
            Spacer(minLength: 2)
            Image(systemName: "chevron.right").font(.caption2.weight(.bold)).foregroundStyle(PupuStyle.muted)
        }.diaryCard().accessibilityElement(children: .combine)
    }
}

private struct TestTypography: ViewModifier {
    @Environment(\.dynamicTypeSize) private var inherited
    let enabled: Bool
    func body(content: Content) -> some View {
        content.environment(\.dynamicTypeSize, enabled ? .accessibility3 : inherited)
    }
}
