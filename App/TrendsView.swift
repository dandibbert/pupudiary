import SwiftUI

struct TrendsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var days = 7
    private var period: [LogEntry] {
        let start = Calendar.current.date(byAdding: .day, value: 1 - days, to: Calendar.current.startOfDay(for: Date()))!
        return model.entries.filter { $0.occurredAt >= start && $0.occurredAt <= Date() }
    }
    private var recordedDays: Int { Set(period.map { Calendar.current.startOfDay(for: $0.occurredAt) }).count }
    var body: some View {
        let records = period
        let dayCounts = Dictionary(grouping: records) { Calendar.current.startOfDay(for: $0.occurredAt) }.mapValues(\.count)
        let maximumCount = max(1, dayCounts.values.max() ?? 1)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("看见自己的节奏").font(.subheadline).foregroundStyle(PupuStyle.muted)
                    Picker("统计周期", selection: $days) { Text("近 7 天").tag(7); Text("近 30 天").tag(30) }.pickerStyle(.segmented)
                    HStack(spacing: 12) {
                        stat("记录次数", value: "\(records.count)", unit: "次", color: PupuStyle.sage)
                        stat("有记录的日子", value: "\(recordedDays)", unit: "天", color: PupuStyle.peach)
                    }
                    VStack(alignment: .leading, spacing: 18) {
                        SectionHeading(title: "每天的记录", detail: "次数")
                        if typeSize.isAccessibilitySize {
                            ForEach(0..<days, id: \.self) { offset in
                                let date = Calendar.current.date(byAdding: .day, value: offset + 1 - days, to: Date())!
                                let count = dayCounts[Calendar.current.startOfDay(for: date)] ?? 0
                                HStack(alignment: .firstTextBaseline) {
                                    Text(date, format: .dateTime.month().day())
                                    Spacer(minLength: 8)
                                    Text("\(count) 次").monospacedDigit()
                                }.font(.body).padding(.vertical, 4).accessibilityElement(children: .combine)
                            }
                        } else {
                        HStack(alignment: .bottom, spacing: days == 7 ? 13 : 3) {
                            ForEach(0..<days, id: \.self) { offset in
                                let date = Calendar.current.date(byAdding: .day, value: offset + 1 - days, to: Date())!
                                let count = dayCounts[Calendar.current.startOfDay(for: date)] ?? 0
                                VStack(spacing: 7) {
                                    if days == 7 { Text("\(count)").font(.caption2).foregroundStyle(PupuStyle.muted) }
                                    RoundedRectangle(cornerRadius: days == 7 ? 8 : 3).fill(count == 0 ? PupuStyle.sage.opacity(0.5) : PupuStyle.green).frame(height: max(5, CGFloat(count) / CGFloat(maximumCount) * 90))
                                    if days == 7 { Text(date, format: .dateTime.day()).font(.caption2).foregroundStyle(PupuStyle.muted) }
                                }.frame(maxWidth: .infinity).accessibilityElement(children: .ignore).accessibilityLabel("\(date.formatted(date: .abbreviated, time: .omitted))，\(count) 次")
                            }
                        }.frame(minHeight: 133, alignment: .bottom)
                        }
                        Text("未记录不等于没有发生，图表仅展示已保存的记录").font(.caption2).foregroundStyle(PupuStyle.muted)
                    }.diaryCard()
                    VStack(alignment: .leading, spacing: 17) {
                        SectionHeading(title: "形态分布", detail: "已填写 \(records.filter { $0.bristol != nil }.count) 条")
                        ForEach(1...7, id: \.self) { type in
                            let count = records.filter { $0.bristol == type }.count
                            if typeSize.isAccessibilitySize {
                                HStack(alignment: .firstTextBaseline) {
                                    Text("类型 \(type)")
                                    Spacer(minLength: 8)
                                    Text("\(count) 条").monospacedDigit()
                                }.font(.body).accessibilityElement(children: .combine)
                            } else {
                            HStack(spacing: 11) {
                                Text("类型 \(type)").font(.caption).frame(width: 46, alignment: .leading)
                                GeometryReader { g in ZStack(alignment: .leading) { Capsule().fill(PupuStyle.sage.opacity(0.5)); Capsule().fill(PupuStyle.green.opacity(0.75)).frame(width: records.isEmpty ? 0 : g.size.width * CGFloat(count) / CGFloat(max(1, records.count))) } }.frame(height: 10)
                                Text("\(count)").font(.caption.monospacedDigit()).frame(width: 22, alignment: .trailing)
                            }
                            }
                        }
                        Text("未填写形态：\(records.filter { $0.bristol == nil }.count) 条").font(.caption).foregroundStyle(PupuStyle.muted)
                    }.diaryCard()
                    HStack(alignment: .top, spacing: 11) {
                        Image(systemName: "heart.text.clipboard").font(.title3)
                        Text("这里只是你的记录摘要，不做健康评分，也不替代医疗建议。如有持续不适或出血，请及时咨询专业医护人员。").font(.caption).fixedSize(horizontal: false, vertical: true)
                    }.foregroundStyle(PupuStyle.muted).diaryCard(PupuStyle.lavender.opacity(0.65))
                }.padding(22).padding(.bottom, 22)
            }.paper().navigationTitle("我的节奏")
        }
    }
    private var maximum: Int {
        max(1, Dictionary(grouping: period) { Calendar.current.startOfDay(for: $0.occurredAt) }.values.map(\.count).max() ?? 1)
    }
    private func stat(_ title: String, value: String, unit: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) { Text(title).font(.caption).foregroundStyle(PupuStyle.muted); HStack(alignment: .firstTextBaseline, spacing: 4) { Text(value).font(.system(.largeTitle, design: .rounded, weight: .semibold)); Text(unit).font(.caption).foregroundStyle(PupuStyle.muted) } }.frame(maxWidth: .infinity, alignment: .leading).diaryCard(color)
    }
}
