import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// App 与小组件共享的存储位置（App Group）
enum AppGroup {
    /// 从 Info.plist 读取，方便自签时改成自己的 App Group
    static var identifier: String {
        (Bundle.main.object(forInfoDictionaryKey: "AppGroupID") as? String) ?? "group.com.pupudiary.app"
    }

    /// 共享容器；如果签名里没有 App Group（部分自签工具），退回到 App 自己的目录
    static var containerURL: URL {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) {
            return url
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    static var isShared: Bool {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) != nil
    }

    static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }
}

/// 记录以 JSON 文件保存，所有读写都经过文件协调，App 和小组件同时写也不会丢数据
enum RecordStorage {
    private static var directory: URL {
        let dir = AppGroup.containerURL.appendingPathComponent("Pupudiary", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    static var fileURL: URL { directory.appendingPathComponent("records.json") }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// 读取全部记录（按时间倒序）
    static func load() -> [PoopRecord] {
        var result: [PoopRecord] = []
        var coordError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: fileURL, options: [], error: &coordError) { url in
            result = decode(at: url)
        }
        return result.sorted { $0.timestamp > $1.timestamp }
    }

    /// 读-改-写，一次完成
    @discardableResult
    static func mutate(_ change: (inout [PoopRecord]) -> Void) -> [PoopRecord] {
        var result: [PoopRecord] = []
        var coordError: NSError?
        withoutActuallyEscaping(change) { change in
            NSFileCoordinator().coordinate(writingItemAt: fileURL, options: [], error: &coordError) { url in
                var records = decode(at: url)
                change(&records)
                records.sort { $0.timestamp > $1.timestamp }
                if let data = try? encoder.encode(records) {
                    try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                }
                result = records
            }
        }
        markChanged()
        return result
    }

    private static func decode(at url: URL) -> [PoopRecord] {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return [] }
        return (try? decoder.decode([PoopRecord].self, from: data)) ?? []
    }

    /// 通知小组件刷新，并留下修改时间戳供 App 回到前台时判断
    static func markChanged() {
        AppGroup.defaults.set(Date().timeIntervalSince1970, forKey: "lastChange")
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    static var lastChange: TimeInterval {
        AppGroup.defaults.double(forKey: "lastChange")
    }
}

/// App 与小组件共用的设置
enum SharedSettings {
    static let quickTypeKey = "quickDefaultType"

    /// 一键记录时默认使用的分型
    static var quickDefaultType: BristolType {
        get {
            let raw = AppGroup.defaults.integer(forKey: quickTypeKey)
            return BristolType(rawValue: raw) ?? .t4
        }
        set {
            AppGroup.defaults.set(newValue.rawValue, forKey: quickTypeKey)
        }
    }
}
