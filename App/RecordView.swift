import SwiftUI

struct RecordView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    let entry: LogEntry?
    @State private var date: Date
    @State private var bristol: Int?
    @State private var color: String?
    @State private var amount: String?
    @State private var effort: String?
    @State private var symptoms: Set<String>
    @State private var symptomsSpecified: Bool
    @State private var duration: String
    @State private var note: String
    @State private var detailsExpanded: Bool
    @State private var deleteConfirmation = false

    init(entry: LogEntry?, initialDate: Date? = nil) {
        self.entry = entry
        _date = State(initialValue: entry?.occurredAt ?? initialDate ?? Date())
        _bristol = State(initialValue: entry?.bristol)
        _color = State(initialValue: entry?.color)
        _amount = State(initialValue: entry?.amount)
        _effort = State(initialValue: entry?.effort)
        _symptoms = State(initialValue: Set(entry?.symptoms ?? []))
        _symptomsSpecified = State(initialValue: entry?.symptoms != nil)
        _duration = State(initialValue: entry?.durationMinutes.map(String.init) ?? "")
        _note = State(initialValue: entry?.note ?? "")
        _detailsExpanded = State(initialValue: entry?.symptoms != nil || entry?.durationMinutes != nil || entry?.note != nil)
    }

    private var fourColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 0), spacing: 8), count: typeSize.isAccessibilitySize ? 2 : 4)
    }
    private var threeColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 0), spacing: 8), count: typeSize.isAccessibilitySize ? 1 : 3)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    timestamp
                    shapeSection
                    effortSection
                    colorSection
                    amountSection
                    moreDetails
                    if entry != nil {
                        Button("移入最近删除", role: .destructive) { deleteConfirmation = true }
                            .frame(maxWidth: .infinity).padding(.top, 8)
                    }
                }
                .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 28)
            }
            .paper().scrollDismissesKeyboard(.interactively)
            .navigationTitle(entry == nil ? "记录排便" : "编辑排便")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }.accessibilityIdentifier("cancel-record")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }.fontWeight(.semibold).accessibilityIdentifier("save-record")
                }
            }
            .alert("请检查一下", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
                Button("知道了", role: .cancel) { model.error = nil }
            } message: { Text(model.error ?? "") }
            .confirmationDialog("把这条记录移入最近删除？", isPresented: $deleteConfirmation, titleVisibility: .visible) {
                Button("移入最近删除", role: .destructive) { if let entry, model.delete(entry) { dismiss() } }
            } message: { Text("记录不会永久删除，可以在设置中恢复。") }
        }
    }

    private var timestamp: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    Text("发生时间").font(.subheadline)
                    DatePicker("发生时间", selection: $date, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden().datePickerStyle(.compact)
                }
            } else {
                DatePicker("发生时间", selection: $date, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                    .font(.subheadline).datePickerStyle(.compact)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(PupuStyle.card, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityIdentifier("record-timestamp")
    }

    private var shapeSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionHeading(title: "形态", detail: "Bristol 分类 · 选填")
            LazyVGrid(columns: fourColumns, spacing: 8) {
                ForEach(1...7, id: \.self) { type in
                    Button { bristol = bristol == type ? nil : type } label: {
                        BristolChoiceCell(type: type, selected: bristol == type)
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore).accessibilityAddTraits(.isButton).accessibilityHidden(false)
                    .accessibilityLabel(BristolMetadata.accessibilityLabel(for: type))
                    .accessibilityIdentifier("bristol-\(type)")
                    .accessibilityAddTraits(bristol == type ? .isSelected : [])
                    .accessibilityHint("再次点按可清除选择")
                }
                Button { bristol = nil } label: {
                    BristolChoiceCell(type: nil, selected: bristol == nil)
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore).accessibilityAddTraits(.isButton).accessibilityHidden(false)
                .accessibilityLabel("形态未选择")
                .accessibilityIdentifier("bristol-none")
                .accessibilityAddTraits(bristol == nil ? .isSelected : [])
            }
        }
    }

    private var effortSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionHeading(title: "费力程度", detail: "选填")
            LazyVGrid(columns: threeColumns, spacing: 8) {
                ForEach(Array(["轻松", "有点费力", "很费力"].enumerated()), id: \.element) { index, option in
                    Button { effort = effort == option ? nil : option } label: {
                        PictorialChoice(label: option, selected: effort == option) {
                            EffortIllustration(level: index + 1).frame(width: 34, height: 25)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore).accessibilityAddTraits(.isButton).accessibilityHidden(false).accessibilityLabel("费力程度，\(option)")
                    .accessibilityIdentifier("effort-\(["easy", "some", "hard"][index])")
                    .accessibilityAddTraits(effort == option ? .isSelected : [])
                }
            }
        }
    }

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionHeading(title: "颜色", detail: "选填")
            LazyVGrid(columns: fourColumns, spacing: 8) {
                ForEach(StoolColorOption.all) { option in
                    Button { color = color == option.name ? nil : option.name } label: {
                        PictorialChoice(label: option.name, selected: color == option.name) {
                            Circle().fill(option.swatch)
                                .overlay(Circle().strokeBorder(StoolIllustration.outline.opacity(0.45), lineWidth: 1))
                                .frame(width: 25, height: 25)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore).accessibilityAddTraits(.isButton).accessibilityHidden(false).accessibilityLabel("颜色，\(option.name)")
                    .accessibilityIdentifier("color-\(option.id)")
                    .accessibilityAddTraits(color == option.name ? .isSelected : [])
                }
            }
        }
    }

    private var amountSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionHeading(title: "大概多少", detail: "选填")
            LazyVGrid(columns: threeColumns, spacing: 8) {
                ForEach(Array(["少量", "适中", "较多"].enumerated()), id: \.element) { index, option in
                    Button { amount = amount == option ? nil : option } label: {
                        PictorialChoice(label: option, selected: amount == option) {
                            AmountIllustration(level: index + 1).frame(width: 36, height: 25)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore).accessibilityAddTraits(.isButton).accessibilityHidden(false).accessibilityLabel("大概多少，\(option)")
                    .accessibilityIdentifier("amount-\(index + 1)")
                    .accessibilityAddTraits(amount == option ? .isSelected : [])
                }
            }
        }
    }

    private var moreDetails: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { withAnimation(.easeInOut(duration: 0.2)) { detailsExpanded.toggle() } } label: {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("更多详情").font(.headline)
                        if !detailsExpanded {
                            Text(detailsSummary).font(.caption).foregroundStyle(PupuStyle.muted)
                                .lineLimit(2).multilineTextAlignment(.leading)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: detailsExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold)).foregroundStyle(PupuStyle.muted)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityIdentifier("more-details-toggle")
            .accessibilityLabel("更多详情")
            .accessibilityValue(detailsExpanded ? "已展开" : "已收起，\(detailsSummary)")
            .accessibilityHint(detailsExpanded ? "收起其他感受、用时和备注" : "展开其他感受、用时和备注")

            if detailsExpanded {
                VStack(alignment: .leading, spacing: 18) {
                    Divider().padding(.top, 8)
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeading(title: "其他感受", detail: "选填 · 可多选")
                        Toggle("记录这次的感受", isOn: $symptomsSpecified).font(.subheadline)
                            .accessibilityIdentifier("symptoms-specified")
                        if symptomsSpecified {
                            FlowChoices(options: ["腹胀", "腹痛", "急迫", "未尽感", "疼痛", "见血"], isSelected: { symptoms.contains($0) }) { option in
                                if symptoms.contains(option) { symptoms.remove(option) } else { symptoms.insert(option) }
                            }
                            if symptoms.isEmpty {
                                Text("已选择：没有上述感受").font(.caption).foregroundStyle(PupuStyle.muted)
                            }
                        }
                    }
                    HStack {
                        Text("用时").font(.headline)
                        Spacer(minLength: 8)
                        TextField("未填写", text: $duration).keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing).frame(minWidth: 70, maxWidth: 110)
                            .accessibilityLabel("用时分钟").accessibilityIdentifier("duration-field")
                        Text("分钟").font(.subheadline).foregroundStyle(PupuStyle.muted)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("备注").font(.headline)
                        TextField("想补充的事情…", text: $note, axis: .vertical).lineLimit(3...6)
                            .padding(12).background(PupuStyle.paper, in: RoundedRectangle(cornerRadius: 12))
                            .accessibilityLabel("备注").accessibilityIdentifier("note-field")
                    }
                }
            }
        }
        .padding(14).background(PupuStyle.card, in: RoundedRectangle(cornerRadius: 16))
    }

    private var detailsSummary: String {
        var values: [String] = []
        if symptomsSpecified { values.append(symptoms.isEmpty ? "没有上述感受" : symptoms.sorted().joined(separator: "、")) }
        if !duration.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { values.append("\(duration) 分钟") }
        if !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { values.append("备注：\(note)") }
        return values.isEmpty ? "其他感受、用时、备注 · 选填" : values.joined(separator: " · ")
    }

    private func save() {
        let trimmed = duration.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty || (Int(trimmed).map { (0...1440).contains($0) } ?? false) else {
            model.error = "用时请填写 0–1440 之间的整数分钟"; return
        }
        var value = entry ?? LogEntry()
        value.occurredAt = date; value.bristol = bristol; value.color = color; value.amount = amount; value.effort = effort
        value.symptoms = symptomsSpecified ? symptoms.sorted() : nil
        value.durationMinutes = Int(trimmed); value.note = note.isEmpty ? nil : note
        if model.save(value, existing: entry != nil) { dismiss() }
    }
}

