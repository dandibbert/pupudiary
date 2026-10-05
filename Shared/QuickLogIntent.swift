import AppIntents
import WidgetKit

struct QuickLogIntent: AppIntent {
    static var title: LocalizedStringResource = "记下此刻"
    static var description = IntentDescription("只记录当前时间，其余详情留空。可以在噗噗手帐里补充或撤销。")
    static var openAppWhenRun = false
    func perform() async throws -> some IntentResult {
        guard let directory = StorageLocation.sharedDirectory else { throw IntentError.sharedStorageUnavailable }
        let store = try DiaryStore(url: StorageLocation.database(in: directory))
        _ = try store.quickLog(at: Date())
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
    enum IntentError: Error, CustomLocalizedStringResourceConvertible {
        case sharedStorageUnavailable
        var localizedStringResource: LocalizedStringResource { "小组件暂时无法共享手帐，请打开 App 记录。" }
    }
}
