import SwiftUI

struct SettingsView: View {
    @AppStorage("captionSize") private var captionSizeRaw = CaptionSize.medium.rawValue
    @AppStorage("captionBackground") private var captionBackgroundEnabled = true
    @AppStorage("recognitionMode") private var recognitionModeRaw = RecognitionMode.qrOnly.rawValue
    @AppStorage("darkModeEnabled") private var darkModeEnabled = false
    
    @EnvironmentObject private var appState: AppState
    @State private var isSyncing = false
    @State private var showSyncSuccess = false
    @State private var userName = "平花选手"
    @State private var isEditingName = false
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        ZStack {
            // 背景
            backgroundView
            
            ScrollView {
                VStack(spacing: 20) {
                    // 用户资料卡片
                    profileCard
                    
                    // 偏好设置
                    Text("偏好设置")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.primaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                    
                    preferencesCard
                    
                    // 其他
                    otherCard
                    
                    // 数据同步
                    syncCard
                    
                    Spacer(minLength: 100)
                }
                .padding(.top, 20)
            }
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .onTapGesture {
            // 点击空白区域隐藏键盘
            hideKeyboard()
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") {
                    isTextFieldFocused = false
                    isEditingName = false
                }
            }
        }
    }
    
    private func hideKeyboard() {
        isTextFieldFocused = false
        isEditingName = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
    
    // MARK: - Background View
    
    private var backgroundView: some View {
        ZStack {
            Color(red: 0.98, green: 0.97, blue: 0.95)
                .ignoresSafeArea()
            
            // 装饰性形状
            GeometryReader { geometry in
                // 左上蓝色形状
                SettingsShape1()
                    .fill(Color(red: 0.75, green: 0.82, blue: 0.92).opacity(0.6))
                    .frame(width: 150, height: 120)
                    .offset(x: -30, y: 0)
                
                // 右上粉色形状
                SettingsShape2()
                    .fill(Color(red: 0.95, green: 0.75, blue: 0.80).opacity(0.5))
                    .frame(width: 80, height: 80)
                    .offset(x: geometry.size.width - 60, y: geometry.size.height * 0.35)
                
                // 左侧黄色形状
                SettingsShape3()
                    .fill(Color(red: 0.98, green: 0.85, blue: 0.45).opacity(0.6))
                    .frame(width: 100, height: 100)
                    .offset(x: -20, y: geometry.size.height * 0.45)
                
                // 右下绿色形状
                SettingsShape4()
                    .fill(Color(red: 0.70, green: 0.78, blue: 0.55).opacity(0.5))
                    .frame(width: 120, height: 140)
                    .offset(x: geometry.size.width - 80, y: geometry.size.height * 0.7)
            }
        }
    }
    
    // MARK: - Profile Card
    
    private var profileCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 头像
            Image("app-logo")
                .resizable()
                .scaledToFit()
                .frame(width: 60, height: 60)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.white, lineWidth: 2))
                .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
            
            // 用户名
            HStack(spacing: 8) {
                if isEditingName {
                    TextField("用户名", text: $userName)
                        .font(.system(size: 20, weight: .semibold))
                        .textFieldStyle(.plain)
                        .focused($isTextFieldFocused)
                        .onSubmit {
                            isEditingName = false
                            isTextFieldFocused = false
                        }
                        .submitLabel(.done)
                } else {
                    Text(userName)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color.primaryText)
                }
                
                Button {
                    if isEditingName {
                        isEditingName = false
                        isTextFieldFocused = false
                    } else {
                        isEditingName = true
                        isTextFieldFocused = true
                    }
                } label: {
                    Image(systemName: isEditingName ? "checkmark" : "pencil")
                        .font(.system(size: 14))
                        .foregroundStyle(isEditingName ? .green : Color.secondaryText)
                }
            }
            
            Spacer(minLength: 40)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 180)
        .modifier(SettingsCardModifier(color: Color(red: 1.0, green: 0.95, blue: 0.75)))
        .padding(.horizontal, 20)
    }
    
    // MARK: - Preferences Card
    
    private var preferencesCard: some View {
        VStack(spacing: 0) {
            SettingsRow(icon: "person.circle", title: "账号与安全")
            Divider().padding(.leading, 50)
            
            SettingsRow(icon: "globe", title: "语言")
            Divider().padding(.leading, 50)
            
            SettingsRow(icon: "location", title: "位置信息")
            Divider().padding(.leading, 50)
            
            SettingsRowWithStringPicker(
                icon: "textformat.size",
                title: "显示设置",
                selection: $captionSizeRaw,
                options: CaptionSize.allCases.map { ($0.rawValue, $0.title) }
            )
            Divider().padding(.leading, 50)
            
            SettingsRowWithToggle(icon: "moon", title: "深色模式", isOn: $darkModeEnabled)
        }
        .modifier(SettingsCardModifier())
        .padding(.horizontal, 20)
    }
    
    // MARK: - Other Card
    
    private var otherCard: some View {
        VStack(spacing: 0) {
            SettingsRow(icon: "questionmark.circle", title: "问题反馈")
            Divider().padding(.leading, 50)
            
            SettingsRow(icon: "person.2", title: "开发团队")
        }
        .modifier(SettingsCardModifier())
        .padding(.horizontal, 20)
    }
    
    // MARK: - Sync Card
    
    private var syncCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "icloud")
                    .font(.system(size: 18))
                    .foregroundStyle(.blue)
                    .frame(width: 28)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("iCloud 同步")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.primaryText)
                    
                    if let lastSync = appState.cloudKitLastSyncDate {
                        Text("上次: \(lastSync.formatted(date: .abbreviated, time: .shortened))")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.secondaryText)
                    }
                }
                
                Spacer()
                
                if isSyncing {
                    ProgressView()
                        .scaleEffect(0.8)
                } else if showSyncSuccess {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Button {
                        Task {
                            isSyncing = true
                            await appState.fullCloudKitSync()
                            isSyncing = false
                            showSyncSuccess = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                showSyncSuccess = false
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 16))
                            .foregroundStyle(.blue)
                    }
                    .disabled(!appState.isCloudKitAvailable)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            
            if !appState.isCloudKitAvailable {
                Divider().padding(.leading, 50)
                
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 14))
                        .foregroundStyle(.orange)
                        .frame(width: 28)
                    
                    Text("请登录 iCloud 以启用同步")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.secondaryText)
                    
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            
            Divider().padding(.leading, 50)
            
            HStack(spacing: 12) {
                Image(systemName: "archivebox")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.secondaryText)
                    .frame(width: 28)
                
                Text("已保存文物")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.primaryText)
                
                Spacer()
                
                Text("\(appState.userExhibitCount) 件")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.secondaryText)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .modifier(SettingsCardModifier())
        .padding(.horizontal, 20)
        .animation(.easeInOut, value: showSyncSuccess)
    }
}