private struct BristolChoiceCell: View {
    @ScaledMetric(relativeTo: .caption) private var numberSize = 12.0
    @ScaledMetric(relativeTo: .subheadline) private var labelSize = 14.0
    let type: Int?
    let selected: Bool

    var body: some View {
        VStack(spacing: 2) {
            StoolIllustration(type: type).frame(width: 54, height: 38)
            Text(type.map(String.init) ?? "—").font(.system(size: numberSize, weight: .medium))
                .foregroundStyle(PupuStyle.muted)
            Text(BristolMetadata.label(for: type)).font(.system(size: labelSize, weight: .medium))
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 3).padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 86)
        .modifier(RecordSelectionStyle(selected: selected))
    }
}

private struct PictorialChoice<Illustration: View>: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .subheadline) private var labelSize = 14.0
    let label: String
    let selected: Bool
    private let illustration: Illustration

    init(label: String, selected: Bool, @ViewBuilder illustration: () -> Illustration) {
        self.label = label
        self.selected = selected
        self.illustration = illustration()
    }

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                HStack(spacing: 10) {
                    illustration.accessibilityHidden(true)
                    Text(label).font(.system(size: labelSize, weight: .medium)).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }.padding(.horizontal, 12)
            } else {
                VStack(spacing: 5) {
                    illustration.accessibilityHidden(true)
                    Text(label).font(.system(size: labelSize, weight: .medium)).lineLimit(1).minimumScaleFactor(0.7)
                }.padding(.horizontal, 4)
            }
        }
        .padding(.vertical, 9).frame(maxWidth: .infinity, minHeight: 65)
        .modifier(RecordSelectionStyle(selected: selected))
    }
}

