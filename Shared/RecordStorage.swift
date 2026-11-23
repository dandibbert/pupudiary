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

    /// iOS 刚重启、文件保护尚未解锁时共享容器可能暂时不可访问。
    /// 不能用 static let 缓存一次 nil，否则整个进程都会误以为没有 App Group。
    private static var sharedContainer: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    /// 共享容器；没有可用的 App Group 时退回到自己的目录
    static var containerURL: URL { sharedContainer ?? localContainer }

    static var localContainer: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    static var defaults: UserDefaults {
        (isShared ? UserDefaults(suiteName: identifier) : nil) ?? .standard
    }

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

    /// 一个证书可能授权多个 group。首个可访问 group 不是稳定身份：
    /// 它会随着重启后的容器挂载状态或重签名工具改写 Info.plist 而变化。
    /// 在可解析描述文件时始终固定到同一个「字典序最小」的 group，
    /// 即使它临时不可用也绝不悄悄切到另一个空目录。
    static func preferredIdentifier(configured: String, declaredGroups: [String]) -> String {
        let groups = declaredGroups.filter { $0.hasPrefix("group.") }
        return groups.sorted().first ?? configured
    }

    private static func resolveIdentifier() -> String {
        preferredIdentifier(configured: configuredIdentifier, declaredGroups: profileGroups)
    }

    /// 既供用户诊断，也供主 App 从其他已授权容器安全合并旧记录。
    static var candidateGroups: [String] {
        Array(Set(profileGroups + [configuredIdentifier])).sorted()
    }

    static var expectedSharedButUnavailable: Bool {
        !profileGroups.isEmpty && !isShared
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

    private static func groups(inProfileAt url: URL) -> [String]? {
        guard let ent = profile(at: url)?["Entitlements"] as? [String: Any] else { return nil }
        return ent["com.apple.security.application-groups"] as? [String]
    }

    /// embedded.mobileprovision 是 CMS 签名包着的 XML plist，直接截出 plist 部分解析
    static func profile(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url),
              let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex)
        else { return nil }
        let plistData = data.subdata(in: start.lowerBound..<end.upperBound)
        return try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any]
    }
}

/// 数据不能被「读取失败 => 空数组」这种逻辑清空。
/// App/Widget 都必须在读取、协调、备份和写入成功后才能报告保存成功。
enum RecordStorageError: LocalizedError {
    case missingPreviousFile
    case sharedUnavailable(String)
    case unexpectedDrop(previous: Int, actual: Int)
    case unreadable(String)
    case corrupt(String)
    case coordination(String)
    case invalidBackup(String)

    var errorDescription: String? {
        switch self {
        case .missingPreviousFile:
            return "原记录文件意外消失，已阻止写入。请在「我的 › 自动备份与恢复」检查历史快照。"
        case let .sharedUnavailable(group):
            return "共享数据容器 \(group) 暂时不可访问。已停止写入，避免把记录存到另一个空目录。请在解锁设备后重试并查看诊断信息。"
        case let .unexpectedDrop(previous, actual):
            return "检测到记录数从 \(previous) 变为 \(actual)，可能读取了错误的容器。已禁止新保存，请先在「自动备份与恢复」检查旧记录。"
        case let .unreadable(reason):
            return "记录文件暂时无法读取，未进行写入：\(reason)"
        case let .corrupt(reason):
            return "记录文件格式异常，已阻止写入以免覆盖旧数据：\(reason)"
        case let .coordination(reason):
            return "记录存储协调失败，未确认写入：\(reason)"
        case let .invalidBackup(reason):
            return "备份无法恢复：\(reason)"
        }
    }

    var permitsExplicitRepair: Bool {
        switch self {
        case .corrupt, .missingPreviousFile: return true
        default: return false
        }
    }
}

struct RecordSnapshot: Identifiable {
    let url: URL
    let createdAt: Date
    let count: Int
    let source: String

    /// The full *enumerated* URL avoids name collisions between backup containers.
    /// Restoration never accepts arbitrary paths; it resolves IDs against snapshots().
    var id: String { url.standardizedFileURL.path }
}

/// 保留原有的 App Group 与 Pupudiary/records.json 路径，兼容已安装的 Claude 版。
enum RecordStorage {
    #if DEBUG
    /// 独立 macOS 存储测试使用；Release 不编译此入口。
    static var testDirectory: URL?
    #endif

    private static var directory: URL {
        #if DEBUG
        if let testDirectory { return testDirectory }
        #endif
        return AppGroup.containerURL.appendingPathComponent("Pupudiary", isDirectory: true)
    }

