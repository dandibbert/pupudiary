import Foundation
import LocalAuthentication
import UserNotifications
import UIKit

/// App 设置的键名（@AppStorage 使用）
enum SettingsKey {
    static let reminderEnabled = "reminderEnabled"
    static let reminderMinutes = "reminderMinutes"   // 从 0 点开始的分钟数
    static let lockEnabled = "lockEnabled"
    static let hapticsEnabled = "hapticsEnabled"
}

// MARK: - 每日提醒

enum ReminderService {
    private static let id = "daily-reminder"

    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func schedule(minutes: Int) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        let content = UNMutableNotificationContent()
        content.title = "噗噗手帐"
        content.body = ["今天的噗噗记了吗？喝口水，记一笔吧 💧",
                        "小肠道打卡时间到！今天感觉怎么样？",
                        "噗噗在等你～ 记录一下今天的状态吧 🌱"].randomElement()!
        content.sound = .default
        var comps = DateComponents()
        comps.hour = minutes / 60
        comps.minute = minutes % 60
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    static func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }
}

// MARK: - 隐私锁

enum AppLock {
    static var canUseBiometrics: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    static var biometryName: String {
        let ctx = LAContext()
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch ctx.biometryType {
        case .faceID: return "面容 ID"
        case .touchID: return "触控 ID"
        default: return "设备密码"
        }
    }

    static func authenticate() async -> Bool {
        let ctx = LAContext()
        ctx.localizedCancelTitle = "取消"
        return (try? await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "解锁噗噗手帐")) ?? false
    }
}

// MARK: - 触感反馈

enum Haptics {
    static var enabled: Bool {
        UserDefaults.standard.object(forKey: SettingsKey.hapticsEnabled) as? Bool ?? true
    }

    static func success() {
        guard enabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func tap() {
        guard enabled else { return }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }
}
