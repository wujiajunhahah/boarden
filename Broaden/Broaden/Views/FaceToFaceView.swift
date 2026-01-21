import SwiftUI

struct FaceToFaceView: View {
    @State private var leftText = ""
    @State private var rightText = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("面对面沟通")
                .font(.title2.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 12) {
                ConversationPanel(title: "我", text: $leftText)
                ConversationPanel(title: "对方", text: $rightText)
            }

            Button {
                Haptics.lightImpact()
            } label: {
                Label("语音转文字（占位）", systemImage: "mic")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("语音转文字")
            .accessibilityHint("后续可接入语音转文字功能")

            Spacer()
        }
        .padding(20)
        .navigationTitle("沟通模式")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ConversationPanel: View {
    let title: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            TextEditor(text: $text)
                .font(.title2)
                .padding(8)
                .frame(minHeight: 200)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel("输入")
                .accessibilityHint("在此输入文本")
        }
        .frame(maxWidth: .infinity)
    }
}
