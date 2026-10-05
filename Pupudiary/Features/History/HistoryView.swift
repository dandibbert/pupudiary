import SwiftUI

struct HistoryView: View {
    @Environment(RecordStore.self) private var store
    @State private var month = Calendar.current.startOfMonth(for: Date())
    @State private var selectedDay = Calendar.current.startOfDay(for: Date())
    @State private var editing: PoopRecord?
    @State private var creatingFor: NewRecordRequest?
    @State private var mode = Mode.calendar

    enum Mode: String, CaseIterable, Identifiable {
        case calendar = "日历", list = "全部列表"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            Group {
                switch mode {
                case .calendar: calendarMode
                case .list: listMode
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("记录日历")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("显示方式", selection: $mode) {
                        ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        creatingFor = NewRecordRequest(date: selectedDay)
                    } label: {
                        Image(systemName: "plus.circle.fill").font(.system(size: 20))
                    }
                    .accessibilityLabel("补一条记录")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(item: $editing) { RecordEditorView(record: $0) }
        .sheet(item: $creatingFor) { RecordEditorView(record: nil, defaultDate: $0.date) }
    }

    // MARK: 日历模式

    private var calendarMode: some View {
        let stats = store.stats
        let dayRecords = stats.records(on: selectedDay)
        return ScrollView {
            VStack(spacing: 16) {
                MonthCalendar(month: $month, selected: $selectedDay, stats: stats)
                    .cardStyle(padding: 12)

                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle(title: selectedDay.formatted(.dateTime.month().day().weekday(.wide)),
                                 symbol: "sun.max.fill",
                                 trailing: dayRecords.isEmpty ? nil : "\(dayRecords.count) 次")
                    if dayRecords.isEmpty {
                        EmptyHint(title: "这天没有记录",
                                  subtitle: selectedDay > Date() ? nil : "忘记记了？点右上角 ＋ 补一条")
                    } else {
                        ForEach(dayRecords) { r in
                            Button { editing = r } label: { RecordRow(record: r) }
                                .buttonStyle(.plain)
                            if r.id != dayRecords.last?.id { Divider() }
                        }
                    }
                }
                .cardStyle()
            }
            .padding(16)
            .padding(.bottom, 20)
        }
    }

    // MARK: 列表模式

    private var listMode: some View {
        let groups = Dictionary(grouping: store.records) { Calendar.current.startOfDay(for: $0.timestamp) }
        let days = groups.keys.sorted(by: >)
        return Group {
            if store.records.isEmpty {
                ScrollView {
                    EmptyHint(title: "还没有任何记录", subtitle: "回到「今天」点一下就能开始啦", mood: .happy)
                        .padding(.top, 80)
                }
            } else {
                List {
                    ForEach(days, id: \.self) { day in
                        let items = groups[day] ?? []
                        Section {
                            ForEach(items) { r in
                                Button { editing = r } label: { RecordRow(record: r) }
                                    .buttonStyle(.plain)
                                    .listRowBackground(Theme.card)
                                    .swipeActions {
                                        Button(role: .destructive) {
                                            store.delete(r)
                                        } label: {
                                            Label("删除", systemImage: "trash")
                                        }
                                    }
                            }
                        } header: {
                            HStack {
                                Text(day.formatted(.dateTime.year().month().day().weekday(.abbreviated)))
                                Spacer()
                                Text("\(items.count) 次")
                            }
                            .font(.cute(13, .bold))
                            .foregroundStyle(Theme.subtle)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
    }
}

/// 给某一天补记录的请求
struct NewRecordRequest: Identifiable {
    let id = UUID()
    let date: Date
}

extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        self.date(from: dateComponents([.year, .month], from: date)) ?? date
    }
}

// MARK: - 月历

struct MonthCalendar: View {
    @Binding var month: Date
    @Binding var selected: Date
    let stats: GutStats

    private let cal = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Button { shift(-1) } label: {
                    Image(systemName: "chevron.left.circle.fill").font(.system(size: 26))
                }
                .accessibilityLabel("上个月")
                Spacer()
                VStack(spacing: 0) {
                    Text(month.formatted(.dateTime.year().month(.wide)))
                        .font(.cute(18, .heavy))
                        .foregroundStyle(Theme.ink)
                    Text(monthSummary)
                        .font(.cute(12, .medium))
                        .foregroundStyle(Theme.subtle)
                }
                Spacer()
                Button { shift(1) } label: {
                    Image(systemName: "chevron.right.circle.fill").font(.system(size: 26))
                }
                .disabled(isCurrentMonth)
                .accessibilityLabel("下个月")
            }
            .foregroundStyle(Theme.primary)

            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(weekdaySymbols, id: \.self) { w in
                    Text(w).font(.cute(12, .bold)).foregroundStyle(Theme.subtle)
                }
                ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                    if let day {
                        dayCell(day)
                    } else {
                        Color.clear.frame(height: 46)
                    }
                }
            }

