import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var month = Date()
    @State private var selectedDate: Date?
    @State private var query = ""
    @State private var type = 0
    private let calendar = Calendar.current
    private var filtered: [LogEntry] {
        model.entries.filter { entry in
            (selectedDate == nil || calendar.isDate(entry.occurredAt, inSameDayAs: selectedDate!)) &&
            (type == 0 || entry.bristol == type) &&
            (query.isEmpty || (entry.note ?? "").localizedCaseInsensitiveContains(query) || (entry.symptoms ?? []).joined(separator: " ").localizedCaseInsensitiveContains(query))
        }
    }
    private var groups: [(Date, [LogEntry])] {
        Dictionary(grouping: filtered) { calendar.startOfDay(for: $0.occurredAt) }.sorted { $0.key > $1.key }
    }
    var body: some View {
        let dayCounts = Dictionary(grouping: model.entries) { calendar.startOfDay(for: $0.occurredAt) }.mapValues(\.count)
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    VStack(spacing: 17) {
                        if typeSize.isAccessibilitySize {
                            Text("按日期查看").font(.headline).frame(maxWidth: .infinity, alignment: .leading)
                            DatePicker("日期", selection: Binding(get: { selectedDate ?? Date() }, set: { selectedDate = $0 }), displayedComponents: .date)
                                .datePickerStyle(.compact).labelsHidden().accessibilityLabel("筛选日期").frame(maxWidth: .infinity, alignment: .leading)
                            Button("显示全部记录") { selectedDate = nil }.frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                        HStack {
                            Button { moveMonth(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }.accessibilityLabel("上个月")
                            Spacer()
                            Text(month, format: .dateTime.year().month(.wide)).font(.system(.headline, design: .rounded))
                            Spacer()
                            Button { moveMonth(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }.accessibilityLabel("下个月")
                        }
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 5) {
                            ForEach(0..<7) { i in Text(calendar.veryShortStandaloneWeekdaySymbols[(i + calendar.firstWeekday - 1) % 7]).font(.caption).foregroundStyle(PupuStyle.muted).frame(minHeight: 24) }
                            ForEach(Array(monthDays.enumerated()), id: \.offset) { _, day in
                                if let day {
                                    let active = selectedDate.map { calendar.isDate(day, inSameDayAs: $0) } ?? false
                                    let count = dayCounts[calendar.startOfDay(for: day)] ?? 0
                                    Button { selectedDate = active ? nil : day } label: {
                                        VStack(spacing: 3) {
                                            Text(day, format: .dateTime.day()).font(.system(.subheadline, design: .rounded, weight: active ? .bold : .regular))
                                            Circle().fill(count > 0 ? (active ? PupuStyle.onGreen : PupuStyle.green) : .clear).frame(width: 4, height: 4)
                                        }.frame(maxWidth: .infinity, minHeight: 44).background(active ? PupuStyle.green : .clear, in: RoundedRectangle(cornerRadius: 13)).foregroundStyle(active ? PupuStyle.onGreen : PupuStyle.ink)
                                    }.accessibilityLabel("\(day.formatted(date: .complete, time: .omitted))，\(count) 条记录").accessibilityAddTraits(active ? .isSelected : [])
                                } else { Color.clear.frame(height: 44) }
                            }
                        }
                        }
                    }.diaryCard()
                    HStack {
                        if let date = selectedDate { Button { selectedDate = nil } label: { Label(date.formatted(.dateTime.month().day()), systemImage: "xmark.circle.fill") }.font(.caption) }
                        else { Text("全部排便").font(.headline) }
                        Spacer()
                        Picker("形态筛选", selection: $type) { Text("全部形态").tag(0); ForEach(1...7, id: \.self) { Text("类型 \($0)").tag($0) } }.pickerStyle(.menu).font(.caption)
                    }
                    if groups.isEmpty {
                        VStack(spacing: 13) { Dumpling().frame(width: 95, height: 105); Text("这里暂时没有记录").font(.headline); Text("换个日期或筛选条件看看").font(.caption).foregroundStyle(PupuStyle.muted) }.frame(maxWidth: .infinity).padding(25)
                    }
                    ForEach(groups, id: \.0) { date, entries in
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeading(title: date.formatted(.dateTime.month().day().weekday(.wide)), detail: "\(entries.count) 条")
                            ForEach(entries) { entry in Button { model.editing = entry } label: { EntryRow(entry: entry) }.buttonStyle(.plain) }
                        }
                    }
                }.padding(20).padding(.bottom, 20)
            }.paper().navigationTitle("排便历史")
            .searchable(text: $query, prompt: "搜索备注与感受")
            .onAppear(perform: applyRequestedDate)
            .onChange(of: model.requestedHistoryDate) { _, _ in applyRequestedDate() }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { model.recordDate = selectedDate; model.showRecord = true } label: { Image(systemName: "plus") }.accessibilityLabel("新建记录") } }
        }
    }
    private func applyRequestedDate() {
        guard let date = model.requestedHistoryDate else { return }
        selectedDate = date; month = date; model.requestedHistoryDate = nil
    }
    private var monthDays: [Date?] {
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: month))!
        let offset = (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7
        let count = calendar.range(of: .day, in: .month, for: start)!.count
        return Array(repeating: nil, count: offset) + (0..<count).map { calendar.date(byAdding: .day, value: $0, to: start) }
    }
    private func moveMonth(_ step: Int) { month = calendar.date(byAdding: .month, value: step, to: month)! }
}
