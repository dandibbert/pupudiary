import SwiftUI

// MARK: - 表情

struct SmileArc: Shape {
    /// true 时为向下的嘴角（担心）
    var frown = false
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let y0 = frown ? rect.maxY : rect.minY
        let y1 = frown ? rect.minY - rect.height * 0.6 : rect.maxY + rect.height * 0.6
        p.move(to: CGPoint(x: rect.minX, y: y0))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: y0), control: CGPoint(x: rect.midX, y: y1))
        return p
    }
}

/// 可爱的小脸：眼睛 + 腮红 + 嘴巴，宽度为 w
struct CuteFace: View {
    var mood: Mascot.Mood = .happy
    var width: CGFloat
    var ink: Color = Color(hex: 0x4A3A35)

    var body: some View {
        let eye = width * 0.14
        let gap = width * 0.27
        let line = max(1, width * 0.06)
        ZStack {
            // 眼睛
            Group {
                switch mood {
                case .sleepy:
                    SmileArc(frown: true)
                        .stroke(ink, style: StrokeStyle(lineWidth: line, lineCap: .round))
                        .frame(width: eye * 1.3, height: eye * 0.4)
                        .offset(x: -gap)
                    SmileArc(frown: true)
                        .stroke(ink, style: StrokeStyle(lineWidth: line, lineCap: .round))
                        .frame(width: eye * 1.3, height: eye * 0.4)
                        .offset(x: gap)
                case .excited:
                    SmileArc(frown: true)
                        .stroke(ink, style: StrokeStyle(lineWidth: line, lineCap: .round))
                        .frame(width: eye * 1.2, height: eye * 0.6)
                        .offset(x: -gap, y: -eye * 0.2)
                    SmileArc(frown: true)
                        .stroke(ink, style: StrokeStyle(lineWidth: line, lineCap: .round))
                        .frame(width: eye * 1.2, height: eye * 0.6)
                        .offset(x: gap, y: -eye * 0.2)
                default:
                    Circle().fill(ink).frame(width: eye, height: eye).offset(x: -gap)
                    Circle().fill(ink).frame(width: eye, height: eye).offset(x: gap)
                    Circle().fill(.white).frame(width: eye * 0.38, height: eye * 0.38)
                        .offset(x: -gap + eye * 0.18, y: -eye * 0.18)
                    Circle().fill(.white).frame(width: eye * 0.38, height: eye * 0.38)
                        .offset(x: gap + eye * 0.18, y: -eye * 0.18)
                }
            }
            // 腮红
            Ellipse().fill(Theme.blush.opacity(0.75))
                .frame(width: eye * 1.5, height: eye * 0.9)
                .offset(x: -gap - eye * 0.9, y: eye * 1.1)
            Ellipse().fill(Theme.blush.opacity(0.75))
                .frame(width: eye * 1.5, height: eye * 0.9)
                .offset(x: gap + eye * 0.9, y: eye * 1.1)
            // 嘴巴
            switch mood {
            case .worried:
                SmileArc(frown: true)
                    .stroke(ink, style: StrokeStyle(lineWidth: line, lineCap: .round))
                    .frame(width: eye * 1.4, height: eye * 0.45)
                    .offset(y: eye * 1.3)
            case .calm, .sleepy:
                Capsule().fill(ink)
                    .frame(width: eye * 1.0, height: line)
                    .offset(y: eye * 1.1)
            case .happy, .excited:
                SmileArc()
                    .stroke(ink, style: StrokeStyle(lineWidth: line, lineCap: .round))
                    .frame(width: eye * 1.6, height: eye * 0.5)
                    .offset(y: eye * 0.8)
            }
        }
        .frame(width: width, height: width * 0.6)
    }
}

// MARK: - 吉祥物「噗噗」：圆滚滚的小豆子，头顶一棵小嫩芽

