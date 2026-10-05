import SwiftUI

/// 卡片标题
struct SectionTitle: View {
    let title: String
    var symbol: String? = nil
    var trailing: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            if let symbol {
                Image(systemName: symbol).foregroundStyle(Theme.primary)
            }
            Text(title).font(.cute(17, .bold)).foregroundStyle(Theme.ink)
            Spacer()
            if let trailing {
                Text(trailing).font(.cute(13, .medium)).foregroundStyle(Theme.subtle)
            }
        }
    }
}

/// 一条记录
struct RecordRow: View {
    let record: PoopRecord
    var showDate = false

    var body: some View {
        HStack(spacing: 12) {
            BristolIcon(type: record.bristol)
                .frame(width: 44, height: 44)
                .padding(4)
                .background(record.status.softColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(record.bristol.nickname)
                        .font(.cute(16, .bold))
                        .foregroundStyle(Theme.ink)
                    StatusChip(status: record.status)
                    if record.needsAttention {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(Theme.warning)
                            .font(.system(size: 14))
                    }
                }
                Text(detailLine)
                    .font(.cute(12, .medium))
                    .foregroundStyle(Theme.subtle)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 4) {
                Text(record.timestamp, format: .dateTime.hour().minute())
                    .font(.cute(15, .bold))
                    .foregroundStyle(Theme.ink)
                    .monospacedDigit()
                if showDate {
                    Text(record.timestamp, format: .dateTime.month().day())
                        .font(.cute(11, .medium))
                        .foregroundStyle(Theme.subtle)
                } else if record.isQuick {
                    Text("待补充")
                        .font(.cute(11, .bold))
                        .foregroundStyle(Theme.primary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.primarySoft, in: Capsule())
                }
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var detailLine: String {
        var parts = [record.bristol.label, record.amount.title, record.ease.title]
        if record.durationMinutes > 0 { parts.append("\(record.durationMinutes) 分钟") }
        if let c = record.color { parts.append(c.title) }
        if !record.symptoms.isEmpty { parts.append(record.symptoms.map(\.title).joined(separator: "、")) }
        if !record.note.isEmpty { parts.append(record.note) }
        return parts.joined(separator: " · ")
    }
}

/// 最近 7 天的小格子
struct WeekStrip: View {
    let days: [DaySummary]
    var onSelect: ((Date) -> Void)? = nil

    var body: some View {
        HStack(spacing: 0) {
            ForEach(days) { d in
                let isToday = Calendar.current.isDateInToday(d.day)
                VStack(spacing: 6) {
                    Text(isToday ? "今" : weekday(d.day))
                        .font(.cute(12, isToday ? .heavy : .medium))
                        .foregroundStyle(isToday ? Theme.primary : Theme.subtle)
                    ZStack {
                        if let s = d.dominantStatus {
                            Circle().fill(s.color)
                            Text("\(d.count)")
                                .font(.cute(15, .heavy))
                                .foregroundStyle(.white)
                        } else {
                            Circle().strokeBorder(Theme.subtle.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                        }
                    }
                    .frame(width: 34, height: 34)
                    Text(d.day, format: .dateTime.day())
                        .font(.cute(11, .medium))
                        .foregroundStyle(Theme.subtle)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { onSelect?(d.day) }
                .accessibilityLabel("\(d.day.formatted(.dateTime.month().day()))，\(d.count) 次\(d.dominantStatus.map { "，\($0.title)" } ?? "")")
            }
        }
    }

    private func weekday(_ d: Date) -> String {
        let i = Calendar.current.component(.weekday, from: d)
        return ["日", "一", "二", "三", "四", "五", "六"][i - 1]
    }
}

/// 四种状态的图例
struct StatusLegend: View {
    var body: some View {
        HStack(spacing: 14) {
            ForEach(GutStatus.allCases) { s in
                HStack(spacing: 4) {
                    StatusDot(status: s, size: 8)
                    Text(s.title).font(.cute(11, .medium)).foregroundStyle(Theme.subtle)
                }
            }
        }
    }
}

/// 健康提示卡片
struct InsightCard: View {
    let insight: Insight

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: insight.level.symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(insight.level.color)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(insight.title).font(.cute(15, .bold)).foregroundStyle(Theme.ink)
                Text(insight.message).font(.cute(13, .medium)).foregroundStyle(Theme.subtle)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(insight.level.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// 底部的小提示条
struct Toast: Equatable {
    var message: String
    var recordID: UUID?
}

struct ToastView: View {
    let toast: Toast
    var action: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(GutStatus.ideal.color)
            Text(toast.message).font(.cute(15, .bold)).foregroundStyle(.white)
            Spacer(minLength: 0)
            if let action {
                Button("补充细节", action: action)
                    .font(.cute(14, .bold))
                    .foregroundStyle(Theme.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.white, in: Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(hex: 0x3D302C).opacity(0.94), in: Capsule())
        .padding(.horizontal, 16)
        .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
    }
}

/// 空状态
struct EmptyHint: View {
    let title: String
    var subtitle: String? = nil
    var mood: Mascot.Mood = .calm

    var body: some View {
        VStack(spacing: 8) {
            Mascot(mood: mood).frame(width: 72)
            Text(title).font(.cute(15, .bold)).foregroundStyle(Theme.ink)
            if let subtitle {
                Text(subtitle).font(.cute(13, .medium)).foregroundStyle(Theme.subtle)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
}

extension Double {
    /// 把小时数格式化成“3 小时 / 2 天”
    var friendlyDuration: String {
        if self < 1 { return "\(max(1, Int(self * 60))) 分钟" }
        if self < 48 { return "\(Int(self)) 小时" }
        return "\(Int(self / 24)) 天"
    }
}