    static var fileURL: URL { directory.appendingPathComponent("records.json") }
    private static var backupsURL: URL { directory.appendingPathComponent("Backups", isDirectory: true) }
    private static var privateBackupsURL: URL {
        #if DEBUG
        if let testDirectory { return testDirectory.appendingPathComponent("PrivateBackups", isDirectory: true) }
        #endif
        return AppGroup.localContainer
            .appendingPathComponent("Pupudiary", isDirectory: true)
            .appendingPathComponent("Backups", isDirectory: true)
    }
    private static var markerURL: URL { directory.appendingPathComponent(".records-initialized") }
    private static let maximumSnapshots = 40

    /// 无法访问声明的共享容器时绝不改写另一套私有数据库。
    /// 仅独立回归测试可指定临时目录。
    private static func requireStorage() throws {
        #if DEBUG
        if testDirectory != nil { return }
        #endif
        guard AppGroup.isShared else {
            throw RecordStorageError.sharedUnavailable(AppGroup.identifier)
        }
    }

    /// 启动时检测同一签名授权的其他 App Group 里是否有这款 App 的记录。
    /// 只做「按 UUID 补齐」，不会移动/删除其他组中的原文件；新旧签名选错
    /// Group 时仍可以重新找到数据，且不必破坏历史快照。
    static func mergeOtherGroupsIfNeeded() throws -> Int {
        try requireStorage()
        guard AppGroup.isShared else { return 0 }
        var merged = 0
        var errors: [String] = []
        var known = Set(try load().map(\.id))
        let fm = FileManager.default
        do {
            _ = try preserveAlternateSnapshots()
        } catch {
            errors.append("迁移其他 Group 的历史快照失败：\(error.localizedDescription)")
        }

        for group in AppGroup.candidateGroups where group != AppGroup.identifier {
            guard let container = fm.containerURL(forSecurityApplicationGroupIdentifier: group) else { continue }
            let source = container.appendingPathComponent("Pupudiary/records.json")
            guard fm.fileExists(atPath: source.path) else { continue }
            do {
                var rows: [PoopRecord]?
                var readFailure: Error?
                var coordinatorFailure: NSError?
                NSFileCoordinator().coordinate(readingItemAt: source, options: [], error: &coordinatorFailure) { safeURL in
                    do { rows = try read(at: safeURL).records }
                    catch { readFailure = error }
                }
                if let coordinatorFailure { throw RecordStorageError.coordination(coordinatorFailure.localizedDescription) }
                if let readFailure { throw readFailure }
                guard let rows else { throw RecordStorageError.coordination("旧容器未返回记录") }
                let missing = rows.filter { !known.contains($0.id) }
                if missing.isEmpty { continue }
                let saved = try mutate { list in
                    var ids = Set(list.map(\.id))
                    for record in missing where ids.insert(record.id).inserted {
                        list.append(record)
                    }
                }
                let latest = Set(saved.map(\.id))
                merged += missing.filter { latest.contains($0.id) }.count
                known = latest
            } catch {
                errors.append("\(group): \(error.localizedDescription)")
            }
        }
        if !errors.isEmpty {
            throw RecordStorageError.unreadable("其他 App Group 中的记录尚未合并：\(errors.joined(separator: "; "))")
        }
        return merged
    }

    /// 小组件只读检测：其他已授权 group 中可能还留有未合并记录。
    /// 这种情况下不要将一个不完整的数据集冒充「全部记录」。
    static func hasUnmergedAlternateRecords(comparedTo records: [PoopRecord]) -> Bool {
        let known = Set(records.map(\.id))
        let fm = FileManager.default
        for group in AppGroup.candidateGroups where group != AppGroup.identifier {
            guard let base = fm.containerURL(forSecurityApplicationGroupIdentifier: group) else { continue }
            let path = base.appendingPathComponent("Pupudiary/records.json")
            guard let bytes = try? Data(contentsOf: path),
                  let other = try? decoder.decode([PoopRecord].self, from: bytes) else { continue }
            if other.contains(where: { !known.contains($0.id) }) { return true }
        }
        return false
    }

