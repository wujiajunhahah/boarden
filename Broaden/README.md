# 博听 Broaden

面向听障/聋人博物馆参观的 SwiftUI 原型，提供相机导览、手语视频占位、字幕与易读内容、追问对话、面对面沟通模式与设置。

## 运行方式
1. 用 Xcode 打开 `Broaden/Broaden.xcodeproj`。
2. 选择 iOS 模拟器或真机运行。
3. 首次进入相机导览会请求相机权限。

> 若 AppIcon 缺失，Xcode 可能提示警告，可后续补充图标资源。

## Mock 数据格式
路径：`Broaden/Broaden/Resources/exhibits.json`

字段结构：
```
{
  "id": "EXH-001",
  "title": "展品名",
  "shortIntro": "一句话简介",
  "easyText": "易读版",
  "detailText": "详细信息",
  "glossary": [{"term": "术语", "def": "解释"}],
  "media": {
    "signVideoFilename": "sign_demo.mp4",
    "captionsVttOrSrtFilename": "captions_demo.srt"
  },
  "references": [{"refId": "REF-01", "snippet": "引用片段"}]
}
```

## Mock 追问接口
文件：`Broaden/Broaden/Services/AskService.swift`

当前使用 `MockAskService`，根据问题关键词返回 `AskResponse`。后续可替换为真实 HTTP API：
- 将 `AskServicing` 实现替换为 `RemoteAskService`
- 使用 `URLSession` + `async/await`
- 将 `AnswerCache` 作为离线缓存层

## 可达设计说明
- 使用系统字体样式与 Dynamic Type，避免固定字号。
- 支持深色模式与足够对比度；字幕背景遮罩可在设置中开关。
- 关键按钮添加 `accessibilityLabel` 和 `accessibilityHint`。
- 关键交互触发轻量触觉反馈，并尊重“减少动态效果”。
- 字幕显示使用系统风格材质，并可调整字号。

## 模块结构
- Models: 数据模型
- Services: 本地数据、识别、缓存、Mock API
- ViewModels: MVVM 业务逻辑
- Views: 页面与组件
- Resources: Mock JSON、字幕文件、Assets
