import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var exhibits: [Exhibit] = []
    @Published var recentExhibitIds: [String] = []
    @Published private(set) var artifactPhotoURLs: [String: URL] = [:]
    @Published private(set) var exhibitLocations: [String: LocationRecord] = [:]
    
    /// 待跳转的展品详情（用于导航）
    @Published var pendingExhibitForDetail: Exhibit?
    
    /// 用户添加的展品（持久化存储）
    private var userExhibits: [Exhibit] = []
    
    /// iCloud Key-Value Store
    private let iCloudStore = NSUbiquitousKeyValueStore.default

    private let exhibitService: ExhibitProviding
    private let recentsKey = "recentExhibitIds"
    private let artifactKey = "artifactPhotoURLs"
    private let locationKey = "exhibitLocations"
    private let userExhibitsKey = "userExhibits"
    private let locationService = LocationService()
    
    /// 本地存储路径（作为备份）
    private var localUserExhibitsURL: URL {
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return folder.appendingPathComponent("user_exhibits.json")
    }
    
    /// iCloud Documents 目录
    private var iCloudDocumentsURL: URL? {
        FileManager.default.url(forUbiquityContainerIdentifier: nil)?.appendingPathComponent("Documents")
    }
    
    /// iCloud 用户展品存储路径
    private var iCloudUserExhibitsURL: URL? {
        iCloudDocumentsURL?.appendingPathComponent("user_exhibits.json")
    }
    
    /// iCloud 图片存储目录
    private var iCloudPhotosURL: URL? {
        iCloudDocumentsURL?.appendingPathComponent("photos")
    }

    init(exhibitService: ExhibitProviding = ExhibitService()) {
        self.exhibitService = exhibitService
        
        // 确保 iCloud 目录存在
        setupiCloudDirectories()
        
        // 监听 iCloud 同步变化
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: iCloudStore,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.loadFromiCloud()
            }
        }
        
        // 启动 iCloud 同步
        iCloudStore.synchronize()
        
        // 加载数据（优先从 iCloud）
        loadFromiCloud()
        loadUserExhibits()
    }
    
    private func setupiCloudDirectories() {
        // 创建 iCloud Documents 目录
        if let docsURL = iCloudDocumentsURL {
            try? FileManager.default.createDirectory(at: docsURL, withIntermediateDirectories: true)
        }
        // 创建 iCloud photos 目录
        if let photosURL = iCloudPhotosURL {
            try? FileManager.default.createDirectory(at: photosURL, withIntermediateDirectories: true)
        }
    }
    
    // MARK: - iCloud 数据加载
    
    private func loadFromiCloud() {
        // 加载最近浏览 - 合并 iCloud 和本地数据，防止同步延迟导致数据丢失
        var mergedRecents: [String] = []
        
        // 1. 先加载本地数据
        if let localData = UserDefaults.standard.data(forKey: recentsKey),
           let localIds = try? JSONDecoder().decode([String].self, from: localData) {
            mergedRecents = localIds
            print("[AppState] 从本地加载了 \(localIds.count) 个最近浏览")
        }
        
        // 2. 加载 iCloud 数据并合并
        if let iCloudData = iCloudStore.data(forKey: recentsKey),
           let iCloudIds = try? JSONDecoder().decode([String].self, from: iCloudData) {
            print("[AppState] 从 iCloud 加载了 \(iCloudIds.count) 个最近浏览")
            
            // 合并：保留本地数据的顺序，追加 iCloud 中有但本地没有的记录
            for id in iCloudIds {
                if !mergedRecents.contains(id) {
                    mergedRecents.append(id)
                }
            }
        }
        
        // 3. 限制最多 10 条
        if mergedRecents.count > 10 {
            mergedRecents = Array(mergedRecents.prefix(10))
        }
        
        recentExhibitIds = mergedRecents
        print("[AppState] 合并后共 \(recentExhibitIds.count) 个最近浏览")
        
        // 加载图片路径映射
        if let data = iCloudStore.data(forKey: artifactKey),
           let entries = try? JSONDecoder().decode([String: String].self, from: data) {
            rebuildArtifactURLs(from: entries)
            print("[AppState] 从 iCloud 加载了 \(entries.count) 个图片映射")
        } else {
            loadArtifactsFromLocal()
        }
        
        // 加载位置信息
        if let data = iCloudStore.data(forKey: locationKey),
           let entries = try? JSONDecoder().decode([String: LocationRecord].self, from: data) {
            exhibitLocations = entries
            print("[AppState] 从 iCloud 加载了 \(entries.count) 个位置记录")
        } else {
            loadLocationsFromLocal()
        }
    }
    
    /// 重建图片 URL（考虑 iCloud 和本地路径）
    private func rebuildArtifactURLs(from entries: [String: String]) {
        var urls: [String: URL] = [:]
        for (exhibitId, filename) in entries {
            // 优先检查 iCloud 路径
            if let iCloudURL = iCloudPhotosURL?.appendingPathComponent(filename),
               FileManager.default.fileExists(atPath: iCloudURL.path) {
                urls[exhibitId] = iCloudURL
            } else {
                // 回退到本地 Documents 路径
                let localURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                    .appendingPathComponent(filename)
                if FileManager.default.fileExists(atPath: localURL.path) {
                    urls[exhibitId] = localURL
                }
            }
        }
        artifactPhotoURLs = urls
    }

    func loadExhibits() async {
        do {
            // 加载预置展品
            let bundleExhibits = try await exhibitService.loadExhibits()
            // 合并用户展品（用户展品优先显示在前面，且不会被预置展品覆盖）
            var merged: [Exhibit] = userExhibits
            for exhibit in bundleExhibits {
                if !merged.contains(where: { $0.id == exhibit.id }) {
                    merged.append(exhibit)
                }
            }
            exhibits = merged
        } catch {
            // 即使加载预置展品失败，仍显示用户展品
            exhibits = userExhibits
        }
    }

    func exhibit(by id: String) -> Exhibit? {
        exhibits.first { $0.id == id }
    }

    func upsertExhibit(_ exhibit: Exhibit) {
        // 更新 exhibits 数组
        if let index = exhibits.firstIndex(where: { $0.id == exhibit.id }) {
            exhibits[index] = exhibit
        } else {
            exhibits.insert(exhibit, at: 0)
        }
        
        // 同步更新用户展品并持久化
        if let index = userExhibits.firstIndex(where: { $0.id == exhibit.id }) {
            userExhibits[index] = exhibit
        } else {
            userExhibits.insert(exhibit, at: 0)
        }
        saveUserExhibits()
    }

    func addRecent(exhibit: Exhibit) {
        recentExhibitIds.removeAll { $0 == exhibit.id }
        recentExhibitIds.insert(exhibit.id, at: 0)
        if recentExhibitIds.count > 10 {
            recentExhibitIds = Array(recentExhibitIds.prefix(10))
        }
        saveRecents()
    }

    private func loadRecentsFromLocal() {
        if let data = UserDefaults.standard.data(forKey: recentsKey),
           let ids = try? JSONDecoder().decode([String].self, from: data) {
            recentExhibitIds = ids
        }
    }

    private func saveRecents() {
        if let data = try? JSONEncoder().encode(recentExhibitIds) {
            // 保存到 iCloud
            iCloudStore.set(data, forKey: recentsKey)
            iCloudStore.synchronize()
            // 同时保存到本地作为备份
            UserDefaults.standard.set(data, forKey: recentsKey)
        }
    }

    func saveArtifactPhoto(data: Data, exhibitId: String) -> URL? {
        let filename = "artifact_\(exhibitId)_\(UUID().uuidString).jpg"
        
        // 优先保存到 iCloud
        var savedURL: URL?
        if let iCloudURL = iCloudPhotosURL?.appendingPathComponent(filename) {
            do {
                try data.write(to: iCloudURL)
                savedURL = iCloudURL
                print("[AppState] 图片已保存到 iCloud: \(filename)")
            } catch {
                print("[AppState] 保存到 iCloud 失败: \(error)")
            }
        }
        
        // 如果 iCloud 失败，保存到本地
        if savedURL == nil {
            let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            if let localURL = folder?.appendingPathComponent(filename) {
                do {
                    try data.write(to: localURL)
                    savedURL = localURL
                    print("[AppState] 图片已保存到本地: \(filename)")
                } catch {
                    print("[AppState] 保存到本地也失败: \(error)")
                    return nil
                }
            }
        }
        
        if let url = savedURL {
            artifactPhotoURLs[exhibitId] = url
            saveArtifacts(filename: filename, exhibitId: exhibitId)
            return url
        }
        
        return nil
    }

    func artifactPhotoURL(for exhibitId: String) -> URL? {
        artifactPhotoURLs[exhibitId]
    }

    func captureLocation(for exhibitId: String) async {
        if let record = await locationService.fetchCurrentLocation() {
            exhibitLocations[exhibitId] = record
            saveLocations()
        }
    }

    func locationRecord(for exhibitId: String) -> LocationRecord? {
        exhibitLocations[exhibitId]
    }

    private func loadArtifactsFromLocal() {
        if let data = UserDefaults.standard.data(forKey: artifactKey),
           let entries = try? JSONDecoder().decode([String: String].self, from: data) {
            rebuildArtifactURLs(from: entries)
        }
    }

    private func saveArtifacts(filename: String, exhibitId: String) {
        // 构建文件名映射（只存文件名，不存完整路径）
        var entries: [String: String] = [:]
        for (id, url) in artifactPhotoURLs {
            entries[id] = url.lastPathComponent
        }
        entries[exhibitId] = filename
        
        if let data = try? JSONEncoder().encode(entries) {
            // 保存到 iCloud
            iCloudStore.set(data, forKey: artifactKey)
            iCloudStore.synchronize()
            // 同时保存到本地
            UserDefaults.standard.set(data, forKey: artifactKey)
        }
    }

    private func loadLocationsFromLocal() {
        if let data = UserDefaults.standard.data(forKey: locationKey),
           let entries = try? JSONDecoder().decode([String: LocationRecord].self, from: data) {
            exhibitLocations = entries
        }
    }

    private func saveLocations() {
        if let data = try? JSONEncoder().encode(exhibitLocations) {
            // 保存到 iCloud
            iCloudStore.set(data, forKey: locationKey)
            iCloudStore.synchronize()
            // 同时保存到本地
            UserDefaults.standard.set(data, forKey: locationKey)
        }
    }
    
    // MARK: - 用户展品持久化
    
    /// 加载用户添加的展品（优先从 iCloud）
    private func loadUserExhibits() {
        // 优先从 iCloud 加载
        if let iCloudURL = iCloudUserExhibitsURL,
           FileManager.default.fileExists(atPath: iCloudURL.path) {
            do {
                let data = try Data(contentsOf: iCloudURL)
                userExhibits = try JSONDecoder().decode([Exhibit].self, from: data)
                print("[AppState] 从 iCloud 加载了 \(userExhibits.count) 个用户展品")
                return
            } catch {
                print("[AppState] 从 iCloud 加载用户展品失败: \(error)")
            }
        }
        
        // 回退到本地
        guard FileManager.default.fileExists(atPath: localUserExhibitsURL.path) else {
            print("[AppState] 用户展品文件不存在，跳过加载")
            return
        }
        
        do {
            let data = try Data(contentsOf: localUserExhibitsURL)
            userExhibits = try JSONDecoder().decode([Exhibit].self, from: data)
            print("[AppState] 从本地加载了 \(userExhibits.count) 个用户展品")
            
            // 同步到 iCloud
            saveUserExhibits()
        } catch {
            print("[AppState] 加载用户展品失败: \(error)")
            userExhibits = []
        }
    }
    
    /// 保存用户添加的展品（同时保存到 iCloud 和本地）
    private func saveUserExhibits() {
        do {
            let data = try JSONEncoder().encode(userExhibits)
            
            // 保存到 iCloud
            if let iCloudURL = iCloudUserExhibitsURL {
                try data.write(to: iCloudURL)
                print("[AppState] 已保存 \(userExhibits.count) 个用户展品到 iCloud")
            }
            
            // 同时保存到本地作为备份
            try data.write(to: localUserExhibitsURL)
        } catch {
            print("[AppState] 保存用户展品失败: \(error)")
        }
    }
    
    /// 删除用户展品
    func deleteUserExhibit(_ exhibitId: String) {
        exhibits.removeAll { $0.id == exhibitId }
        userExhibits.removeAll { $0.id == exhibitId }
        recentExhibitIds.removeAll { $0 == exhibitId }
        
        // 删除图片文件
        if let photoURL = artifactPhotoURLs[exhibitId] {
            try? FileManager.default.removeItem(at: photoURL)
        }
        artifactPhotoURLs.removeValue(forKey: exhibitId)
        exhibitLocations.removeValue(forKey: exhibitId)
        
        saveUserExhibits()
        saveRecents()
        saveLocations()
        
        print("[AppState] 已删除展品: \(exhibitId)")
    }
    
    /// 获取用户展品数量
    var userExhibitCount: Int {
        userExhibits.count
    }
    
    /// 强制同步 iCloud
    func forceiCloudSync() {
        iCloudStore.synchronize()
        saveUserExhibits()
        saveRecents()
        saveLocations()
        print("[AppState] 已强制同步到 iCloud")
    }
    
    // MARK: - CloudKit Sync
    
    /// CloudKit 同步服务
    private var _cloudKitService: CloudKitSyncService?
    
    private var cloudKitService: CloudKitSyncService {
        if _cloudKitService == nil {
            _cloudKitService = CloudKitSyncService()
        }
        return _cloudKitService!
    }
    
    /// 是否正在同步 CloudKit
    var isCloudKitSyncing: Bool {
        _cloudKitService?.isSyncing ?? false
    }
    
    /// CloudKit 是否可用
    var isCloudKitAvailable: Bool {
        _cloudKitService?.isCloudAvailable ?? false
    }
    
    /// CloudKit 最后同步时间
    var cloudKitLastSyncDate: Date? {
        _cloudKitService?.lastSyncDate
    }
    
    /// 同步到 CloudKit
    func syncToCloudKit() async {
        await cloudKitService.syncAll(exhibits: userExhibits, photoURLs: artifactPhotoURLs)
    }
    
    /// 从 CloudKit 拉取数据
    func pullFromCloudKit() async {
        guard let result = await cloudKitService.fetchFromCloud() else { return }
        
        // 合并展品
        for exhibit in result.exhibits {
            if !userExhibits.contains(where: { $0.id == exhibit.id }) {
                userExhibits.append(exhibit)
            }
        }
        
        // 合并图片 URL
        for (exhibitId, url) in result.photoURLs {
            if artifactPhotoURLs[exhibitId] == nil {
                artifactPhotoURLs[exhibitId] = url
            }
        }
        
        // 保存到本地
        saveUserExhibits()
        saveArtifactsMapping()
        
        // 刷新展品列表
        await loadExhibits()
        
        print("[AppState] 已从 CloudKit 拉取并合并数据")
    }
    
    /// 完整 CloudKit 同步（推拉）
    func fullCloudKitSync() async {
        // 先拉取远程数据
        await pullFromCloudKit()
        // 再推送本地数据
        await syncToCloudKit()
    }
    
    /// 保存图片 URL 映射
    private func saveArtifactsMapping() {
        var entries: [String: String] = [:]
        for (id, url) in artifactPhotoURLs {
            entries[id] = url.lastPathComponent
        }
        
        if let data = try? JSONEncoder().encode(entries) {
            iCloudStore.set(data, forKey: artifactKey)
            iCloudStore.synchronize()
            UserDefaults.standard.set(data, forKey: artifactKey)
        }
    }
    
    /// 订阅 CloudKit 变更通知
    func subscribeToCloudKitChanges() async {
        await cloudKitService.subscribeToChanges()
    }
}
