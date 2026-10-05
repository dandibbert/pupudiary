import SwiftUI

struct RecordEditorView: View {
    @Environment(RecordStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private let isNew: Bool
    @State private var draft: PoopRecord
    @State private var confirmDelete = false
    @State private var showGuide = false

    init(record: PoopRecord?, defaultDate: Date? = nil) {
        isNew = record == nil
        var r = record ?? PoopRecord(bristol: SharedSettings.quickDefaultType)
        if record == nil, let defaultDate, !Calendar.current.isDateInToday(defaultDate) {
            // 在日历里给过去某天补记录：默认放在那天中午
            r.timestamp = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: defaultDate) ?? defaultDate
        }
        _draft = State(initialValue: r)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    timeCard
                    typeCard
                    feelCard
                    colorCard
                    symptomCard
                    noteCard
                    if !isNew {
                        Button(role: .destructive) {
                            confirmDelete = true
                        } label: {
                            Label("删除这条记录", systemImage: "trash")
                                .font(.cute(15, .bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .tint(Theme.warning)
                    }
                }
                .padding(16)
                .padding(.bottom, 80)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(isNew ? "记录一次" : "编辑记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: save).fontWeight(.bold)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: save) {
                    Text(isNew ? "保存记录" : "保存修改")
                        .font(.cute(18, .heavy))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Theme.primary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(PressableStyle())
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .background(Theme.background.opacity(0.95).ignoresSafeArea())
            }
            .confirmationDialog("确定删除这条记录吗？", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("删除", role: .destructive) {
                    store.delete(draft)
                    dismiss()
                }
            }
            .sheet(isPresented: $showGuide) {
                BristolGuideView()
            }
        }
    }

    private func save() {
        draft.isQuick = false
        draft.note = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
        store.save(draft)
        Haptics.success()
        dismiss()
    }

    // MARK: 时间

    private var timeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "什么时候", symbol: "clock.fill")
            DatePicker("时间", selection: $draft.timestamp, in: ...Date().addingTimeInterval(60))
                .labelsHidden()
                .datePickerStyle(.compact)
                .tint(Theme.primary)
            if isNew {
                HStack(spacing: 8) {
                    ForEach([0, 15, 30, 60], id: \.self) { mins in
                        Button {
                            draft.timestamp = Date().addingTimeInterval(TimeInterval(-mins * 60))
                            Haptics.tap()
                        } label: {
                            Text(mins == 0 ? "刚刚" : "\(mins) 分钟前")
                                .font(.cute(13, .bold))
                                .foregroundStyle(Theme.ink)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Theme.cardAlt, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    // MARK: 形状

    private var typeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionTitle(title: "看起来像哪一种？", symbol: "circle.hexagongrid.fill")
                Button {
                    showGuide = true
                } label: {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 18))
                        .foregroundStyle(Theme.subtle)
                }
                .accessibilityLabel("分型说明")
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(BristolType.allCases) { t in
                    let selected = draft.bristol == t
                    Button {
                        withAnimation(.spring(response: 0.3)) { draft.bristol = t }
                        Haptics.tap()
                    } label: {
                        VStack(spacing: 4) {
                            BristolIcon(type: t)
                                .frame(width: 44, height: 44)
                            Text(t.nickname)
                                .font(.cute(12, .bold))
                                .foregroundStyle(Theme.ink)
                            Text("\(t.rawValue) 型")
                                .font(.cute(10, .medium))
                                .foregroundStyle(Theme.subtle)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(selected ? t.status.softColor : Theme.cardAlt.opacity(0.5),
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(selected ? t.status.color : .clear, lineWidth: 2.5)
                        )
                        .scaleEffect(selected ? 1.04 : 1)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(t.label) \(t.nickname)，\(t.status.title)")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            HStack(alignment: .top, spacing: 8) {
                StatusChip(status: draft.bristol.status)
                VStack(alignment: .leading, spacing: 2) {
                    Text(draft.bristol.hint)
                        .font(.cute(13, .semibold))
                        .foregroundStyle(Theme.ink)
                    Text(draft.bristol.status.advice)
                        .font(.cute(12, .medium))
                        .foregroundStyle(Theme.subtle)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(draft.bristol.status.softColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .cardStyle()
    }

    // MARK: 感受

    private var feelCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(title: "感觉怎么样", symbol: "heart.fill")
            labeled("排出") {
                PillPicker(items: Ease.allCases, selection: $draft.ease) { "\($0.emoji) \($0.title)" }
            }
            labeled("分量") {
                PillPicker(items: Amount.allCases, selection: $draft.amount) { $0.title }
            }
            labeled("用时") {
                HStack {
                    Text(draft.durationMinutes == 0 ? "未记录" : "\(draft.durationMinutes) 分钟")
                        .font(.cute(15, .bold))
                        .foregroundStyle(draft.durationMinutes == 0 ? Theme.subtle : Theme.ink)
                        .monospacedDigit()
                    Spacer()
                    Stepper("", value: $draft.durationMinutes, in: 0...120)
                        .labelsHidden()
                }
            }
        }
        .cardStyle()
    }

    private func labeled<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.cute(13, .medium)).foregroundStyle(Theme.subtle)
            content()
        }
    }

    // MARK: 颜色

    private var colorCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "颜色", symbol: "paintpalette.fill", trailing: "可选")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 10) {
                swatchButton(nil)
                ForEach(StoolColor.allCases) { swatchButton($0) }
            }
            if let c = draft.color, c.needsAttention {
                Label("这个颜色需要留意，如果不是食物或药物引起，并且持续出现，建议咨询医生。", systemImage: "info.circle.fill")
                    .font(.cute(12, .medium))
                    .foregroundStyle(Theme.warning)
            }
        }
        .cardStyle()
    }

    private func swatchButton(_ c: StoolColor?) -> some View {
        let selected = draft.color == c
        return Button {
            draft.color = c
            Haptics.tap()
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    if let c {
                        Circle().fill(c.swatch)
                    } else {
                        Circle().strokeBorder(Theme.subtle.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                        Image(systemName: "minus").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.subtle)
                    }
                    if selected {
                        Circle().strokeBorder(Theme.primary, lineWidth: 3).padding(-4)
                    }
                }
                .frame(width: 28, height: 28)
                Text(c?.title ?? "不记录")
                    .font(.cute(11, .medium))
                    .foregroundStyle(selected ? Theme.ink : Theme.subtle)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    // MARK: 不适

    private var symptomCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "有没有不舒服", symbol: "bandage.fill", trailing: "可多选")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(Symptom.allCases) { s in
                    let on = draft.symptoms.contains(s)
                    Button {
                        if on { draft.symptoms.removeAll { $0 == s } } else { draft.symptoms.append(s) }
                        Haptics.tap()
                    } label: {
                        Text(s.title)
                            .font(.cute(13, .bold))
                            .foregroundStyle(on ? .white : Theme.ink)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(on ? (s.needsAttention ? Theme.warning : Theme.primary) : Theme.cardAlt,
                                        in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
        .cardStyle()
    }

    // MARK: 备注

    private var noteCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "备注", symbol: "note.text", trailing: "可选")
            TextField("比如：昨晚吃了火锅 🌶️", text: $draft.note, axis: .vertical)
                .font(.cute(15, .medium))
                .lineLimit(2...5)
                .padding(12)
                .background(Theme.cardAlt.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .cardStyle()
    }
}

/// 胶囊单选
struct PillPicker<Item: Identifiable & Hashable>: View {
    let items: [Item]
    @Binding var selection: Item
    let title: (Item) -> String

    var body: some View {
        HStack(spacing: 6) {
            ForEach(items) { item in
                let on = item == selection
                Button {
                    withAnimation(.spring(response: 0.25)) { selection = item }
                    Haptics.tap()
                } label: {
                    Text(title(item))
                        .font(.cute(14, .bold))
                        .foregroundStyle(on ? .white : Theme.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(on ? Theme.primary : Theme.cardAlt, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}
