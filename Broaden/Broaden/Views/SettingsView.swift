import SwiftUI

struct SettingsView: View {
    @AppStorage("captionSize") private var captionSizeRaw = CaptionSize.medium.rawValue
    @AppStorage("captionBackground") private var captionBackgroundEnabled = true
    @AppStorage("recognitionMode") private var recognitionModeRaw = RecognitionMode.qrOnly.rawValue

    var body: some View {
        Form {
            Section("字幕") {
                Picker("字幕字号", selection: $captionSizeRaw) {
                    ForEach(CaptionSize.allCases) { size in
                        Text(size.title).tag(size.rawValue)
                    }
                }
                .accessibilityLabel("字幕字号")
                .accessibilityHint("选择字幕显示大小")

                Toggle("字幕背景遮罩", isOn: $captionBackgroundEnabled)
                    .accessibilityLabel("字幕背景遮罩")
                    .accessibilityHint("开启后字幕背景更易读")
            }

            Section("识别方式") {
                Picker("相机识别触发方式", selection: $recognitionModeRaw) {
                    ForEach(RecognitionMode.allCases) { mode in
                        Text(mode.title).tag(mode.rawValue)
                    }
                }
                .accessibilityLabel("相机识别触发方式")
                .accessibilityHint("选择二维码或文字识别")
            }

            Section("隐私说明") {
                Text("本应用优先在本地处理识别与字幕，不会上传相机画面。若需联网获取深度资料，将明确提示并征求同意。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("设置")
    }
}