struct Mascot: View {
    enum Mood { case happy, calm, worried, sleepy, excited }
    var mood: Mood = .happy

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            ZStack {
                // 嫩芽
                Capsule().fill(Theme.leaf)
                    .frame(width: s * 0.04, height: s * 0.14)
                    .offset(y: -s * 0.36)
                Ellipse().fill(Theme.leaf)
                    .frame(width: s * 0.2, height: s * 0.1)
                    .rotationEffect(.degrees(-25))
                    .offset(x: -s * 0.09, y: -s * 0.44)
                Ellipse().fill(Theme.leaf.opacity(0.85))
                    .frame(width: s * 0.16, height: s * 0.085)
                    .rotationEffect(.degrees(25))
                    .offset(x: s * 0.08, y: -s * 0.42)
                // 身体
                Ellipse()
                    .fill(LinearGradient(colors: [Theme.mascotBody, Theme.mascotShade],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: s * 0.92, height: s * 0.74)
                    .offset(y: s * 0.1)
                // 高光
                Ellipse().fill(.white.opacity(0.5))
                    .frame(width: s * 0.2, height: s * 0.1)
                    .rotationEffect(.degrees(-25))
                    .offset(x: -s * 0.24, y: -s * 0.08)
                CuteFace(mood: mood, width: s * 0.5)
                    .offset(y: s * 0.12)
                // 小脚
                Capsule().fill(Theme.mascotShade)
                    .frame(width: s * 0.16, height: s * 0.08)
                    .offset(x: -s * 0.18, y: s * 0.46)
                Capsule().fill(Theme.mascotShade)
                    .frame(width: s * 0.16, height: s * 0.08)
                    .offset(x: s * 0.18, y: s * 0.46)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

// MARK: - 布里斯托七型的 Q 版图标（抽象几何 + 小脸，不写实）

struct DropShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addCurve(to: CGPoint(x: rect.maxX, y: rect.minY + h * 0.66),
                   control1: CGPoint(x: rect.midX + w * 0.12, y: rect.minY + h * 0.2),
                   control2: CGPoint(x: rect.maxX, y: rect.minY + h * 0.38))
        p.addArc(center: CGPoint(x: rect.midX, y: rect.minY + h * 0.66),
                 radius: w / 2, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
        p.addCurve(to: CGPoint(x: rect.midX, y: rect.minY),
                   control1: CGPoint(x: rect.minX, y: rect.minY + h * 0.38),
                   control2: CGPoint(x: rect.midX - w * 0.12, y: rect.minY + h * 0.2))
        p.closeSubpath()
        return p
    }
}

struct BristolIcon: View {
    let type: BristolType
    /// 是否画小脸（很小的尺寸可以关掉）
    var showFace = true

    private var mood: Mascot.Mood {
        switch type.status {
        case .dry, .loose: return .worried
        case .ideal: return .happy
        case .soft: return .calm
        }
    }

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            let u = s / 100
            let base = type.status.color
            let fill = LinearGradient(colors: [base.opacity(0.75), base], startPoint: .top, endPoint: .bottom)
            ZStack {
                shapes(u: u, fill: fill)
                if showFace {
                    CuteFace(mood: mood, width: faceWidth * u)
                        .offset(x: faceCenter.x * u - 50 * u, y: faceCenter.y * u - 50 * u)
                }
            }
            .frame(width: s, height: s)
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private var faceCenter: CGPoint {
        switch type {
        case .t1: return CGPoint(x: 56, y: 42)
        case .t2: return CGPoint(x: 49, y: 52)
        case .t3, .t4: return CGPoint(x: 50, y: 52)
        case .t5: return CGPoint(x: 50, y: 47)
        case .t6: return CGPoint(x: 50, y: 56)
        case .t7: return CGPoint(x: 50, y: 64)
        }
    }

    private var faceWidth: CGFloat {
        switch type {
        case .t1: return 22
        case .t5: return 22
        default: return 30
        }
    }

    @ViewBuilder
    private func shapes(u: CGFloat, fill: LinearGradient) -> some View {
        switch type {
        case .t1:
            blob(Circle(), fill, x: 26, y: 66, w: 26, h: 26, u: u)
            blob(Circle(), fill, x: 56, y: 42, w: 36, h: 36, u: u)
            blob(Circle(), fill, x: 76, y: 72, w: 22, h: 22, u: u)
        case .t2:
            blob(Circle(), fill, x: 20, y: 54, w: 28, h: 28, u: u)
            blob(Circle(), fill, x: 37, y: 48, w: 32, h: 32, u: u)
            blob(Circle(), fill, x: 59, y: 53, w: 34, h: 34, u: u)
            blob(Circle(), fill, x: 80, y: 49, w: 28, h: 28, u: u)
        case .t3:
            blob(Capsule(), fill, x: 50, y: 52, w: 84, h: 38, u: u)
            ForEach([26.0, 50.0, 74.0], id: \.self) { x in
                Capsule().fill(.white.opacity(0.75))
                    .frame(width: 2.5 * u, height: 9 * u)
                    .rotationEffect(.degrees(x == 50 ? 0 : (x < 50 ? -15 : 15)))
                    .offset(x: (x - 50) * u, y: (36 - 50) * u)
            }
        case .t4:
            blob(Capsule(), fill, x: 50, y: 52, w: 86, h: 38, u: u)
            Image(systemName: "sparkle")
                .font(.system(size: 16 * u, weight: .bold))
                .foregroundStyle(Color(hex: 0xFFD54F))
                .offset(x: 36 * u, y: -24 * u)
        case .t5:
            blob(Ellipse(), fill, x: 22, y: 60, w: 32, h: 28, u: u)
            blob(Ellipse(), fill, x: 50, y: 47, w: 36, h: 32, u: u)
            blob(Ellipse(), fill, x: 78, y: 61, w: 30, h: 26, u: u)
        case .t6:
            blob(Circle(), fill, x: 30, y: 58, w: 38, h: 38, u: u)
            blob(Circle(), fill, x: 52, y: 44, w: 44, h: 44, u: u)
            blob(Circle(), fill, x: 72, y: 58, w: 36, h: 36, u: u)
            blob(Ellipse(), fill, x: 50, y: 66, w: 66, h: 26, u: u)
        case .t7:
            DropShape().fill(fill)
                .frame(width: 52 * u, height: 70 * u)
                .offset(x: 0, y: (52 - 50) * u)
            DropShape().fill(fill).opacity(0.7)
                .frame(width: 14 * u, height: 19 * u)
                .offset(x: 34 * u, y: -22 * u)
            DropShape().fill(fill).opacity(0.6)
                .frame(width: 10 * u, height: 14 * u)
                .offset(x: -34 * u, y: -10 * u)
        }
    }

    private func blob<S: Shape>(_ shape: S, _ fill: LinearGradient,
                                x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, u: CGFloat) -> some View {
        shape.fill(fill)
            .frame(width: w * u, height: h * u)
            .offset(x: (x - 50) * u, y: (y - 50) * u)
    }
}

/// 状态小圆点
struct StatusDot: View {
    let status: GutStatus
    var size: CGFloat = 10
    var body: some View {
        Circle().fill(status.color).frame(width: size, height: size)
    }
}

/// 状态胶囊标签
struct StatusChip: View {
    let status: GutStatus
    var body: some View {
        Text(status.title)
            .font(.cute(12, .bold))
            .foregroundStyle(status.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(status.softColor, in: Capsule())
    }
}
