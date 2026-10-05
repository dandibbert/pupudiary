import SwiftUI
import WidgetKit

struct DiaryTimelineEntry: TimelineEntry {
    let date: Date
    let count: Int
    let last: Date?
    let sharedAvailable: Bool
    let discreet: Bool
    let error: Bool
}
struct DiaryProvider: TimelineProvider {
    func placeholder(in context: Context) -> DiaryTimelineEntry { DiaryTimelineEntry(date: Date(), count: 0, last: nil, sharedAvailable: true, discreet: false, error: false) }
    func getSnapshot(in context: Context, completion: @escaping (DiaryTimelineEntry) -> Void) { completion(read()) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<DiaryTimelineEntry>) -> Void) {
        let entry = read()
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
    private func read() -> DiaryTimelineEntry {
        let discreet = StorageLocation.sharedPreferences?.bool(forKey: "discreet") ?? false
        guard let directory = StorageLocation.sharedDirectory else { return DiaryTimelineEntry(date: Date(), count: 0, last: nil, sharedAvailable: false, discreet: true, error: false) }
        do {
            let store = try DiaryStore(url: StorageLocation.database(in: directory))
            let entries = try store.entries()
            return DiaryTimelineEntry(date: Date(), count: entries.filter { Calendar.current.isDateInToday($0.occurredAt) }.count, last: entries.first?.occurredAt, sharedAvailable: true, discreet: discreet, error: false)
        } catch { return DiaryTimelineEntry(date: Date(), count: 0, last: nil, sharedAvailable: false, discreet: true, error: true) }
    }
}
struct DiaryWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DiaryTimelineEntry
    var body: some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 8 : 12) {
            PupuWidgetContent(count: entry.count, last: entry.last, discreet: entry.discreet, sharedAvailable: entry.sharedAvailable, compact: family == .systemSmall)
            if entry.sharedAvailable {
                Button(intent: QuickLogIntent()) { Label("记下此刻", systemImage: "plus").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 10) }.buttonStyle(.plain).background(PupuStyle.green, in: Capsule()).foregroundStyle(PupuStyle.onGreen)
            } else {
                Link(destination: URL(string: "pupudiary://record")!) { Label("打开 App 记录", systemImage: "arrow.up.right").font(.caption.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 10) }.background(PupuStyle.green, in: Capsule()).foregroundStyle(PupuStyle.onGreen)
            }
        }.containerBackground(PupuStyle.sage, for: .widget).widgetURL(URL(string: "pupudiary://home"))
    }
}
@main struct PupudiaryWidget: Widget {
    let kind = "PupudiaryWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DiaryProvider()) { entry in DiaryWidgetView(entry: entry) }
            .configurationDisplayName("噗噗手帐").description("看看今天的记录，轻轻一点记下此刻。详情默认留空，可在 App 补充或撤销。")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}