    /// 将其他已授权 App Group 中的旧快照复制到当前目录，保留其原始文件。
    /// 单独使用 recovered- 前缀，不受「最近 40 次自动写入快照」清理策略影响。
    private static func preserveAlternateSnapshots() throws -> Int {
        let fm = FileManager.default
        var copied = 0
        for group in AppGroup.candidateGroups where group != AppGroup.identifier {
            guard let root = fm.containerURL(forSecurityApplicationGroupIdentifier: group) else { continue }
            let sourceDir = root.appendingPathComponent("Pupudiary/Backups", isDirectory: true)
            guard fm.fileExists(atPath: sourceDir.path) else { continue }
            let names = try fm.contentsOfDirectory(atPath: sourceDir.path)
            for name in names where
                (name.hasPrefix("records-") || name.hasPrefix("recovered-")) && name.hasSuffix(".json") {
                let safeGroup = group.replacingOccurrences(of: ".", with: "-")
                let targetName = "recovered-\(safeGroup)-\(name)"
                let dest = backupsURL.appendingPathComponent(targetName)
                if fm.fileExists(atPath: dest.path) { continue }
                try fm.createDirectory(at: backupsURL, withIntermediateDirectories: true)
                try fm.copyItem(at: sourceDir.appendingPathComponent(name), to: dest)
                copied += 1
            }
        }
        return copied
    }

    /// 只读检查：能直接显示当前进程使用的 group，以及其他容器中的文件大小、
    /// 记录数、历史快照数。不能解码时明确注明，绝不显示为「0 条」。
    static func storageSurvey() -> [String] {
        let fm = FileManager.default
        var lines = [
            "configured=\(AppGroup.configuredIdentifier) selected=\(AppGroup.identifier) shared=\(AppGroup.isShared)",
            "已授权 groups=\(AppGroup.profileGroups.sorted().joined(separator: ","))"
        ]
        // App 私有容器在重签或 Group 切换后可能仍然保有副本。
        let privateFolder = AppGroup.localContainer.appendingPathComponent("Pupudiary", isDirectory: true)
        let privateRecord = privateFolder.appendingPathComponent("records.json")
        let privateMigrated = privateFolder.appendingPathComponent("records.json.migrated")
        for (label, file) in [("私有 records.json", privateRecord), ("旧迁移文件", privateMigrated)] {
            if fm.fileExists(atPath: file.path) {
                let size = (try? fm.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.intValue ?? -1
                if let bytes = try? Data(contentsOf: file),
                   let records = try? decoder.decode([PoopRecord].self, from: bytes) {
                    lines.append("\(label) | \(size) B | \(records.count) 条")
                } else {
                    lines.append("\(label) | \(size) B | 文件存在但无法解析")
                }
            }
        }
        let privateSnapshots = (try? fm.contentsOfDirectory(atPath: privateBackupsURL.path))?
            .filter { $0.hasPrefix("records-") && $0.hasSuffix(".json") }.count ?? 0
        lines.append("App 私有备份 | \(privateSnapshots) 份")

        for group in AppGroup.candidateGroups {
            guard let base = fm.containerURL(forSecurityApplicationGroupIdentifier: group) else {
                lines.append("\(group) | 无访问权限")
                continue
            }
            let dir = base.appendingPathComponent("Pupudiary", isDirectory: true)
            let url = dir.appendingPathComponent("records.json")
            let backups = dir.appendingPathComponent("Backups", isDirectory: true)
            let backupCount = (try? fm.contentsOfDirectory(atPath: backups.path))?
                .filter { ($0.hasPrefix("records-") || $0.hasPrefix("recovered-")) && $0.hasSuffix(".json") }.count ?? 0
            if !fm.fileExists(atPath: url.path) {
                lines.append("\(group) | 无 records.json | 快照 \(backupCount)")
                continue
            }
            let bytes = (try? fm.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? -1
            do {
                let records = try read(at: url).records
                lines.append("\(group) | \(bytes) B | \(records.count) 条 | 快照 \(backupCount)")
            } catch {
                lines.append("\(group) | \(bytes) B | 读取失败: \(error.localizedDescription) | 快照 \(backupCount)")
            }
        }
        return lines
    }

    /// 旧版本在 App 私有目录中的文件仅在成功合并后才改名，不允许无声丢弃。
    static func migrateLocalDataIfNeeded() throws {
        guard AppGroup.isShared else { return }
        let local = AppGroup.localContainer
            .appendingPathComponent("Pupudiary", isDirectory: true)
            .appendingPathComponent("records.json")
        guard local != fileURL, FileManager.default.fileExists(atPath: local.path) else { return }

        let old = try read(at: local).records
        if !old.isEmpty {
            _ = try mutate { list in
                var ids = Set(list.map(\.id))
                for record in old where ids.insert(record.id).inserted {
                    list.append(record)
                }
            }
        }
        let migrated = local.appendingPathExtension("migrated")
        // 如果已经有迁移副本，保留两个源文件而不是覆盖旧副本。
        if !FileManager.default.fileExists(atPath: migrated.path) {
            try FileManager.default.moveItem(at: local, to: migrated)
        }
    }

    /// 每次创建独立的编解码器，避免多线程共用可变实例。
    static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    /// nil 原始数据只表示第一次安装；零字节/解码错误/曾有记录却丢文件，全部报错。
    private static func read(at url: URL) throws -> (records: [PoopRecord], bytes: Data?) {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            if url == fileURL &&
                (fm.fileExists(atPath: markerURL.path) || hasSnapshotFiles()) {
                throw RecordStorageError.missingPreviousFile
            }
            return ([], nil)
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw RecordStorageError.unreadable(error.localizedDescription)
        }
        guard !data.isEmpty else { throw RecordStorageError.corrupt("文件为 0 字节") }
        do {
            let records = try decoder.decode([PoopRecord].self, from: data)
            guard Set(records.map(\.id)).count == records.count else {
                throw RecordStorageError.corrupt("发现重复的记录 ID")
            }
            return (records, data)
        } catch let error as RecordStorageError {
            throw error
        } catch {
            throw RecordStorageError.corrupt(error.localizedDescription)
        }
    }

    /// 读取失败不会再显示为「零条记录」。
    static func load() throws -> [PoopRecord] {
        try requireStorage()
        let url = fileURL
        if !FileManager.default.fileExists(atPath: url.path) {
            return try read(at: url).records
        }

        var result: [PoopRecord]?
        var readError: Error?
        var coordError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordError) { target in
            do { result = try read(at: target).records }
            catch { readError = error }
        }
        if let coordError { throw RecordStorageError.coordination(coordError.localizedDescription) }
        if let readError { throw readError }
        guard let result else { throw RecordStorageError.coordination("读取协调器未返回数据") }
        return result.sorted { $0.timestamp > $1.timestamp }
    }

