import SwiftUI

/// 自动快照保存在现有 App Group 的 Pupudiary/Backups 目录。
/// 恢复只补回缺失的 ID，不会覆盖或删除当前记录。
struct StorageBackupView: View {
    @Environment(RecordStore.self) private var store
    @State private var snapshots: [RecordSnapshot] = []
    @State private var selected: RecordSnapshot?
    @State private var resultMessage: String?
    @State private var loadError: String?
    @State private var confirmFreshStart = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    SectionTitle(title: "自动保护", symbol: "externaldrive.fill")
                    Text("每次成功保存前，都会把原始 records.json 备份一份，最多保留最近 40 份。保存失败不会覆盖旧数据。")
                        .font(.cute(13, .medium))
                        .foregroundStyle(Theme.subtle)
                    Text("自动备份只在本机 App Group 内。卸载 App 或更换签名、App Group 前，仍应在「导出记录」生成 JSON 备份并保存到其他位置。")
                        .font(.cute(12, .medium))
                        .foregroundStyle(Theme.warning)
                }
                .cardStyle()

                if store.hasUnexpectedRecordDrop {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionTitle(title: "记录数量异常", symbol: "exclamationmark.triangle.fill")
                        Text("App 发现记录数量意外减少。为保护旧数据，已停止新保存。建议先检查下方历史快照和「诊断信息」中的其他 App Group。")
                            .font(.cute(13, .medium))
                            .foregroundStyle(Theme.warning)
                        Button("我确认无需恢复，允许从当前记录重新开始") {
                            confirmFreshStart = true
                        }
                        .font(.cute(13, .bold))
                        .foregroundStyle(Theme.warning)
                    }
                    .cardStyle()
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        SectionTitle(title: "历史快照", symbol: "clock.arrow.circlepath", trailing: "\(snapshots.count) 份")
                        Spacer()
                        Button("刷新", action: refresh)
                            .font(.cute(13, .bold))
                    }

                    if let loadError {
                        Text(loadError)
                            .font(.cute(13, .medium))
                            .foregroundStyle(Theme.warning)
                    } else if snapshots.isEmpty {
                        Text("暂无历史快照。首次保存只创建数据文件；下一次成功保存前会自动保留上一版。")
                            .font(.cute(13, .medium))
                            .foregroundStyle(Theme.subtle)
                    } else {
                        ForEach(snapshots) { item in
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.createdAt.formatted(.dateTime.year().month().day().hour().minute().second()))
                                        .font(.cute(14, .bold))
                                        .foregroundStyle(Theme.ink)
                                    Text("\(item.count) 条记录")
                                        .font(.cute(12, .medium))
                                        .foregroundStyle(Theme.subtle)
                                }
                                Spacer(minLength: 4)
                                ShareLink(item: item.url) {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.system(size: 17, weight: .semibold))
                                }
                                .accessibilityLabel("导出此快照")
                                Button("合并恢复") { selected = item }
                                    .font(.cute(13, .bold))
                                    .disabled(item.count == 0)
                            }
                            .padding(.vertical, 8)
                            Divider()
                        }
                    }
                }
                .cardStyle()
            }
            .padding(16)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("自动备份与恢复")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .onAppear(perform: refresh)
        .confirmationDialog("合并历史快照？", isPresented: Binding(
            get: { selected != nil },
            set: { if !$0 { selected = nil } }
        ), titleVisibility: .visible) {
            Button("恢复缺失的记录", action: restore)
            Button("取消", role: .cancel) { selected = nil }
        } message: {
            Text("只补回当前没有的记录，现有记录不会被删除或覆盖。如果当前数据损坏，会先隔离原始损坏文件。")
        }
        .confirmationDialog("确认放弃寻找旧记录？", isPresented: $confirmFreshStart, titleVisibility: .visible) {
            Button("从当前数据继续记录", role: .destructive) {
                store.acceptCurrentRecordsAsNewBaseline()
                resultMessage = store.hasUnexpectedRecordDrop
                    ? "尚未完成重置，请检查存储错误。"
                    : "已允许从当前记录继续使用。"
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作不删除现有文件或历史快照，但可能使你错过恢复旧记录的机会。")
        }
        .alert("备份操作", isPresented: Binding(
            get: { resultMessage != nil },
            set: { if !$0 { resultMessage = nil } }
        )) {
            Button("好的", role: .cancel) { resultMessage = nil }
        } message: {
            Text(resultMessage ?? "")
        }
    }

    private func refresh() {
        do {
            snapshots = try RecordStorage.snapshots()
            loadError = nil
        } catch {
            loadError = "读取自动备份失败：\(error.localizedDescription)"
        }
    }

    private func restore() {
        guard let selected else { return }
        self.selected = nil
        do {
            let added = try RecordStorage.restoreMissingRecords(from: selected.id)
            store.reload()
            refresh()
            resultMessage = "恢复完成：补回 \(added) 条缺失记录，原有记录保留。"
        } catch {
            resultMessage = "恢复失败，未确认写入：\(error.localizedDescription)"
        }
    }
}
