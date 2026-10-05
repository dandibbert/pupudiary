import SwiftUI
import UIKit

struct ExportView: View {
    @Environment(RecordStore.self) private var store
    @State private var format = ExportFormat.pdf
    @State private var range = ExportRange.month
    @State private var shareItem: ShareItem?
    @State private var errorText: String?

    struct ShareItem: Identifiable {
        let id = UUID()
        let url: URL
    }

    private var count: Int {
        Exporter.filter(store.records, range: range, now: Date()).count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle(title: "导出成什么", symbol: "doc.fill")
                    ForEach(ExportFormat.allCases) { f in
                        let on = f == format
                        Button {
                            format = f
                            Haptics.tap()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: f.symbol)
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(on ? .white : Theme.primary)
                                    .frame(width: 42, height: 42)
                                    .background(on ? Theme.primary : Theme.primarySoft,
                                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(f.title).font(.cute(16, .bold)).foregroundStyle(Theme.ink)
                                    Text(f.subtitle).font(.cute(12, .medium)).foregroundStyle(Theme.subtle)
                                }
                                Spacer()
                                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 22))
                                    .foregroundStyle(on ? Theme.primary : Theme.subtle.opacity(0.4))
                            }
                            .padding(10)
                            .background(on ? Theme.primarySoft.opacity(0.5) : .clear,
                                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .cardStyle()

                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle(title: "时间范围", symbol: "calendar", trailing: "共 \(count) 条")
                    Picker("时间范围", selection: $range) {
                        ForEach(ExportRange.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                .cardStyle()

                Button(action: export) {
                    Label("生成并分享", systemImage: "square.and.arrow.up")
                        .font(.cute(18, .heavy))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(count == 0 ? Theme.subtle.opacity(0.5) : Theme.primary,
                                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(PressableStyle())
                .disabled(count == 0)

                if let errorText {
                    Text(errorText).font(.cute(13, .medium)).foregroundStyle(Theme.warning)
                }

                Text("生成后可以「存储到文件」、AirDrop、发给自己或打印。JSON 备份可以在「我的 › 导入」恢复。")
                    .font(.cute(12, .medium))
                    .foregroundStyle(Theme.subtle)
            }
            .padding(16)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("导出记录")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $shareItem) { item in
            ActivityView(items: [item.url])
                .presentationDetents([.medium, .large])
        }
    }

    private func export() {
        do {
            let url = try Exporter.export(store.records, format: format, range: range)
            errorText = nil
            shareItem = ShareItem(url: url)
        } catch {
            errorText = "导出失败：\(error.localizedDescription)"
        }
    }
}

/// 系统分享面板
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
