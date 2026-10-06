import UIKit
import UniformTypeIdentifiers

/// 系统文件选择器（拷贝模式）。
///
/// SwiftUI 的 .fileImporter 是「原地打开」模式，需要安全作用域授权；在部分重签名的环境里，
/// 点选文件后选择器没有任何反应。拷贝模式由系统先把文件复制到 App 的临时目录，
/// 不需要额外授权，兼容性最好。直接用 UIKit 弹出，也避免和 SwiftUI 的 sheet 互相冲突。
@MainActor
final class DocumentPicker: NSObject, UIDocumentPickerDelegate {
    static let shared = DocumentPicker()

    private var completion: ((URL?) -> Void)?

    func present(types: [UTType] = [.item], completion: @escaping (URL?) -> Void) {
        guard let presenter = Self.topViewController() else {
            completion(nil)
            return
        }
        self.completion = completion
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.allowsMultipleSelection = false
        picker.shouldShowFileExtensions = true
        picker.delegate = self
        presenter.present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        finish(urls.first)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        finish(nil)
    }

    private func finish(_ url: URL?) {
        let done = completion
        completion = nil
        done?(url)
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive } ??
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var top = scene?.windows.first(where: \.isKeyWindow)?.rootViewController ?? scene?.windows.first?.rootViewController
        while let presented = top?.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }
}
