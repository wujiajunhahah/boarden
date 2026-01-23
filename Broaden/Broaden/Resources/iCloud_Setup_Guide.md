# iCloud 配置指南

## 问题 1: 需要在 Xcode 中开启 iCloud capability

### 步骤：

1. **打开 Xcode 项目**
   - 打开 `Broaden.xcodeproj`

2. **选择 Target**
   - 点击左侧项目导航器中的项目名称
   - 选择 "Broaden" target

3. **添加 iCloud Capability**
   - 点击 "Signing & Capabilities" 标签
   - 点击 "+ Capability" 按钮
   - 搜索并双击 "iCloud"

4. **配置 iCloud**
   - 勾选 "CloudKit"
   - 勾选 "iCloud Documents"
   - (可选) 勾选 "Key-Value Store"

5. **配置容器 (如果需要)**
   - 在 "Containers" 下点击 "+"
   - 输入容器标识符：`iCloud.com.yourcompany.Broaden`
   - 或使用 Xcode 自动生成的容器

6. **更新 Entitlements**
   - 确保 `Broaden.entitlements` 文件已创建（已包含在项目中）
   - 如果 Xcode 自动创建了新的 entitlements 文件，确保其内容包含必要的权限

7. **修改 Bundle Identifier**
   - 将 `com.example.Broaden` 改为你自己的 Bundle ID
   - 确保与 Apple Developer 账户中的 App ID 一致

---

## 问题 2: NSUbiquitousKeyValueStore 1MB 限制

### 解决方案：混合存储策略

**优化后的架构：**

| 数据类型 | 存储位置 | 说明 |
|---------|---------|------|
| 最近浏览 IDs | 本地 JSON + iCloud Documents | 大数据使用文件存储 |
| 图片路径映射 | 本地 JSON + iCloud Documents | 无大小限制 |
| 位置记录 | 本地 JSON + iCloud Documents | 无大小限制 |
| 用户展品 | 本地 JSON + iCloud Documents | 无大小限制 |
| 同步令牌 | KVS | 轻量级信号 |

### 如何使用优化版本：

```swift
// 在 BroadenApp.swift 中替换
// @StateObject private var appState = AppState()
// 改为：
@StateObject private var appState = AppState_Optimized()
```

---

## 问题 3: iCloud Documents 同步延迟

### 解决方案：本地优先 + 后台同步

**新架构特点：**

1. **立即写本地** - 所有数据操作先保存到本地 Application Support 目录
2. **延迟同步** - 2 秒内多次修改只同步一次
3. **智能合并** - 本地数据优先，追加云端独有的数据
4. **后台任务** - 应用在前台时每 30 秒检查一次云端更新
5. **生命周期同步** - 进入后台时主动同步，激活时拉取更新

**同步时机：**

| 事件 | 动作 |
|------|------|
| 数据修改 | 延迟 2 秒后同步 |
| 进入后台 | 立即同步到 iCloud |
| 变为活跃 | 从 iCloud 拉取更新 |
| 收到通知 | 合并云端数据 |

---

## 测试清单

- [ ] 在 Xcode 中添加 iCloud capability
- [ ] 修改 Bundle Identifier 为唯一值
- [ ] 在真机上测试（模拟器 iCloud 功能有限）
- [ ] 测试多设备同步（需要两台设备登录同一 Apple ID）
- [ ] 测试离线场景
- [ ] 测试网络恢复后的合并

---

## 故障排查

### iCloud 不同步
1. 检查设备是否登录 iCloud
2. 检查 Settings > Apple ID > iCloud > Photos 是否开启
3. 在 Xcode 中检查 CloudKit Container 配置

### 数据丢失
1. 优先使用本地数据作为主要存储
2. iCloud Documents 作为备份和同步
3. 定期验证本地文件完整性

### 内存警告
1. 限制同步频率
2. 使用分页加载大量数据
3. 清理过期缓存
