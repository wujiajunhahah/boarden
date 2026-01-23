import Foundation
import CloudKit
import Combine

/// CloudKit 同步服务 - 使用私有数据库同步用户数据
@MainActor
final class CloudKitSyncService: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published private(set) var isSyncing = false
    @Published private(set) var lastSyncDate: Date?
    @Published private(set) var syncError: Error?
    @Published private(set) var isCloudAvailable = false
    
    // MARK: - CloudKit Configuration
    
    private let container: CKContainer
    private let privateDatabase: CKDatabase
    private let customZoneID: CKRecordZone.ID
    
    // Record Types
    private let exhibitRecordType = "Exhibit"
    private let photoRecordType = "ArtifactPhoto"
    
    // UserDefaults Keys
    private let serverChangeTokenKey = "cloudkit_server_change_token"
    private let lastSyncKey = "cloudkit_last_sync"
    
    // MARK: - Initialization
    
    init() {
        // 使用默认容器（需要在 Xcode 中配置 iCloud 容器）
        self.container = CKContainer.default()
        self.privateDatabase = container.privateCloudDatabase
        self.customZoneID = CKRecordZone.ID(zoneName: "BroadenZone", ownerName: CKCurrentUserDefaultName)
        
        // 加载上次同步时间
        if let date = UserDefaults.standard.object(forKey: lastSyncKey) as? Date {
            lastSyncDate = date
        }
        
        // 检查 iCloud 可用性
        Task {
            await checkCloudAvailability()
        }
    }
    
    // MARK: - Cloud Availability
    
    /// 检查 iCloud 是否可用
    func checkCloudAvailability() async {
        do {
            let status = try await container.accountStatus()
            isCloudAvailable = (status == .available)
            
            if isCloudAvailable {
                // 确保自定义区域存在
                await createCustomZoneIfNeeded()
            }
            
            print("[CloudKit] 账户状态: \(status.rawValue), 可用: \(isCloudAvailable)")
        } catch {
            isCloudAvailable = false
            print("[CloudKit] 检查账户状态失败: \(error)")
        }
    }
    
    /// 创建自定义记录区域（如果不存在）
    private func createCustomZoneIfNeeded() async {
        let zone = CKRecordZone(zoneID: customZoneID)
        
        do {
            _ = try await privateDatabase.save(zone)
            print("[CloudKit] 自定义区域已创建或已存在")
        } catch let error as CKError where error.code == .serverRecordChanged {
            // 区域已存在，忽略
            print("[CloudKit] 自定义区域已存在")
        } catch {
            print("[CloudKit] 创建自定义区域失败: \(error)")
        }
    }
    
    // MARK: - Sync Operations
    
    /// 同步所有数据
    func syncAll(exhibits: [Exhibit], photoURLs: [String: URL]) async {
        guard isCloudAvailable else {
            print("[CloudKit] iCloud 不可用，跳过同步")
            return
        }
        
        isSyncing = true
        syncError = nil
        
        do {
            // 1. 上传本地数据到 CloudKit
            try await uploadExhibits(exhibits)
            try await uploadPhotos(photoURLs)
            
            // 2. 更新同步时间
            lastSyncDate = Date()
            UserDefaults.standard.set(lastSyncDate, forKey: lastSyncKey)
            
            print("[CloudKit] 同步完成")
        } catch {
            syncError = error
            print("[CloudKit] 同步失败: \(error)")
        }
        
        isSyncing = false
    }
    
    /// 从 CloudKit 拉取数据
    func fetchFromCloud() async -> (exhibits: [Exhibit], photoURLs: [String: URL])? {
        guard isCloudAvailable else {
            print("[CloudKit] iCloud 不可用，跳过拉取")
            return nil
        }
        
        isSyncing = true
        defer { isSyncing = false }
        
        do {
            let exhibits = try await fetchExhibits()
            let photoURLs = try await fetchPhotos()
            
            print("[CloudKit] 拉取完成: \(exhibits.count) 个展品, \(photoURLs.count) 张图片")
            return (exhibits, photoURLs)
        } catch {
            syncError = error
            print("[CloudKit] 拉取失败: \(error)")
            return nil
        }
    }
    
    // MARK: - Exhibit Sync
    
    /// 上传展品到 CloudKit
    private func uploadExhibits(_ exhibits: [Exhibit]) async throws {
        for exhibit in exhibits {
            let recordID = CKRecord.ID(recordName: exhibit.id, zoneID: customZoneID)
            let record = CKRecord(recordType: exhibitRecordType, recordID: recordID)
            
            // 设置记录字段
            record["id"] = exhibit.id
            record["title"] = exhibit.title
            record["shortIntro"] = exhibit.shortIntro
            record["detailText"] = exhibit.detailText
            record["easyText"] = exhibit.easyText
            
            // 编码 glossary
            if let glossaryData = try? JSONEncoder().encode(exhibit.glossary) {
                record["glossary"] = String(data: glossaryData, encoding: .utf8)
            }
            
            // 编码 media
            if let mediaData = try? JSONEncoder().encode(exhibit.media) {
                record["media"] = String(data: mediaData, encoding: .utf8)
            }
            
            // 编码 references
            if let refsData = try? JSONEncoder().encode(exhibit.references) {
                record["references"] = String(data: refsData, encoding: .utf8)
            }
            
            do {
                _ = try await privateDatabase.save(record)
                print("[CloudKit] 已上传展品: \(exhibit.title)")
            } catch let error as CKError where error.code == .serverRecordChanged {
                // 处理冲突：使用服务器版本的 recordChangeTag 重试
                if let serverRecord = error.userInfo[CKRecordChangedErrorServerRecordKey] as? CKRecord {
                    serverRecord["title"] = exhibit.title
                    serverRecord["shortIntro"] = exhibit.shortIntro
                    serverRecord["detailText"] = exhibit.detailText
                    serverRecord["easyText"] = exhibit.easyText
                    _ = try await privateDatabase.save(serverRecord)
                    print("[CloudKit] 解决冲突并上传展品: \(exhibit.title)")
                }
            }
        }
    }
    
    /// 从 CloudKit 拉取展品
    private func fetchExhibits() async throws -> [Exhibit] {
        let query = CKQuery(recordType: exhibitRecordType, predicate: NSPredicate(value: true))
        
        var exhibits: [Exhibit] = []
        var cursor: CKQueryOperation.Cursor?
        
        repeat {
            let result: (matchResults: [(CKRecord.ID, Result<CKRecord, Error>)], queryCursor: CKQueryOperation.Cursor?)
            
            if let cursor = cursor {
                result = try await privateDatabase.records(continuingMatchFrom: cursor)
            } else {
                result = try await privateDatabase.records(matching: query, inZoneWith: customZoneID)
            }
            
            for (_, recordResult) in result.matchResults {
                if case .success(let record) = recordResult {
                    if let exhibit = exhibitFromRecord(record) {
                        exhibits.append(exhibit)
                    }
                }
            }
            
            cursor = result.queryCursor
        } while cursor != nil
        
        return exhibits
    }
    
    /// 将 CKRecord 转换为 Exhibit
    private func exhibitFromRecord(_ record: CKRecord) -> Exhibit? {
        guard let id = record["id"] as? String,
              let title = record["title"] as? String else {
            return nil
        }
        
        var glossary: [GlossaryItem] = []
        if let glossaryString = record["glossary"] as? String,
           let glossaryData = glossaryString.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([GlossaryItem].self, from: glossaryData) {
            glossary = decoded
        }
        
        var media = ExhibitMedia(signVideoFilename: "", captionsVttOrSrtFilename: "")
        if let mediaString = record["media"] as? String,
           let mediaData = mediaString.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(ExhibitMedia.self, from: mediaData) {
            media = decoded
        }
        
        var references: [ReferenceSnippet] = []
        if let refsString = record["references"] as? String,
           let refsData = refsString.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([ReferenceSnippet].self, from: refsData) {
            references = decoded
        }
        
        return Exhibit(
            id: id,
            title: title,
            shortIntro: record["shortIntro"] as? String ?? "",
            easyText: record["easyText"] as? String ?? "",
            detailText: record["detailText"] as? String ?? "",
            glossary: glossary,
            media: media,
            references: references
        )
    }
    
    // MARK: - Photo Sync
    
    /// 上传图片到 CloudKit
    private func uploadPhotos(_ photoURLs: [String: URL]) async throws {
        for (exhibitId, localURL) in photoURLs {
            guard FileManager.default.fileExists(atPath: localURL.path) else { continue }
            
            let recordID = CKRecord.ID(recordName: "photo_\(exhibitId)", zoneID: customZoneID)
            let record = CKRecord(recordType: photoRecordType, recordID: recordID)
            
            // 创建 CKAsset
            let asset = CKAsset(fileURL: localURL)
            record["exhibitId"] = exhibitId
            record["photo"] = asset
            record["filename"] = localURL.lastPathComponent
            
            do {
                _ = try await privateDatabase.save(record)
                print("[CloudKit] 已上传图片: \(exhibitId)")
            } catch let error as CKError where error.code == .serverRecordChanged {
                // 处理冲突
                if let serverRecord = error.userInfo[CKRecordChangedErrorServerRecordKey] as? CKRecord {
                    serverRecord["photo"] = asset
                    serverRecord["filename"] = localURL.lastPathComponent
                    _ = try await privateDatabase.save(serverRecord)
                }
            }
        }
    }
    
    /// 从 CloudKit 拉取图片
    private func fetchPhotos() async throws -> [String: URL] {
        let query = CKQuery(recordType: photoRecordType, predicate: NSPredicate(value: true))
        
        var photoURLs: [String: URL] = [:]
        
        let result = try await privateDatabase.records(matching: query, inZoneWith: customZoneID)
        
        for (_, recordResult) in result.matchResults {
            if case .success(let record) = recordResult {
                guard let exhibitId = record["exhibitId"] as? String,
                      let asset = record["photo"] as? CKAsset,
                      let assetURL = asset.fileURL else { continue }
                
                // 将图片复制到本地 Documents 目录
                let filename = record["filename"] as? String ?? "artifact_\(exhibitId).jpg"
                let localURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                    .appendingPathComponent(filename)
                
                do {
                    if FileManager.default.fileExists(atPath: localURL.path) {
                        try FileManager.default.removeItem(at: localURL)
                    }
                    try FileManager.default.copyItem(at: assetURL, to: localURL)
                    photoURLs[exhibitId] = localURL
                    print("[CloudKit] 已下载图片: \(exhibitId)")
                } catch {
                    print("[CloudKit] 复制图片失败: \(error)")
                }
            }
        }
        
        return photoURLs
    }
    
    // MARK: - Delete
    
    /// 从 CloudKit 删除展品
    func deleteExhibit(_ exhibitId: String) async {
        guard isCloudAvailable else { return }
        
        let exhibitRecordID = CKRecord.ID(recordName: exhibitId, zoneID: customZoneID)
        let photoRecordID = CKRecord.ID(recordName: "photo_\(exhibitId)", zoneID: customZoneID)
        
        do {
            try await privateDatabase.deleteRecord(withID: exhibitRecordID)
            try await privateDatabase.deleteRecord(withID: photoRecordID)
            print("[CloudKit] 已删除展品: \(exhibitId)")
        } catch {
            print("[CloudKit] 删除失败: \(error)")
        }
    }
    
    // MARK: - Subscriptions (Push Notifications)
    
    /// 订阅数据变更（需要配置推送通知）
    func subscribeToChanges() async {
        guard isCloudAvailable else { return }
        
        let subscriptionID = "exhibit-changes"
        
        // 检查是否已订阅
        do {
            _ = try await privateDatabase.subscription(for: subscriptionID)
            print("[CloudKit] 已存在订阅")
            return
        } catch {
            // 订阅不存在，创建新订阅
        }
        
        let subscription = CKDatabaseSubscription(subscriptionID: subscriptionID)
        
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true // 静默推送
        subscription.notificationInfo = notificationInfo
        
        do {
            _ = try await privateDatabase.save(subscription)
            print("[CloudKit] 订阅创建成功")
        } catch {
            print("[CloudKit] 创建订阅失败: \(error)")
        }
    }
}

// MARK: - CloudKit Error Extension

extension CKError {
    var isRetryable: Bool {
        switch code {
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited, .zoneBusy:
            return true
        default:
            return false
        }
    }
    
    var retryAfterSeconds: Double? {
        userInfo[CKErrorRetryAfterKey] as? Double
    }
}
