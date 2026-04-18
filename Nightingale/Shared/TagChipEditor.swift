import SwiftUI

/// 标签输入 / 展示（Phase 3 · P3.4）。通用组件：把 `[String]` 展示成 chip 列表，
/// 支持点 X 删除、点"+"弹出 prompt 加新标签。保存由外层 binding 决定。
struct TagChipEditor: View {
    @Binding var tags: [String]

    @State private var showAddPrompt = false
    @State private var draft: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(tags, id: \.self) { tag in
                    HStack(spacing: 4) {
                        Text(tag)
                            .font(.footnote)
                            .foregroundStyle(Theme.textPrimary)
                        Button {
                            remove(tag)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.textTertiary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Theme.surfaceElevated)
                    .clipShape(Capsule())
                }

                Button {
                    draft = ""
                    showAddPrompt = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                        Text("标签")
                    }
                    .font(.footnote)
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .overlay(
                        Capsule().stroke(Theme.accent, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .alert("添加标签", isPresented: $showAddPrompt) {
            TextField("例如：昨晚喝酒", text: $draft)
                .textInputAutocapitalization(.never)
            Button("取消", role: .cancel) {}
            Button("添加") { commit() }
        } message: {
            Text("标签可用于在趋势页按分组比较。")
        }
    }

    private func remove(_ tag: String) {
        tags.removeAll { $0 == tag }
    }

    private func commit() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !tags.contains(trimmed) { tags.append(trimmed) }
        draft = ""
    }
}
