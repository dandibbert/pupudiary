import SwiftUI
import UniformTypeIdentifiers

/// 导入：支持 PoopLog 备份（zip / data.mdb）和噗噗手帐的 JSON 备份。
/// 文件类型不做限制（有些备份在「文件」里识别不出类型，会变成灰色选不了），选中后按内容自动判断。
struct ImportView: View {
    @Environment(RecordStore.self) private var store
    @State private var state = Phase.idle
    /// 从「文件」等 App 共享过来的文件，打开页面后自动导入
    var incomingURL: URL? = nil

    enum Phase {
        case idle
        case working
        case done(source: String, total: Int, added: Int, first: Date?, last: Date?)
        case failed(String)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle(title: "支持的备份", symbol: "tray.and.arrow.down.fill")
                    source(icon: "arrow.triangle.2.circlepath", color: GutStatus.loose.color,
                           title: "PoopLog 备份",
                           text: "在 PoopLog 里导出备份，得到 poop_log_backup_xxx.zip，直接选它即可。")
                    source(icon: "doc.text.fill", color: Theme.primary,
                           title: "噗噗手帐 JSON 备份",
                           text: "在「我的 › 导出记录」里导出的 JSON 文件。")
                    Text("也可以在「文件」App 里长按备份 › 共享 › 选择「噗噗手帐」直接导入。重复导入同一份备份不会产生重复记录。")
                        .font(.cute(12, .medium))
                        .foregroundStyle(Theme.subtle)
                }
                .cardStyle()

                Button {
                    DocumentPicker.shared.present { url in
                        if let url { importFile(url) }
                    }
                } label: {
                    HStack {
                        if case .working = state {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "folder.fill")
                        }
                        Text(isWorking ? "正在导入…" : "选择备份文件")
                    }
                    .font(.cute(18, .heavy))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Theme.primary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(PressableStyle())
                .disabled(isWorking)

                result
            }
            .padding(16)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("导入数据")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task {
            if let incomingURL, case .idle = state { importFile(incomingURL) }
        }
    }

    private var isWorking: Bool {
        if case .working = state { return true }
        return false
    }

    @ViewBuilder
    private var result: some View {
        switch state {
        case .idle, .working:
            EmptyView()
        case let .done(source, total, added, first, last):
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Mascot(mood: .excited).frame(width: 52, height: 52)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("导入成功！").font(.cute(18, .heavy)).foregroundStyle(Theme.ink)
                        Text("来自 \(source)").font(.cute(13, .medium)).foregroundStyle(Theme.subtle)
                    }
                }
                HStack(spacing: 8) {
                    stat("读取", "\(total) 条", GutStatus.loose.color)
                    stat("新增", "\(added) 条", GutStatus.ideal.color)
                    stat("更新", "\(total - added) 条", Theme.primary)
                }
                if let first, let last {
                    Text("时间范围：\(first.formatted(.dateTime.year().month().day())) — \(last.formatted(.dateTime.year().month().day()))")
                        .font(.cute(12, .medium))
                        .foregroundStyle(Theme.subtle)
                }
            }
            .cardStyle()
        case let .failed(message):
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.warning)
                VStack(alignment: .leading, spacing: 4) {
                    Text("导入失败").font(.cute(16, .bold)).foregroundStyle(Theme.ink)
                    Text(message).font(.cute(13, .medium)).foregroundStyle(Theme.subtle)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(Theme.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func source(icon: String, color: Color, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(color, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.cute(15, .bold)).foregroundStyle(Theme.ink)
                Text(text).font(.cute(12, .medium)).foregroundStyle(Theme.subtle)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func stat(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.cute(16, .heavy)).foregroundStyle(color)
            Text(title).font(.cute(11, .medium)).foregroundStyle(Theme.subtle)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func importFile(_ url: URL) {
        state = .working
        Task {
            let parsed: Result<(String, [PoopRecord]), Error> = await Task.detached {
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                do {
                    let data = try Data(contentsOf: url)
                    if PoopLogImporter.isPoopLogBackup(data) {
                        return .success(("PoopLog", try PoopLogImporter.records(from: data)))
                    }
                    return .success(("噗噗手帐备份", try Exporter.importJSON(data)))
                } catch {
                    return .failure(error)
                }
            }.value

            switch parsed {
            case let .success((source, records)):
                let added = store.merge(records)
                let sorted = records.map(\.timestamp).sorted()
                Haptics.success()
                state = .done(source: source, total: records.count, added: added, first: sorted.first, last: sorted.last)
            case let .failure(error):
                if let e = error as? PoopLogImporter.ImportError {
                    state = .failed(e.errorDescription ?? "无法读取 PoopLog 备份。")
                } else if error is DecodingError {
                    state = .failed("文件格式不对。请选择 PoopLog 导出的 zip 备份，或噗噗手帐导出的 JSON 备份。")
                } else {
                    state = .failed("读取失败：\(error.localizedDescription)")
                }
            }
        }
    }
}