            StatusLegend()
            Button("回到今天") {
                withAnimation {
                    month = cal.startOfMonth(for: Date())
                    selected = cal.startOfDay(for: Date())
                }
            }
            .font(.cute(13, .bold))
            .foregroundStyle(Theme.primary)
            .opacity(isCurrentMonth && cal.isDateInToday(selected) ? 0 : 1)
        }
        .gesture(
            DragGesture(minimumDistance: 30).onEnded { v in
                if v.translation.width < -50, !isCurrentMonth { shift(1) }
                if v.translation.width > 50 { shift(-1) }
            }
        )
    }

    private func dayCell(_ day: Date) -> some View {
        let records = stats.records(on: day)
        let summary = DaySummary(day: day, records: records)
        let isSelected = cal.isDate(day, inSameDayAs: selected)
        let isToday = cal.isDateInToday(day)
        let isFuture = day > Date()
        return Button {
            selected = day
            Haptics.tap()
        } label: {
            VStack(spacing: 3) {
                Text("\(cal.component(.day, from: day))")
                    .font(.cute(14, isToday ? .heavy : .semibold))
                    .foregroundStyle(isFuture ? Theme.subtle.opacity(0.4) : (isToday ? Theme.primary : Theme.ink))
                HStack(spacing: 2) {
                    if records.isEmpty {
                        Circle().fill(.clear).frame(width: 6, height: 6)
                    } else {
                        ForEach(Array(records.prefix(3).enumerated()), id: \.offset) { _, r in
                            StatusDot(status: r.status, size: 6)
                        }
                        if records.count > 3 {
                            Text("+").font(.system(size: 8, weight: .bold)).foregroundStyle(Theme.subtle)
                        }
                    }
                }
                .frame(height: 8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? (summary.dominantStatus?.softColor ?? Theme.primarySoft) : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isSelected ? (summary.dominantStatus?.color ?? Theme.primary) : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .disabled(isFuture)
        .accessibilityLabel("\(day.formatted(.dateTime.month().day()))，\(records.count) 次")
    }

    private var weekdaySymbols: [String] {
        let s = ["日", "一", "二", "三", "四", "五", "六"]
        let first = cal.firstWeekday - 1
        return Array(s[first...] + s[..<first])
    }

    private var cells: [Date?] {
        guard let range = cal.range(of: .day, in: .month, for: month) else { return [] }
        let weekday = cal.component(.weekday, from: month)
        let leading = (weekday - cal.firstWeekday + 7) % 7
        var result: [Date?] = Array(repeating: nil, count: leading)
        for d in range {
            result.append(cal.date(byAdding: .day, value: d - 1, to: month))
        }
        return result
    }

    private var isCurrentMonth: Bool {
        cal.isDate(month, equalTo: Date(), toGranularity: .month)
    }

    private var monthSummary: String {
        let list = stats.records.filter { cal.isDate($0.timestamp, equalTo: month, toGranularity: .month) }
        guard !list.isEmpty else { return "本月暂无记录" }
        let ideal = list.filter { $0.status == .ideal }.count
        return "共 \(list.count) 次 · 理想 \(Int((Double(ideal) / Double(list.count) * 100).rounded()))%"
    }

    private func shift(_ delta: Int) {
        if let m = cal.date(byAdding: .month, value: delta, to: month) {
            withAnimation(.easeInOut(duration: 0.2)) { month = m }
        }
    }
}
