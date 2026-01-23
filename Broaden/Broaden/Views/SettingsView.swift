import SwiftUI

struct SettingsView: View {
    @AppStorage("captionSize") private var captionSizeRaw = CaptionSize.medium.rawValue
    @AppStorage("captionBackground") private var captionBackgroundEnabled = true
    @AppStorage("recognitionMode") private var recognitionModeRaw = RecognitionMode.qrOnly.rawValue
    
    @EnvironmentObject private var appState: AppState
    @State private var isSyncing = false
    @State private var showSyncSuccess = false

    var body: some View {
        ZStack {
            // 背景图片
            if let bgUrl = Bundle.main.url(forResource: "home-background", withExtension: "png"),
               let bgData = try? Data(contentsOf: bgUrl),
               let bgImage = UIImage(data: bgData) {
                Image(uiImage: bgImage)
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
            }

            Form {
                // CloudKit 同步
                Section {
                    HStack {
                        Image(systemName: "icloud")
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("iCloud 同步")
                            if let lastSync = appState.cloudKitLastSyncDate {
                                Text("上次同步: \(lastSync.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        if isSyncing {
                            ProgressView()
                        } else {
                            Button {
                                Task {
                                    isSyncing = true
                                    await appState.fullCloudKitSync()
                                    isSyncing = false
                                    showSyncSuccess = true
                                    
                                    // 3秒后隐藏成功提示
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                        showSyncSuccess = false
                                    }
                                }
                            } label: {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.title3)
                            }
                            .disabled(!appState.isCloudKitAvailable)
                        }
                    }
                    
                    if showSyncSuccess {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("同步成功")
                                .foregroundStyle(.green)
                        }
                        .transition(.opacity)
                    }
                    
                    if !appState.isCloudKitAvailable {
                        HStack {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                            Text("请登录 iCloud 以启用同步")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("数据同步")
                } footer: {
                    Text("使用 CloudKit 在您的设备间同步文物数据，重装应用后可恢复")
                }
                
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
                
                Section {
                    HStack {
                        Text("已保存文物")
                        Spacer()
                        Text("\(appState.userExhibitCount) 件")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("数据统计")
                }

                Section("隐私说明") {
                    Text("本应用优先在本地处理识别与字幕，不会上传相机画面。若需联网获取深度资料，将明确提示并征求同意。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("设置")
        .animation(.easeInOut, value: showSyncSuccess)
    }
}
