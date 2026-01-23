import SwiftUI

struct AskView: View {
    let exhibit: Exhibit
    @ObservedObject var viewModel: AskViewModel
    /// 手语数字人协调器 - 用于发送手语脚本实现自动联动
    @ObservedObject var avatarCoordinator: AvatarCoordinator

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
                            viewModel.quickAsk(exhibitId: exhibit.id, question: question, contextText: contextText)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel(question)
                        .accessibilityHint("快速提问")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    viewModel.ask(exhibitId: exhibit.id, question: inputText, contextText: contextText)
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
                        AnswerCardView(response: response, avatarCoordinator: avatarCoordinator)
                    }
                }
                if viewModel.isLoading {
                    ProgressView("正在生成答复")
                        .accessibilityLabel("正在生成答复")
                }
            }
        }
    }

    private var contextText: String {
        let refs = exhibit.references.map { "\($0.refId): \($0.snippet)" }.joined(separator: "\n")
        return """
        标题：\(exhibit.title)
        简介：\(exhibit.shortIntro)
        易读版：\(exhibit.easyText)
        详细：\(exhibit.detailText)
        参考：\(refs)
        """
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
    /// 手语数字人协调器 - 用于发送手语脚本
    @ObservedObject var avatarCoordinator: AvatarCoordinator
    @State private var selectedLayer = 0
    @State private var hasSentSignScript = false

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
            .onChange(of: selectedLayer) { _, newValue in
                // 当用户切换到手语脚本 tab 时，如果还没发送过，则发送
                if newValue == 2 && !hasSentSignScript && !response.signScript.isEmpty && avatarCoordinator.isLoaded {
                    sendSignScript()
                }
            }

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
                    VStack(alignment: .leading, spacing: 8) {
                        Text(response.signScript)
                            .font(.body)

                        // 手语脚本状态指示
                        if avatarCoordinator.isLoaded {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(.green)
                                    .frame(width: 8, height: 8)
                                Text(hasSentSignScript ? "已发送到数字人" : "数字人已就绪")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
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
        .onAppear {
            // 回答卡片出现时，自动发送手语脚本到数字人
            sendSignScriptIfNeeded()
        }
        .onChange(of: avatarCoordinator.isLoaded) { _, isLoaded in
            // 数字人就绪时，发送手语脚本
            if isLoaded {
                sendSignScriptIfNeeded()
            }
        }
    }

    private func sendSignScriptIfNeeded() {
        if !hasSentSignScript && !response.signScript.isEmpty && avatarCoordinator.isLoaded {
            sendSignScript()
        }
    }

    private func sendSignScript() {
        print("[AnswerCardView] 📤 发送追问手语脚本: \(response.signScript.prefix(30))...")
        avatarCoordinator.sendText(response.signScript)
        hasSentSignScript = true
    }

    private var confidenceText: String {
        switch response.confidence {
        case .high: return "高"
        case .medium: return "中"
        case .low: return "低"
        }
    }
}
