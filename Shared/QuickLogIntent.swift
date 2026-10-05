import Foundation
import AppIntents
import WidgetKit

struct QuickLogIntent: AppIntent {
    static var title: LocalizedStringResource = "记下此刻"
    static var description = IntentDescription("只记录当前时间，其余详情留空。可以在噗噗手帐里补充或撤销。")
    static var openAppWhenRun = false
    #if DEBUG && targetEnvironment(simulator)
    // Scoped to the calling test task, so parallel tests cannot redirect each
    // other or the real app. This seam is absent from device/release builds.
    @TaskLocal static var testingDirectory: URL?
    #endif
    func perform() async throws -> some IntentResult {
        let directory: URL?
        #if DEBUG && targetEnvironment(simulator)
        directory = Self.testingDirectory ?? StorageLocation.sharedDirectory
        #else
        directory = StorageLocation.sharedDirectory
        #endif
        guard let directory else { throw IntentError.sharedStorageUnavailable }
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
