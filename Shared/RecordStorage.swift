import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// App 与小组件共享的存储位置（App Group）
///
/// 自签工具（如 sign.lc、全能签）通常会把 App Group 换成证书里的 ID（例如 group.xxxx.1），
/// 但不会改 Info.plist。所以这里在运行时从签名用的描述文件里找出真正可用的 App Group，
/// App 和小组件按同样的规则选择，保证两边用的是同一个容器。
enum AppGroup {
    static let identifier: String = resolveIdentifier()

    /// 当前是否真的在使用共享容器
    static var isShared: Bool { sharedContainer != nil }

    private static let sharedContainer: URL? =
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)

    /// 共享容器；没有可用的 App Group 时退回到自己的目录
    static var containerURL: URL { sharedContainer ?? localContainer }

    static var localContainer: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    static let defaults: UserDefaults =
        (isShared ? UserDefaults(suiteName: identifier) : nil) ?? .standard

    /// Info.plist 里写的（Xcode / resign.sh 编译时的值）
    static var configuredIdentifier: String {
        (Bundle.main.object(forInfoDictionaryKey: "AppGroupID") as? String) ?? "group.com.pupudiary.app"
    }

    /// 描述文件里声明的所有 App Group
    static let profileGroups: [String] = {
        for url in profileURLs {
            if let groups = groups(inProfileAt: url), !groups.isEmpty { return groups }
        }
        return []
    }()

    private static func resolveIdentifier() -> String {
        let configured = configuredIdentifier
        let fm = FileManager.default
        // 优先：Info.plist 里配置的，且确实可用
        if profileGroups.isEmpty || profileGroups.contains(configured),
           fm.containerURL(forSecurityApplicationGroupIdentifier: configured) != nil {
            return configured
        }
        // 其次：描述文件里的 group，按名字排序后取第一个可用的（App 和小组件结果一致）
        for g in profileGroups.sorted() where fm.containerURL(forSecurityApplicationGroupIdentifier: g) != nil {
            return g
        }
        return configured
    }

    /// 先看主 App 的描述文件（App 和小组件读同一份，选出的 group 一定相同），再看自己的
    private static var profileURLs: [URL] {
        var bundle = Bundle.main.bundleURL
        var urls: [URL] = []
        if bundle.pathExtension == "appex" {
            let own = bundle.appendingPathComponent("embedded.mobileprovision")
            bundle = bundle.deletingLastPathComponent().deletingLastPathComponent()
            urls.append(bundle.appendingPathComponent("embedded.mobileprovision"))
            urls.append(own)
        } else {
            urls.append(bundle.appendingPathComponent("embedded.mobileprovision"))
        }
        return urls
    }

    /// embedded.mobileprovision 是 CMS 签名包着的 XML plist，直接截出 plist 部分解析
    private static func groups(inProfileAt url: URL) -> [String]? {
        guard let data = try? Data(contentsOf: url),
              let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex)
        else { return nil }
        let plistData = data.subdata(in: start.lowerBound..<end.upperBound)
        guard let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any],
              let ent = plist["Entitlements"] as? [String: Any]
        else { return nil }
        return ent["com.apple.security.application-groups"] as? [String]
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

    /// 以前没连上 App Group 时保存在 App 自己目录里的数据，连上后自动并入共享容器（只做一次）
    static func migrateLocalDataIfNeeded() {
        guard AppGroup.isShared else { return }
        let local = AppGroup.localContainer
            .appendingPathComponent("Pupudiary", isDirectory: true)
            .appendingPathComponent("records.json")
        guard local != fileURL, FileManager.default.fileExists(atPath: local.path) else { return }
        let old = decode(at: local)
        if !old.isEmpty {
            mutate { list in
                let ids = Set(list.map(\.id))
                list.append(contentsOf: old.filter { !ids.contains($0.id) })
            }
        }
        try? FileManager.default.moveItem(at: local, to: local.appendingPathExtension("migrated"))
    }

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
