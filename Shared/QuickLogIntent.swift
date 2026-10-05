import AppIntents
import Foundation

/// 在快捷指令 / 小组件里选择的状态
enum QuickStatus: String, AppEnum {
    case usual, dry, ideal, soft, loose

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "噗噗状态"

    static var caseDisplayRepresentations: [QuickStatus: DisplayRepresentation] = [
        .usual: "默认类型",
        .dry: "偏干",
        .ideal: "理想",
        .soft: "偏软",
        .loose: "偏稀",
    ]

    var bristol: BristolType {
        switch self {
        case .usual: return SharedSettings.quickDefaultType
        case .dry: return GutStatus.dry.representative
        case .ideal: return GutStatus.ideal.representative
        case .soft: return GutStatus.soft.representative
        case .loose: return GutStatus.loose.representative
        }
    }

    init(_ status: GutStatus) {
        switch status {
        case .dry: self = .dry
        case .ideal: self = .ideal
        case .soft: self = .soft
        case .loose: self = .loose
        }
    }
}

/// 一键记录：小组件按钮、控制中心、快捷指令、操作按钮都用它
struct QuickLogIntent: AppIntent {
    static var title: LocalizedStringResource = "噗！记一下"
    static var description = IntentDescription("立刻记录一次噗噗，细节可以稍后在 App 里补充。")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "状态", default: .usual)
    var status: QuickStatus

    init() {}

    init(status: QuickStatus) {
        self.status = status
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let record = PoopRecord(timestamp: Date(), bristol: status.bristol, isQuick: true)
        let all = RecordStorage.mutate { $0.append(record) }
        let today = GutStats(records: all).today.count
        let message = "已记录！今天第 \(today) 次 ✨"
        return .result(dialog: "\(message)")
    }
}
