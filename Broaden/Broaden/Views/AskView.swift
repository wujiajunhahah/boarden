import SwiftUI

struct AskView: View {
    let exhibit: Exhibit
    @ObservedObject var viewModel: AskViewModel

    @State private var inputText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("追问")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                TextField("输入问题", text: $inputText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("追问输入框")
                    .accessibilityHint("输入想了解的问题")

                HStack(spacing: 8) {
                    ForEach(quickQuestions, id: \.self) { question in
                        Button(question) {
                            viewModel.quickAsk(exhibitId: exhibit.id, question: question)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel(question)
                        .accessibilityHint("快速提问")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    viewModel.ask(exhibitId: exhibit.id, question: inputText)
                    inputText = ""
                } label: {
                    Label("提交追问", systemImage: "paperplane")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("提交追问")
                .accessibilityHint("发送问题并获取回复")
            }

            if let error = viewModel.errorMessage {
                Label(error + "，可尝试以下问题", systemImage: "info.circle")
                    .font(.callout)
                    .padding(12)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityLabel(error)
            }

            VStack(spacing: 12) {
                ForEach(viewModel.messages) { message in
                    if message.isUser {
                        ChatBubble(text: message.text, isUser: true)
                    } else if let response = message.response {
                        AnswerCardView(response: response)
                    }
                }
                if viewModel.isLoading {
                    ProgressView("正在生成答复")
                        .accessibilityLabel("正在生成答复")
                }
            }
        }
    }

    private var quickQuestions: [String] {
        ["为什么重要", "制作或修复", "术语解释"]
    }
}

private struct ChatBubble: View {
    let text: String
    let isUser: Bool

    var body: some View {
        HStack {
            if isUser { Spacer() }
            Text(text)
                .font(.body)
                .padding(12)
                .background(isUser ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            if !isUser { Spacer() }
        }
        .accessibilityLabel(text)
    }
}

private struct AnswerCardView: View {
    let response: AskResponse
    @State private var selectedLayer = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("回答层级", selection: $selectedLayer) {
                Text("简版").tag(0)
                Text("详版").tag(1)
                Text("手语脚本").tag(2)
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("回答层级")
            .accessibilityHint("切换简版、详版或手语脚本")

            Group {
                switch selectedLayer {
                case 1:
                    Text(response.answerDetail)
                        .font(.body)
                        .foregroundStyle(.secondary)
                    if !response.citations.isEmpty {
                        Text("引用片段：" + response.citations.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                case 2:
                    Text(response.signScript)
                        .font(.body)
                default:
                    Text(response.answerSimple)
                        .font(.body)
                }
            }

            Text("置信度：" + confidenceText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityLabel("回答")
    }

    private var confidenceText: String {
        switch response.confidence {
        case .high: return "高"
        case .medium: return "中"
        case .low: return "低"
        }
    }
}
