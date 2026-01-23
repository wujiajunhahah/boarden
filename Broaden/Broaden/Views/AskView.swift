import SwiftUI

struct AskView: View {
    let exhibit: Exhibit
    @ObservedObject var viewModel: AskViewModel
    /// 手语数字人协调器 - 用于发送手语脚本实现自动联动
    @ObservedObject var avatarCoordinator: AvatarCoordinator

    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("追问")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                TextField("输入问题", text: $inputText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .focused($isInputFocused)
                    .submitLabel(.send)
                    .onSubmit {
                        submitQuestion()
                    }
                    .accessibilityLabel("追问输入框")
                    .accessibilityHint("输入想了解的问题")

                HStack(spacing: 8) {
                    ForEach(quickQuestions, id: \.self) { question in
                        Button(question) {
                            isInputFocused = false
                            viewModel.quickAsk(exhibitId: exhibit.id, question: question, contextText: contextText)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel(question)
                        .accessibilityHint("快速提问")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    submitQuestion()
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
                // 加载中提示（显示在最上方，问题下方）
                if viewModel.isLoading {
                    ProgressView("正在生成答复")
                        .accessibilityLabel("正在生成答复")
                }
                
                // 对话历史（新的问答对在上，旧的在下）
                ForEach(viewModel.messages) { message in
                    if message.isUser {
                        ChatBubble(text: message.text, isUser: true)
                    } else if let response = message.response {
                        AnswerCardView(response: response, avatarCoordinator: avatarCoordinator)
                    }
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
    
    private func submitQuestion() {
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        // 先隐藏键盘
        isInputFocused = false
        
        // 提交问题
        viewModel.ask(exhibitId: exhibit.id, question: inputText, contextText: contextText)
        inputText = ""
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
                // 当用户切换到手语脚本时，自动发送到数字人进行翻译
                if newValue == 2 && !response.signScript.isEmpty && avatarCoordinator.isLoaded {
                    avatarCoordinator.sendText(response.signScript)
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
                                Text("数字人已就绪")
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
            // 当新回答出现时，自动发送手语脚本到数字人
            if !response.signScript.isEmpty && avatarCoordinator.isLoaded {
                avatarCoordinator.sendText(response.signScript)
            }
        }
        .onChange(of: avatarCoordinator.isLoaded) { _, isLoaded in
            // 如果数字人刚加载完成，发送手语脚本
            if isLoaded && !response.signScript.isEmpty {
                avatarCoordinator.sendText(response.signScript)
            }
        }
    }

    private var confidenceText: String {
        switch response.confidence {
        case .high: return "高"
        case .medium: return "中"
        case .low: return "低"
        }
    }
}
