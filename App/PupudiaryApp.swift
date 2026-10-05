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
        .sheet(isPresented: $model.showRecord, onDismiss: { model.recordDate = nil }) { RecordView(entry: nil, initialDate: model.recordDate) }
        .sheet(item: $model.editing) { entry in RecordView(entry: entry) }
        .sheet(isPresented: $model.showSettings) { SettingsView() }
        .sheet(isPresented: $model.showWidgetPreview) { WidgetPreview() }
        .alert("提示", isPresented: Binding(get: { model.error != nil && !model.showRecord && model.editing == nil && !model.showSettings && !model.showWidgetPreview }, set: { if !$0 { model.error = nil } })) {
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
    @State private var showHealthInfo = false
    private var recent: [LogEntry] { Array(model.entries.prefix(3)) }
    private var weekEntries: [LogEntry] {
        let start = Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: Date()))!
        return model.entries.filter { $0.occurredAt >= start && $0.occurredAt <= Date() }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("排便记录").font(.system(.title2, design: .rounded, weight: .bold))
                        Spacer()
                        HStack(spacing: 3) {
                            Text("今天"); Text("\(model.today.count)").fontWeight(.semibold).accessibilityIdentifier("entry-count"); Text("次")
                        }.font(.subheadline).foregroundStyle(PupuStyle.muted)
                        Button { model.showSettings = true } label: { Image(systemName: "slider.horizontal.3").frame(width: 40, height: 40) }.accessibilityLabel("设置")
                    }
                    TimelineView(.periodic(from: Date(), by: 60)) { context in
                        VStack(alignment: .leading, spacing: 8) {
                            Text("距上次排便").font(.subheadline).foregroundStyle(PupuStyle.muted)
                            if let last = model.entries.first {
                                Text(interval(since: last.occurredAt, now: context.date)).font(.system(size: typeSize.isAccessibilitySize ? 34 : 40, weight: .bold, design: .rounded)).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("last-bowel-interval")
                                Text(last.occurredAt, format: .dateTime.month().day().hour().minute()).font(.caption).foregroundStyle(PupuStyle.muted)
                                if hasConstipationRelatedDetails(last) {
                                    HStack(spacing: 6) {
                                        Circle().fill(Color(red: 0.69, green: 0.39, blue: 0.19)).frame(width: 7, height: 7)
                                        Text("便秘相关表现").font(.caption.weight(.semibold))
                                        Text(healthDetails(last)).font(.caption).foregroundStyle(PupuStyle.muted)
                                        Spacer(minLength: 0)
                                        Button { showHealthInfo = true } label: { Image(systemName: "info.circle").frame(width: 30, height: 30) }.accessibilityLabel("关于便秘相关表现")
                                    }.padding(.top, 3)
                                }
                            } else {
                                Text("尚无排便记录").font(.system(.title, design: .rounded, weight: .bold))
                                Text("从第一次记录开始计算间隔").font(.caption).foregroundStyle(PupuStyle.muted)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("近 7 天").font(.headline)
                            Spacer()
                            Text("已记录 \(weekEntries.count) 次").font(.subheadline.weight(.semibold))
                            let hard = weekEntries.filter { $0.bristol == 1 || $0.bristol == 2 }.count
                            if hard > 0 { Text("· 偏硬 \(hard) 次").font(.caption).foregroundStyle(PupuStyle.muted) }
                        }
                        WeekStrip(entries: model.entries) { day in model.requestedHistoryDate = day; model.selectedTab = 1 }

                    }.padding(.vertical, 12).padding(.horizontal, 12).background(PupuStyle.sage.opacity(0.60), in: RoundedRectangle(cornerRadius: 18))
                    VStack(alignment: .leading, spacing: 8) {
                        HStack { Text("最近排便").font(.headline); Spacer(); Button("全部记录") { model.selectedTab = 1 }.font(.caption) }
                        if recent.isEmpty {
                            Text("记录后，这里显示形态、费力程度和时间").font(.subheadline).foregroundStyle(PupuStyle.muted).padding(.vertical, 18)
                        } else {
                            ForEach(recent) { entry in
                                Button { model.editing = entry } label: { EntryRow(entry: entry, compact: true) }.buttonStyle(.plain)
                                if entry.id != recent.last?.id { Divider() }
                            }
                        }
                    }

                }.padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 12)
            }.paper()
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 4) {
                    if let toast = model.toast {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(PupuStyle.green)
                            Text(toast).font(.caption)
                            Spacer(minLength: 0)
                            if model.undoID != nil { Button("撤销") { model.undoSave() }.font(.subheadline.weight(.semibold)).accessibilityIdentifier("undo-save") }
                            else { Button { model.toast = nil } label: { Image(systemName: "xmark").frame(width: 28, height: 28) }.accessibilityLabel("关闭提示") }
                        }.padding(.vertical, 5).accessibilityElement(children: .contain)
                    }
                    HStack(spacing: 12) {
                        Button { model.quickSave() } label: {
                            Label("记录排便", systemImage: "plus").font(.headline).frame(maxWidth: .infinity).frame(minHeight: 54).foregroundStyle(PupuStyle.onGreen).background(PupuStyle.green, in: RoundedRectangle(cornerRadius: 17))
                        }.disabled(model.isLoading).accessibilityIdentifier("quick-save")
                        Button(model.undoID == nil ? "详细记录" : "补充刚才记录") { model.openDetailedRecord() }.font(.subheadline.weight(.semibold)).frame(minWidth: 74, minHeight: 54).disabled(model.isLoading).accessibilityIdentifier("open-record")
                    }
                }.padding(.horizontal, 20).padding(.vertical, 10).background(PupuStyle.paper)
            }
            .toolbar(.hidden, for: .navigationBar)
            .alert("便秘相关表现", isPresented: $showHealthInfo) { Button("知道了", role: .cancel) {} } message: {
                Text("未排便时长与频次按记录计算，默认未记录即未排便；漏记后补记会自动重新计算。干硬或结块、排便费力或疼痛、排不尽感可能与便秘相关，但这些记录不能单独诊断便秘。依据：NIDDK、NHS 便秘说明。")
            }
        }
    }
    private func interval(since date: Date, now: Date) -> String {
        let seconds = now.timeIntervalSince(date)
        guard seconds >= 0 else { return "记录时间在未来" }
        let minutes = Int(seconds / 60), hours = minutes / 60, days = hours / 24
        if days > 0 { return "\(days) 天 \(hours % 24) 小时" }
        if hours > 0 { return "\(hours) 小时 \(minutes % 60) 分钟" }
        return minutes > 0 ? "\(minutes) 分钟" : "刚刚"
    }
    private func hasConstipationRelatedDetails(_ entry: LogEntry) -> Bool {
        entry.bristol == 1 || entry.bristol == 2 || ["有点费力", "很费力"].contains(entry.effort ?? "") || !(Set(entry.symptoms ?? []).intersection(["疼痛", "未尽感"])).isEmpty
    }
    private func healthDetails(_ entry: LogEntry) -> String {
        var items: [String] = []
        if entry.bristol == 1 || entry.bristol == 2 { items.append("偏硬") }
        if ["有点费力", "很费力"].contains(entry.effort ?? "") { items.append("费力") }
        if (entry.symptoms ?? []).contains("未尽感") { items.append("未尽感") }
        if (entry.symptoms ?? []).contains("疼痛") { items.append("疼痛") }
        return items.joined(separator: " · ")
    }
}
struct WeekStrip: View {
    let entries: [LogEntry]
    var action: (Date) -> Void = { _ in }
    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            ForEach(0..<7) { offset in
                let day = Calendar.current.date(byAdding: .day, value: offset - 6, to: Date())!
                let count = entries.filter { Calendar.current.isDate($0.occurredAt, inSameDayAs: day) }.count
                Button { action(day) } label: {
                    VStack(spacing: 5) {
                        Text(offset == 6 ? "今天" : day.formatted(.dateTime.weekday(.narrow))).font(.caption2).foregroundStyle(PupuStyle.muted)
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 4).fill(PupuStyle.green.opacity(0.06)).frame(height: 38)
                            if count > 0 { RoundedRectangle(cornerRadius: 4).fill(PupuStyle.green.opacity(0.55)).frame(height: CGFloat(min(count, 4)) * 8 + 6) }
                            Text("\(count)").font(.system(.headline, design: .rounded)).padding(.bottom, 7)
                        }
                        Text(day, format: .dateTime.day()).font(.caption2).foregroundStyle(PupuStyle.muted)
                    }.frame(maxWidth: .infinity)
                }.buttonStyle(.plain).accessibilityLabel("\(day.formatted(date: .abbreviated, time: .omitted))，\(count)次排便")
            }
        }
    }
}
struct EntryRow: View {
    let entry: LogEntry
    var compact = false
    var body: some View {
        HStack(spacing: 11) {
            StoolIllustration(type: entry.bristol).frame(width: 46, height: 40).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(entry.occurredAt, format: .dateTime.month().day().hour().minute()).font(.system(.subheadline, design: .rounded, weight: .semibold))
                    Spacer(minLength: 0)
                    if let type = entry.bristol { Text("\(type)型").font(.caption2).foregroundStyle(PupuStyle.muted) }
                }
                Text(details).font(.caption).foregroundStyle(PupuStyle.muted).lineLimit(2)
            }
            Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(PupuStyle.muted)
        }.padding(compact ? 4 : 16).frame(minHeight: compact ? 58 : 68).background(compact ? .clear : PupuStyle.card, in: RoundedRectangle(cornerRadius: 16)).accessibilityElement(children: .combine)
    }
    private var details: String {
        var items = [entry.bristol.map { BristolMetadata.label(for: $0) } ?? "形态未填"]
        if let effort = entry.effort { items.append(effort) }
        if let symptoms = entry.symptoms, !symptoms.isEmpty { items.append(symptoms.prefix(2).joined(separator: "、")) }
        return items.joined(separator: " · ")
    }
}

private struct TestTypography: ViewModifier {
    @Environment(\.dynamicTypeSize) private var inherited
    let enabled: Bool
    func body(content: Content) -> some View {
        content.environment(\.dynamicTypeSize, enabled ? .accessibility3 : inherited)
    }
}
