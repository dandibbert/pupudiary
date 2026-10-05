import SwiftUI
import UIKit

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }

    /// 自动适配深色模式
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { trait in
            let hex = trait.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                           green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255,
                           alpha: 1)
        })
    }
}

enum Theme {
    static let background = Color(light: 0xFFF6EC, dark: 0x1C1A1F)
    static let card = Color(light: 0xFFFFFF, dark: 0x2A2730)
    static let cardAlt = Color(light: 0xFFEFDF, dark: 0x332E36)
    static let primary = Color(light: 0xFF8C66, dark: 0xFF9B7A)
    static let primarySoft = Color(light: 0xFFE2D4, dark: 0x4A3530)
    static let ink = Color(light: 0x4A3A35, dark: 0xF4ECE6)
    static let subtle = Color(light: 0x9C8A82, dark: 0xA79C98)
    static let warning = Color(light: 0xF0625F, dark: 0xFF7B78)

    static let mascotBody = Color(hex: 0xFFC48C)
    static let mascotShade = Color(hex: 0xF5A66B)
    static let blush = Color(hex: 0xFF8FA3)
    static let leaf = Color(hex: 0x7ACB7E)

    static let corner: CGFloat = 22
}

extension GutStatus {
    var color: Color {
        switch self {
        case .dry: return Color(hex: 0xFFAA55)
        case .ideal: return Color(hex: 0x4FC487)
        case .soft: return Color(hex: 0xF2C230)
        case .loose: return Color(hex: 0x62AEF0)
        }
    }

    var softColor: Color { color.opacity(0.18) }

    var emoji: String {
        switch self {
        case .dry: return "🌵"
        case .ideal: return "🌟"
        case .soft: return "🍮"
        case .loose: return "💧"
        }
    }
}

extension InsightLevel {
    var color: Color {
        switch self {
        case .good: return GutStatus.ideal.color
        case .info: return Theme.primary
        case .attention: return GutStatus.dry.color
        case .warning: return Theme.warning
        }
    }

    var symbol: String {
        switch self {
        case .good: return "checkmark.seal.fill"
        case .info: return "sparkles"
        case .attention: return "exclamationmark.bubble.fill"
        case .warning: return "cross.case.fill"
        }
    }

    var mood: Mascot.Mood {
        switch self {
        case .good: return .happy
        case .info: return .calm
        case .attention: return .worried
        case .warning: return .worried
        }
    }
}

extension StoolColor {
    /// 柔和的小色点，不追求写实
    var swatch: Color {
        switch self {
        case .brown: return Color(hex: 0xB98260)
        case .darkBrown: return Color(hex: 0x7D5A45)
        case .yellow: return Color(hex: 0xE8C35A)
        case .green: return Color(hex: 0x8DB06A)
        case .black: return Color(hex: 0x45434A)
        case .red: return Color(hex: 0xE07068)
        case .pale: return Color(hex: 0xE2DCD0)
        }
    }
}

extension View {
    /// 统一的卡片样式
    func cardStyle(padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
            .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 4)
    }
}

extension Font {
    static func cute(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}
