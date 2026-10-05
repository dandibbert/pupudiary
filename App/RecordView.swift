import SwiftUI

struct RecordView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let entry: LogEntry?
    @State private var date: Date
    @State private var bristol: Int?
    @State private var color: String?
    @State private var amount: String?
    @State private var effort: String?
    @State private var symptoms: Set<String>
    @State private var symptomsSpecified: Bool
    @State private var duration = ""
    @State private var note: String
    @State private var deleteConfirmation = false
    init(entry: LogEntry?) {
        self.entry = entry
        _date = State(initialValue: entry?.occurredAt ?? Date())
        _bristol = State(initialValue: entry?.bristol)
        _color = State(initialValue: entry?.color)
        _amount = State(initialValue: entry?.amount)
        _effort = State(initialValue: entry?.effort)
        _symptoms = State(initialValue: Set(entry?.symptoms ?? []))
        _symptomsSpecified = State(initialValue: entry?.symptoms != nil)
        _duration = State(initialValue: entry?.durationMinutes.map(String.init) ?? "")
        _note = State(initialValue: entry?.note ?? "")
    }
    private let types = ["分散硬粒", "成团条状", "表面裂纹", "柔软光滑", "柔软小块", "松散糊状", "水样"]
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(spacing: 12) {
                        Dumpling().frame(width: 59, height: 67)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("记一笔，轻轻松松").font(.system(.title3, design: .rounded, weight: .bold))
                            Text("除了时间，下面都可以留空").font(.caption).foregroundStyle(PupuStyle.muted)
                        }
                    }
                    DatePicker("发生时间", selection: $date, in: ...Date(), displayedComponents: [.date, .hourAndMinute]).font(.subheadline).diaryCard()
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeading(title: "形态", detail: "Bristol 分类 · 选填")
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 8)], spacing: 8) {
                            ForEach(1...7, id: \.self) { type in
                                Button { bristol = bristol == type ? nil : type } label: {
                                    VStack(spacing: 7) {
                                        Text(String(type)).font(.system(.title3, design: .rounded, weight: .semibold)).frame(width: 30, height: 30).background(bristol == type ? PupuStyle.green : PupuStyle.sage, in: Circle()).foregroundStyle(bristol == type ? PupuStyle.onGreen : PupuStyle.green)
                                        Text(types[type - 1]).font(.caption)
                                    }.frame(maxWidth: .infinity, minHeight: 69).padding(8).background(bristol == type ? PupuStyle.sage : PupuStyle.card, in: RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).stroke(bristol == type ? PupuStyle.green : .clear, lineWidth: 1.5))
                                }.buttonStyle(.plain).accessibilityLabel("类型 \(type)，\(types[type - 1])").accessibilityAddTraits(bristol == type ? .isSelected : [])
                            }
                        }
                        Text("只帮助描述外观，不代表诊断或健康评分").font(.caption2).foregroundStyle(PupuStyle.muted)
                    }
                    ChoiceSection(title: "顺不顺利", options: ["轻松", "有点费力", "很费力"], selection: $effort)
                    ChoiceSection(title: "颜色", options: ["棕色", "浅棕", "黄色", "绿色", "黑色", "红色", "灰白"], selection: $color)
                    ChoiceSection(title: "大概多少", options: ["少量", "适中", "较多"], selection: $amount)
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeading(title: "其他感受", detail: "选填 · 可多选")
                        Toggle("记录这次的感受", isOn: $symptomsSpecified).font(.subheadline)
                        if symptomsSpecified {
                            FlowChoices(options: ["腹胀", "腹痛", "急迫", "未尽感", "疼痛", "见血"], isSelected: { symptoms.contains($0) }) { option in
                                if symptoms.contains(option) { symptoms.remove(option) } else { symptoms.insert(option) }
                            }
                            if symptoms.isEmpty { Text("已选择：没有上述感受").font(.caption).foregroundStyle(PupuStyle.muted) }
                        }
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("用时").font(.headline); Spacer()
                            TextField("未填写", text: $duration).keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 90).accessibilityLabel("用时分钟").accessibilityIdentifier("duration-field")
                            Text("分钟").font(.subheadline).foregroundStyle(PupuStyle.muted)
                        }
                        TextField("想补充的事情…", text: $note, axis: .vertical).lineLimit(3...6).padding(14).background(PupuStyle.card, in: RoundedRectangle(cornerRadius: 14)).accessibilityLabel("备注").accessibilityIdentifier("note-field")
                    }
                    if entry != nil {
                        Button("移入最近删除", role: .destructive) { deleteConfirmation = true }.frame(maxWidth: .infinity).padding(.top, 8)
                    }
                }.padding(22).padding(.bottom, 24)
            }.paper().scrollDismissesKeyboard(.interactively)
            .navigationTitle(entry == nil ? "新的一笔" : "这一笔的详情").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.accessibilityIdentifier("cancel-record") }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { save() }.fontWeight(.semibold).accessibilityIdentifier("save-record") }
            }
            .alert("请检查一下", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
                Button("知道了", role: .cancel) { model.error = nil }
            } message: { Text(model.error ?? "") }
            .confirmationDialog("把这条记录移入最近删除？", isPresented: $deleteConfirmation, titleVisibility: .visible) {
                Button("移入最近删除", role: .destructive) { if let entry, model.delete(entry) { dismiss() } }
            } message: { Text("记录不会永久删除，可以在设置中恢复。") }
        }
    }
    private func save() {
        let trimmed = duration.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty || (Int(trimmed).map { (0...1440).contains($0) } ?? false) else { model.error = "用时请填写 0–1440 之间的整数分钟"; return }
        var value = entry ?? LogEntry()
        value.occurredAt = date; value.bristol = bristol; value.color = color; value.amount = amount; value.effort = effort
        value.symptoms = symptomsSpecified ? symptoms.sorted() : nil
        value.durationMinutes = Int(trimmed); value.note = note.isEmpty ? nil : note
        if model.save(value, existing: entry != nil) { dismiss() }
    }
}
struct ChoiceSection: View {
    let title: String
    let options: [String]
    @Binding var selection: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(title: title, detail: "选填")
            FlowChoices(options: options, isSelected: { selection == $0 }) { option in selection = selection == option ? nil : option }
        }
    }
}
struct FlowChoices: View {
    let options: [String]
    let isSelected: (String) -> Bool
    let action: (String) -> Void
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 9)], spacing: 9) {
            ForEach(options, id: \.self) { option in
                Button { action(option) } label: {
                    Text(option).font(.subheadline).frame(maxWidth: .infinity, minHeight: 44).padding(.horizontal, 5).background(isSelected(option) ? PupuStyle.sage : PupuStyle.card, in: Capsule()).overlay(Capsule().stroke(isSelected(option) ? PupuStyle.green : .clear, lineWidth: 1.5))
                }.buttonStyle(.plain).accessibilityAddTraits(isSelected(option) ? .isSelected : [])
            }
        }
    }
}
