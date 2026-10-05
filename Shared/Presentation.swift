import SwiftUI

// Original vector artwork, intentionally abstract and unrelated to stool appearance.
enum PupuStyle {
    static let ink = Color(light: 0x273B36, dark: 0xE9F0E6)
    static let muted = Color(light: 0x617168, dark: 0xABBCAE)
    static let paper = Color(light: 0xFBF8F2, dark: 0x17241F)
    static let card = Color(light: 0xFFFFFF, dark: 0x21332B)
    static let green = Color(light: 0x276658, dark: 0x99D3AF)
    static let onGreen = Color(light: 0xFFFFFF, dark: 0x18372B)
    static let sage = Color(light: 0xDCEAD7, dark: 0x334B3A)
    static let peach = Color(light: 0xF8DDCB, dark: 0x533E35)
    static let lavender = Color(light: 0xE6E1F2, dark: 0x3D364D)
}
extension Color {
    init(light: UInt, dark: UInt) {
        self.init(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, alpha: 1)
        })
    }
}
struct Dumpling: View {
    var happy = true
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack {
                Ellipse().fill(Color.black.opacity(0.045)).frame(width: w * 0.73, height: h * 0.10).offset(y: h * 0.39)
                RoundedRectangle(cornerRadius: w * 0.35).fill(Color(red: 1, green: 0.96, blue: 0.84))
                    .frame(width: w * 0.78, height: h * 0.74).rotationEffect(.degrees(-5))
                Ellipse().fill(Color(red: 0.95, green: 0.80, blue: 0.59)).frame(width: w * 0.10, height: h * 0.04).offset(x: -w * 0.30, y: h * 0.22)
                Ellipse().fill(Color(red: 0.95, green: 0.80, blue: 0.59)).frame(width: w * 0.10, height: h * 0.04).offset(x: w * 0.30, y: h * 0.22)
                Capsule().fill(Color(red: 0.59, green: 0.78, blue: 0.65)).frame(width: w * 0.60, height: h * 0.105).rotationEffect(.degrees(-5)).offset(y: h * 0.24)
                Capsule().fill(Color(red: 0.59, green: 0.78, blue: 0.65)).frame(width: w * 0.12, height: h * 0.23).rotationEffect(.degrees(-20)).offset(x: w * 0.14, y: h * 0.30)
                HStack(spacing: w * 0.16) {
                    Capsule().frame(width: w * 0.036, height: h * 0.063)
                    Capsule().frame(width: w * 0.036, height: h * 0.063)
                }.foregroundStyle(Color(red: 0.21, green: 0.27, blue: 0.22)).offset(y: -h * 0.02)
                HStack(spacing: w * 0.31) {
                    Ellipse().frame(width: w * 0.10, height: h * 0.05)
                    Ellipse().frame(width: w * 0.10, height: h * 0.05)
                }.foregroundStyle(Color(red: 0.96, green: 0.67, blue: 0.60).opacity(0.6)).offset(y: h * 0.045)
                Text(happy ? "⌣" : "·").font(.system(size: w * 0.15, weight: .medium, design: .rounded)).foregroundStyle(Color(red: 0.21, green: 0.27, blue: 0.22)).offset(y: h * 0.062)
                Image(systemName: "leaf.fill").font(.system(size: w * 0.18)).foregroundStyle(Color(red: 0.38, green: 0.63, blue: 0.43)).rotationEffect(.degrees(-25)).offset(x: w * 0.10, y: -h * 0.34)
            }.frame(width: w, height: h)
        }.accessibilityHidden(true)
    }
}
struct PupuWidgetContent: View {
    let count: Int
    let last: Date?
    let discreet: Bool
    let sharedAvailable: Bool
    var compact = false
    var lastBristol: Int? = nil
    var lastEffort: String? = nil
    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                Text("排便记录").font(.caption.weight(.semibold)).foregroundStyle(PupuStyle.muted)
                if !sharedAvailable {
                    Text("在 App 内查看").font(.system(.headline, design: .rounded)).foregroundStyle(PupuStyle.ink)
                    Text("共享空间未启用").font(.caption2).foregroundStyle(PupuStyle.muted)
                } else if discreet {
                    Text("内容已隐藏").font(.system(.headline, design: .rounded)).foregroundStyle(PupuStyle.ink)
                } else {
                    Text("今天已记 \(count) 次").font(.system(.headline, design: .rounded, weight: .bold)).foregroundStyle(PupuStyle.ink)
                    if let last {
                        Text("上次 \(last.formatted(.relative(presentation: .numeric)))").font(.caption).foregroundStyle(PupuStyle.muted)
                    } else {
                        Text("尚无排便记录").font(.caption).foregroundStyle(PupuStyle.muted)
                    }
                }
            }
            if !compact, sharedAvailable, !discreet, last != nil {
                Spacer(minLength: 0)
                VStack(spacing: 3) {
                    StoolIllustration(type: lastBristol).frame(width: 50, height: 35)
                    Text(lastBristol == nil ? "形态未填" : BristolMetadata.label(for: lastBristol)).font(.caption2)
                    if let lastEffort { Text(lastEffort).font(.caption2).foregroundStyle(PupuStyle.muted) }
                }
            }
        }.privacySensitive(!discreet)
    }
}