// MARK: - Settings Row Components

private struct SettingsRow: View {
    let icon: String
    let title: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(Color.secondaryText)
                .frame(width: 28)
            
            Text(title)
                .font(.system(size: 16))
                .foregroundStyle(Color.primaryText)
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 14))
                .foregroundStyle(Color.secondaryText.opacity(0.5))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}

private struct SettingsRowWithToggle: View {
    let icon: String
    let title: String
    @Binding var isOn: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(Color.secondaryText)
                .frame(width: 28)
            
            Text(title)
                .font(.system(size: 16))
                .foregroundStyle(Color.primaryText)
            
            Spacer()
            
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .scaleEffect(0.9)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

private struct SettingsRowWithStringPicker: View {
    let icon: String
    let title: String
    @Binding var selection: String
    let options: [(String, String)]
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(Color.secondaryText)
                .frame(width: 28)
            
            Text(title)
                .font(.system(size: 16))
                .foregroundStyle(Color.primaryText)
            
            Spacer()
            
            Menu {
                ForEach(options, id: \.0) { option in
                    Button(option.1) {
                        selection = option.0
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(options.first { $0.0 == selection }?.1 ?? "")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.secondaryText)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.secondaryText.opacity(0.5))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

// MARK: - Settings Card Modifier (iOS 26 Liquid Glass)

private struct SettingsCardModifier: ViewModifier {
    var color: Color = .white.opacity(0.85)
    
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(in: .rect(cornerRadius: 20))
        } else {
            content
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(color)
                        .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 4)
                )
        }
    }
}

// MARK: - Decorative Shapes

private struct SettingsShape1: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addEllipse(in: rect)
        return path
    }
}

private struct SettingsShape2: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: 0))
        path.addQuadCurve(
            to: CGPoint(x: rect.width, y: rect.midY),
            control: CGPoint(x: rect.width, y: 0)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.midX, y: rect.height),
            control: CGPoint(x: rect.width, y: rect.height)
        )
        path.addQuadCurve(
            to: CGPoint(x: 0, y: rect.midY),
            control: CGPoint(x: 0, y: rect.height)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.midX, y: 0),
            control: CGPoint(x: 0, y: 0)
        )
        path.closeSubpath()
        return path
    }
}

private struct SettingsShape3: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.5, y: 0))
        path.addCurve(
            to: CGPoint(x: rect.width, y: rect.height * 0.6),
            control1: CGPoint(x: rect.width * 0.9, y: 0),
            control2: CGPoint(x: rect.width, y: rect.height * 0.3)
        )
        path.addCurve(
            to: CGPoint(x: rect.width * 0.3, y: rect.height),
            control1: CGPoint(x: rect.width, y: rect.height * 0.9),
            control2: CGPoint(x: rect.width * 0.6, y: rect.height)
        )
        path.addCurve(
            to: CGPoint(x: 0, y: rect.height * 0.4),
            control1: CGPoint(x: 0, y: rect.height),
            control2: CGPoint(x: 0, y: rect.height * 0.7)
        )
        path.addCurve(
            to: CGPoint(x: rect.width * 0.5, y: 0),
            control1: CGPoint(x: 0, y: rect.height * 0.1),
            control2: CGPoint(x: rect.width * 0.2, y: 0)
        )
        path.closeSubpath()
        return path
    }
}

private struct SettingsShape4: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.3, y: 0))
        path.addCurve(
            to: CGPoint(x: rect.width, y: rect.height * 0.4),
            control1: CGPoint(x: rect.width * 0.7, y: 0),
            control2: CGPoint(x: rect.width, y: rect.height * 0.1)
        )
        path.addCurve(
            to: CGPoint(x: rect.width * 0.6, y: rect.height),
            control1: CGPoint(x: rect.width, y: rect.height * 0.8),
            control2: CGPoint(x: rect.width * 0.9, y: rect.height)
        )
        path.addCurve(
            to: CGPoint(x: 0, y: rect.height * 0.5),
            control1: CGPoint(x: rect.width * 0.2, y: rect.height),
            control2: CGPoint(x: 0, y: rect.height * 0.8)
        )
        path.addCurve(
            to: CGPoint(x: rect.width * 0.3, y: 0),
            control1: CGPoint(x: 0, y: rect.height * 0.2),
            control2: CGPoint(x: rect.width * 0.1, y: 0)
        )
        path.closeSubpath()
        return path
    }
}
