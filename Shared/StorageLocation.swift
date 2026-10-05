import Foundation

struct StorageLocation {
    static let groupID = "group.com.dandibbert.pupudiary"
    static var sharedDirectory: URL? { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) }
    static var privateDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Pupudiary", isDirectory: true)
    }
    static func database(in directory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        // Keep ordinary device backups enabled; this app has no server or analytics.
        return directory.appendingPathComponent("diary.sqlite")
    }
    static var sharedPreferences: UserDefaults? { sharedDirectory == nil ? nil : UserDefaults(suiteName: groupID) }
}
