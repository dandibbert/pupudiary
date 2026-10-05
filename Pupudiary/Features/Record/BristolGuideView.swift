import SwiftUI

/// 布里斯托分型说明
struct BristolGuideView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("布里斯托大便分类法是医生常用的参考标准，把形态分成 7 型。3、4 型最理想；1、2 型偏干，可能是便秘；6、7 型偏稀，可能是腹泻。")
                        .font(.cute(14, .medium))
                        .foregroundStyle(Theme.subtle)
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(GutStatus.allCases) { status in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(status.emoji)
                                Text(status.title).font(.cute(17, .heavy)).foregroundStyle(status.color)
                                Spacer()
                            }
                            ForEach(BristolType.allCases.filter { $0.status == status }) { t in
                                HStack(spacing: 12) {
                                    BristolIcon(type: t)
                                        .frame(width: 48, height: 48)
                                        .padding(4)
                                        .background(status.softColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("\(t.label) · \(t.nickname)").font(.cute(15, .bold)).foregroundStyle(Theme.ink)
                                        Text(t.hint).font(.cute(13, .medium)).foregroundStyle(Theme.subtle)
                                    }
                                    Spacer(minLength: 0)
                                }
                            }
                            Text(status.advice)
                                .font(.cute(12, .medium))
                                .foregroundStyle(Theme.subtle)
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(status.softColor, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .cardStyle()
                    }

                    Text("颜色小贴士：棕色、黄棕色都很常见；绿色多与蔬菜或饮食有关。黑色、红色或灰白色如果不是食物或药物引起，并且反复出现，建议及时就医。")
                        .font(.cute(13, .medium))
                        .foregroundStyle(Theme.subtle)
                        .cardStyle()

                    Text("本 App 仅用于日常记录，不能代替专业医疗建议。")
                        .font(.cute(12, .medium))
                        .foregroundStyle(Theme.subtle)
                        .frame(maxWidth: .infinity)
                }
                .padding(16)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("七种类型怎么分")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("好的") { dismiss() }
                }
            }
        }
    }
}
