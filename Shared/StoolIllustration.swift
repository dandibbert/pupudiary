import SwiftUI

/// Descriptive labels only: these categories are not a diagnosis or a score.
enum BristolMetadata {
    static func label(for type: Int?) -> String {
        switch type {
        case 1: return "硬颗粒"
        case 2: return "结块条状"
        case 3: return "表面裂纹"
        case 4: return "光滑柔软"
        case 5: return "柔软小块"
        case 6: return "糊状"
        case 7: return "水样"
        default: return "未选择"
        }
    }

    static func accessibilityLabel(for type: Int?) -> String {
        guard let type, (1...7).contains(type) else { return "形态未选择" }
        return "类型 \(type)，\(label(for: type))"
    }
}

/// Original flat vector drawings shared by the entry form, history, and home.
/// The caller supplies the text alternative so a row is announced just once.
struct StoolIllustration: View {
    let type: Int?

    static let fill = Color(red: 181.0 / 255, green: 141.0 / 255, blue: 114.0 / 255)
    static let outline = Color(red: 118.0 / 255, green: 91.0 / 255, blue: 73.0 / 255)

    var body: some View {
        Canvas { context, size in
            context.scaleBy(x: size.width / 54, y: size.height / 38)
            let stroke = StrokeStyle(lineWidth: 1.35, lineCap: .round, lineJoin: .round)
            guard let type, (1...7).contains(type) else {
                let empty = Path(roundedRect: CGRect(x: 13, y: 8, width: 28, height: 22), cornerSize: CGSize(width: 8, height: 8))
                context.stroke(empty, with: .color(PupuStyle.muted.opacity(0.55)), style: StrokeStyle(lineWidth: 1.2, dash: [2.5, 3]))
                var line = Path()
                line.move(to: CGPoint(x: 23, y: 19))
                line.addLine(to: CGPoint(x: 31, y: 19))
                context.stroke(line, with: .color(PupuStyle.muted), style: stroke)
                return
            }
            for path in StoolArtwork.silhouettes(for: type) {
                context.fill(path, with: .color(Self.fill))
                context.stroke(path, with: .color(Self.outline), style: stroke)
            }
            context.stroke(StoolArtwork.details(for: type), with: .color(Self.outline), style: stroke)
        }
        .aspectRatio(54.0 / 38, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

private enum StoolArtwork {
    static func silhouettes(for type: Int) -> [Path] {
        switch type {
        case 1:
            // Five separate small hard pellets.
            return [
                Path(ellipseIn: CGRect(x: 7, y: 8, width: 10, height: 10)),
                Path(ellipseIn: CGRect(x: 25, y: 5, width: 10, height: 10)),
                Path(ellipseIn: CGRect(x: 39, y: 13, width: 8, height: 8)),
                Path(ellipseIn: CGRect(x: 16, y: 23, width: 9, height: 9)),
                Path(ellipseIn: CGRect(x: 34, y: 26, width: 8, height: 8))
            ]
        case 2:
            // A single connected log with visibly lumpy edges.
            return [Path { p in
                p.move(to: CGPoint(x: 6, y: 21))
                p.addCurve(to: CGPoint(x: 12, y: 14), control1: CGPoint(x: 3, y: 17), control2: CGPoint(x: 7, y: 12))
                p.addCurve(to: CGPoint(x: 24, y: 11), control1: CGPoint(x: 13, y: 6), control2: CGPoint(x: 21, y: 6))
                p.addCurve(to: CGPoint(x: 36, y: 11), control1: CGPoint(x: 29, y: 4), control2: CGPoint(x: 36, y: 5))
                p.addCurve(to: CGPoint(x: 47, y: 17), control1: CGPoint(x: 44, y: 6), control2: CGPoint(x: 51, y: 12))
                p.addCurve(to: CGPoint(x: 41, y: 26), control1: CGPoint(x: 53, y: 22), control2: CGPoint(x: 48, y: 28))
                p.addCurve(to: CGPoint(x: 28, y: 28), control1: CGPoint(x: 37, y: 33), control2: CGPoint(x: 30, y: 33))
                p.addCurve(to: CGPoint(x: 15, y: 27), control1: CGPoint(x: 22, y: 34), control2: CGPoint(x: 14, y: 33))
                p.addCurve(to: CGPoint(x: 6, y: 21), control1: CGPoint(x: 7, y: 31), control2: CGPoint(x: 2, y: 26))
                p.closeSubpath()
            }]
        case 3:
            return [Path { p in
                p.move(to: CGPoint(x: 6, y: 23))
                p.addCurve(to: CGPoint(x: 14, y: 11), control1: CGPoint(x: 3, y: 17), control2: CGPoint(x: 8, y: 12))
                p.addCurve(to: CGPoint(x: 44, y: 12), control1: CGPoint(x: 25, y: 8), control2: CGPoint(x: 36, y: 10))
                p.addCurve(to: CGPoint(x: 45, y: 27), control1: CGPoint(x: 52, y: 14), control2: CGPoint(x: 52, y: 25))
                p.addCurve(to: CGPoint(x: 15, y: 29), control1: CGPoint(x: 34, y: 28), control2: CGPoint(x: 26, y: 27))
                p.addCurve(to: CGPoint(x: 6, y: 23), control1: CGPoint(x: 10, y: 30), control2: CGPoint(x: 7, y: 27))
                p.closeSubpath()
            }]
        case 4:
            // A smooth, gently curved log, without cracks or lumps.
            return [Path { p in
                p.move(to: CGPoint(x: 7, y: 12))
                p.addCurve(to: CGPoint(x: 28, y: 13), control1: CGPoint(x: 12, y: 5), control2: CGPoint(x: 23, y: 6))
                p.addCurve(to: CGPoint(x: 43, y: 19), control1: CGPoint(x: 34, y: 21), control2: CGPoint(x: 37, y: 22))
                p.addCurve(to: CGPoint(x: 49, y: 27), control1: CGPoint(x: 49, y: 14), control2: CGPoint(x: 54, y: 22))
                p.addCurve(to: CGPoint(x: 24, y: 26), control1: CGPoint(x: 42, y: 35), control2: CGPoint(x: 31, y: 34))
                p.addCurve(to: CGPoint(x: 13, y: 22), control1: CGPoint(x: 19, y: 19), control2: CGPoint(x: 17, y: 18))
                p.addCurve(to: CGPoint(x: 7, y: 12), control1: CGPoint(x: 6, y: 27), control2: CGPoint(x: 1, y: 19))
                p.closeSubpath()
            }]
        case 5:
            // Three larger soft pieces with clean, separate boundaries.
            return [
                Path(roundedRect: CGRect(x: 5, y: 8, width: 16, height: 12), cornerSize: CGSize(width: 5, height: 5)),
                Path(roundedRect: CGRect(x: 30, y: 7, width: 17, height: 13), cornerSize: CGSize(width: 5.5, height: 5.5)),
                Path(roundedRect: CGRect(x: 18, y: 24, width: 18, height: 11), cornerSize: CGSize(width: 5, height: 5))
            ]
        case 6:
            // Loose, fluffy fragments with irregular feathered edges.
            return [Path { p in
                p.move(to: CGPoint(x: 7, y: 10))
                p.addQuadCurve(to: CGPoint(x: 12, y: 8), control: CGPoint(x: 6, y: 4))
                p.addQuadCurve(to: CGPoint(x: 20, y: 8), control: CGPoint(x: 20, y: 2))
                p.addQuadCurve(to: CGPoint(x: 24, y: 15), control: CGPoint(x: 30, y: 9))
                p.addQuadCurve(to: CGPoint(x: 21, y: 21), control: CGPoint(x: 27, y: 24))
                p.addQuadCurve(to: CGPoint(x: 13, y: 21), control: CGPoint(x: 14, y: 26))
                p.addQuadCurve(to: CGPoint(x: 6, y: 17), control: CGPoint(x: 4, y: 25))
                p.addQuadCurve(to: CGPoint(x: 7, y: 10), control: CGPoint(x: 0, y: 11))
                p.closeSubpath()
            }, Path { p in
                p.move(to: CGPoint(x: 34, y: 10))
                p.addQuadCurve(to: CGPoint(x: 41, y: 8), control: CGPoint(x: 35, y: 3))
                p.addQuadCurve(to: CGPoint(x: 48, y: 13), control: CGPoint(x: 49, y: 4))
                p.addQuadCurve(to: CGPoint(x: 46, y: 21), control: CGPoint(x: 55, y: 21))
                p.addQuadCurve(to: CGPoint(x: 37, y: 23), control: CGPoint(x: 43, y: 30))
                p.addQuadCurve(to: CGPoint(x: 32, y: 18), control: CGPoint(x: 28, y: 26))
                p.addQuadCurve(to: CGPoint(x: 34, y: 10), control: CGPoint(x: 28, y: 10))
                p.closeSubpath()
            }, Path { p in
                p.move(to: CGPoint(x: 23, y: 28))
                p.addQuadCurve(to: CGPoint(x: 30, y: 27), control: CGPoint(x: 24, y: 23))
                p.addQuadCurve(to: CGPoint(x: 34, y: 32), control: CGPoint(x: 37, y: 28))
                p.addQuadCurve(to: CGPoint(x: 28, y: 35), control: CGPoint(x: 33, y: 38))
                p.addQuadCurve(to: CGPoint(x: 22, y: 33), control: CGPoint(x: 20, y: 37))
                p.addQuadCurve(to: CGPoint(x: 23, y: 28), control: CGPoint(x: 18, y: 28))
                p.closeSubpath()
            }]
        case 7:
            // A flat fluid puddle. No pellets or solid fragments.
            return [Path { p in
                p.move(to: CGPoint(x: 5, y: 24))
                p.addCurve(to: CGPoint(x: 15, y: 18), control1: CGPoint(x: 2, y: 20), control2: CGPoint(x: 9, y: 17))
                p.addCurve(to: CGPoint(x: 33, y: 16), control1: CGPoint(x: 23, y: 20), control2: CGPoint(x: 25, y: 13))
                p.addCurve(to: CGPoint(x: 44, y: 20), control1: CGPoint(x: 38, y: 18), control2: CGPoint(x: 38, y: 20))
                p.addCurve(to: CGPoint(x: 46, y: 28), control1: CGPoint(x: 54, y: 20), control2: CGPoint(x: 53, y: 26))
                p.addCurve(to: CGPoint(x: 14, y: 30), control1: CGPoint(x: 39, y: 33), control2: CGPoint(x: 25, y: 29))
                p.addCurve(to: CGPoint(x: 5, y: 24), control1: CGPoint(x: 7, y: 31), control2: CGPoint(x: 1, y: 28))
                p.closeSubpath()
            }]
        default: return []
        }
    }

    static func details(for type: Int) -> Path {
        Path { p in
            if type == 3 {
                p.move(to: CGPoint(x: 17, y: 12))
                p.addLine(to: CGPoint(x: 16, y: 17))
                p.addLine(to: CGPoint(x: 20, y: 20))
                p.addLine(to: CGPoint(x: 18, y: 25))
                p.move(to: CGPoint(x: 28, y: 11))
                p.addLine(to: CGPoint(x: 26, y: 16))
                p.addLine(to: CGPoint(x: 30, y: 19))
                p.addLine(to: CGPoint(x: 29, y: 23))
                p.move(to: CGPoint(x: 40, y: 13))
                p.addLine(to: CGPoint(x: 37, y: 18))
                p.addLine(to: CGPoint(x: 40, y: 22))
                p.addLine(to: CGPoint(x: 38, y: 26))
            } else if type == 7 {
                p.move(to: CGPoint(x: 13, y: 23))
                p.addQuadCurve(to: CGPoint(x: 25, y: 23), control: CGPoint(x: 18, y: 20))
                p.move(to: CGPoint(x: 30, y: 26))
                p.addQuadCurve(to: CGPoint(x: 42, y: 25), control: CGPoint(x: 36, y: 28))
            }
        }
    }
}

#Preview("Bristol illustrations") {
    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 16) {
        ForEach(1...7, id: \.self) { type in
            VStack(spacing: 4) {
                StoolIllustration(type: type).frame(width: 54, height: 38)
                Text("\(type)").font(.system(size: 12))
                Text(BristolMetadata.label(for: type)).font(.system(size: 14))
            }
        }
    }
    .padding(16)
    .background(PupuStyle.paper)
}