    @discardableResult
    static func mutate(_ change: (inout [PoopRecord]) -> Void) throws -> [PoopRecord] {
        try coordinatedWrite(change, allowRepair: false)
    }

    /// 所有写入都串行协调：读取成功 -> 先备份旧字节 -> 原子写入 -> 通知成功。
    @discardableResult
    private static func coordinatedWrite(
        _ change: (inout [PoopRecord]) -> Void,
        allowRepair: Bool
    ) throws -> [PoopRecord] {
        try requireStorage()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var result: [PoopRecord]?
        var writeError: Error?
        var coordError: NSError?

        withoutActuallyEscaping(change) { change in
            NSFileCoordinator().coordinate(writingItemAt: fileURL, options: [], error: &coordError) { target in
                do {
                    var records: [PoopRecord]
                    var original: Data?
                    do {
                        let current = try read(at: target)
                        records = current.records
                        original = current.bytes
                    } catch let storageError as RecordStorageError {
                        guard allowRepair && storageError.permitsExplicitRepair else { throw storageError }
                        // 用户显式选择恢复时也先隔离损坏文件，不直接丢弃任何原始字节。
                        if FileManager.default.fileExists(atPath: target.path) {
                            let damaged = try Data(contentsOf: target)
                            try saveCopy(damaged, prefix: "damaged", in: backupsURL)
                        }
                        records = []
                        original = nil
                    }

                    change(&records)
                    records.sort { $0.timestamp > $1.timestamp }
                    let encoded = try encoder.encode(records)
                    // 将本次要保存的完整记录也持久化：第一次保存就有可恢复副本。
                    // 两个容器全部保存成功后才改写主文件（避免“备份失败仍覆盖主库”）。
                    // 与主文件相同的 App Group 备份供小组件使用；App 私有备份
                    // 可防重签/Group 切换造成的“当前 Group 0 份快照”。
                    // 旧记录也多保留一份，以支持从意外删减中恢复。
                    if let original { try saveCopy(original, prefix: "records", in: backupsURL) }
                    try saveCopy(encoded, prefix: "records", in: backupsURL)
                    try saveCopy(encoded, prefix: "records", in: privateBackupsURL)
                    try encoded.write(to: target, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                    result = records
                    // 主文件已成功提交，清理失败不影响报告成功。
                    try? "1".write(to: markerURL, atomically: true, encoding: .utf8)
                    pruneSnapshots(in: backupsURL)
                    pruneSnapshots(in: privateBackupsURL)
                } catch {
                    writeError = error
                }
            }
        }

        if let coordError { throw RecordStorageError.coordination(coordError.localizedDescription) }
        if let writeError { throw writeError }
        guard let result else { throw RecordStorageError.coordination("写入协调器未完成") }
        markChanged()
        return result
    }

    private static func saveCopy(_ bytes: Data, prefix: String, in folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let name = "\(prefix)-\(timestamp)-\(UUID().uuidString).json"
        let target = folder.appendingPathComponent(name)
        try bytes.write(to: target,
                        options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        // A snapshot is valid only if it can actually be read back and decoded.
        do {
            let confirmed = try Data(contentsOf: target)
            if prefix != "damaged" { _ = try decoder.decode([PoopRecord].self, from: confirmed) }
            guard confirmed == bytes else { throw RecordStorageError.invalidBackup("快照校验失败") }
        } catch {
            try? FileManager.default.removeItem(at: target)
            throw RecordStorageError.invalidBackup("备份校验失败，未修改原文件：\(error.localizedDescription)")
        }
    }

    private static func hasSnapshotFiles() -> Bool {
        for folder in [backupsURL, privateBackupsURL] {
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { continue }
            if names.contains(where: { $0.hasPrefix("records-") && $0.hasSuffix(".json") }) {
                return true
            }
        }
        return false
    }

    /// 只修剪正常历史快照，永不自动删除 damaged- 原始抢救文件。
    private static func pruneSnapshots(in folder: URL) {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return }
        let snapshots = names.filter { $0.hasPrefix("records-") && $0.hasSuffix(".json") }.sorted(by: >)
        for name in snapshots.dropFirst(maximumSnapshots) {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
        }
    }

    /// 统一查找主 App Group、App 私有备份、其他已授权的 App Group。
    /// 列表仅从实际存在且可以解码的文件生成；不能用整数计数冒充恢复能力。
    static func snapshots() throws -> [RecordSnapshot] {
        let fm = FileManager.default
        var locations: [(URL, String)] = [
            (backupsURL, "当前 App Group"),
            (privateBackupsURL, "本 App 私有备份")
        ]
        for group in AppGroup.candidateGroups where group != AppGroup.identifier {
            guard let root = fm.containerURL(forSecurityApplicationGroupIdentifier: group) else { continue }
            locations.append((root.appendingPathComponent("Pupudiary/Backups", isDirectory: true), group))
        }
        var knownPaths = Set<String>()
        var result: [RecordSnapshot] = []
        for (folder, source) in locations {
            guard knownPaths.insert(folder.standardizedFileURL.path).inserted else { continue }
            guard fm.fileExists(atPath: folder.path) else { continue }
            let urls = try fm.contentsOfDirectory(at: folder,
                includingPropertiesForKeys: [.contentModificationDateKey])
            for url in urls {
                guard (url.lastPathComponent.hasPrefix("records-") ||
                       url.lastPathComponent.hasPrefix("recovered-")),
                      url.pathExtension == "json",
                      let bytes = try? Data(contentsOf: url),
                      let rows = try? decoder.decode([PoopRecord].self, from: bytes),
                      let date = try? url.resourceValues(
                          forKeys: [.contentModificationDateKey]).contentModificationDate else { continue }
                result.append(RecordSnapshot(url: url, createdAt: date, count: rows.count, source: source))
            }
        }
        return result.sorted { $0.createdAt > $1.createdAt }
    }

    /// 通过 snapshots() 中已经验证的 URL 恢复，不允许用户输入任意绝对路径。
    @discardableResult
    static func restoreMissingRecords(from snapshotID: String) throws -> Int {
        guard let selected = try snapshots().first(where: { $0.id == snapshotID }) else {
            throw RecordStorageError.invalidBackup("快照不存在或已损坏")
        }
        let data: Data
        do { data = try Data(contentsOf: selected.url) }
        catch { throw RecordStorageError.invalidBackup(error.localizedDescription) }
        let incoming: [PoopRecord]
        do { incoming = try decoder.decode([PoopRecord].self, from: data) }
        catch { throw RecordStorageError.invalidBackup(error.localizedDescription) }
        guard Set(incoming.map(\.id)).count == incoming.count else {
            throw RecordStorageError.invalidBackup("备份中有重复 ID")
        }

        var added = 0
        _ = try coordinatedWrite({ list in
            var ids = Set(list.map(\.id))
            for record in incoming where ids.insert(record.id).inserted {
                list.append(record)
                added += 1
            }
        }, allowRepair: true)
        return added
    }

    /// 只有成功提交后才更新时间戳 / 刷新小组件。
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