private struct RecordSelectionStyle: ViewModifier {
    let selected: Bool
    func body(content: Content) -> some View {
        content
            .background(selected ? PupuStyle.sage : PupuStyle.card, in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(selected ? PupuStyle.green : PupuStyle.muted.opacity(0.14), lineWidth: selected ? 1.8 : 0.7))
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 12, weight: .semibold))
                        .symbolRenderingMode(.palette).foregroundStyle(PupuStyle.onGreen, PupuStyle.green)
                        .padding(5).accessibilityHidden(true)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 13))
    }
}

private struct EffortIllustration: View {
    let level: Int
    var body: some View {
        Canvas { context, size in
            context.scaleBy(x: size.width / 34, y: size.height / 25)
            var arrows = Path()
            for index in 0..<level {
                let x = 17.0 + (Double(index) - Double(level - 1) / 2) * 10
                arrows.move(to: CGPoint(x: x, y: 3))
                arrows.addLine(to: CGPoint(x: x, y: 17))
                arrows.move(to: CGPoint(x: x - 3, y: 14))
                arrows.addLine(to: CGPoint(x: x, y: 17))
                arrows.addLine(to: CGPoint(x: x + 3, y: 14))
            }
            arrows.move(to: CGPoint(x: 6, y: 22))
            arrows.addQuadCurve(to: CGPoint(x: 28, y: 22), control: CGPoint(x: 17, y: 25))
            context.stroke(arrows, with: .color(PupuStyle.green), style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
        }
    }
}

private struct AmountIllustration: View {
    let level: Int
    var body: some View {
        Capsule().fill(StoolIllustration.fill)
            .overlay(Capsule().strokeBorder(StoolIllustration.outline, lineWidth: 1.2))
            .frame(width: CGFloat(9 + level * 7), height: CGFloat(5 + level * 4))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct StoolColorOption: Identifiable {
    let id: String
    let name: String
    let swatch: Color
    static let all: [StoolColorOption] = [
        .init(id: "brown", name: "棕色", swatch: Color(red: 0.50, green: 0.33, blue: 0.22)),
        .init(id: "light-brown", name: "浅棕", swatch: Color(red: 0.72, green: 0.56, blue: 0.39)),
        .init(id: "yellow", name: "黄色", swatch: Color(red: 0.82, green: 0.70, blue: 0.31)),
        .init(id: "green", name: "绿色", swatch: Color(red: 0.45, green: 0.51, blue: 0.29)),
        .init(id: "black", name: "黑色", swatch: Color(red: 0.20, green: 0.20, blue: 0.19)),
        .init(id: "red", name: "红色", swatch: Color(red: 0.71, green: 0.35, blue: 0.32)),
        .init(id: "gray-white", name: "灰白", swatch: Color(red: 0.87, green: 0.86, blue: 0.82))
    ]
}

struct FlowChoices: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let options: [String]
    let isSelected: (String) -> Bool
    let action: (String) -> Void
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 8), count: typeSize.isAccessibilitySize ? 2 : 3), spacing: 8) {
            ForEach(options, id: \.self) { option in
                Button { action(option) } label: {
                    Text(option).font(.subheadline).frame(maxWidth: .infinity, minHeight: 44).padding(.horizontal, 5)
                        .background(isSelected(option) ? PupuStyle.sage : PupuStyle.paper, in: Capsule())
                        .overlay(Capsule().strokeBorder(isSelected(option) ? PupuStyle.green : .clear, lineWidth: 1.5))
                }.buttonStyle(.plain).accessibilityAddTraits(isSelected(option) ? .isSelected : [])
            }
        }
    }
}
