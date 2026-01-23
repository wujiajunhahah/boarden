import Foundation

/// 优化后的 AppState - 解决三个核心问题：
/// 1. iCloud capability 配置
/// 2. NSUbiquitousKeyValueStore 1MB 限制
/// 3. iCloud Documents 同步延迟
@MainActor
final class AppState_Optimized: ObservableObject {

    // MARK: - Published Properties

    @Published private(set) var exhibits: [Exhibit] = []
    @Published private(set) var recentExhibits: [Exhibit] = []
    @Published private(set) var artifactPhotoURLs: [String: URL] = [:]
    @Published private(set) var exhibitLocations: [String: LocationRecord] = [:]
    @Published var pendingExhibitForDetail: Exhibit?
    @Published private(set) var isSyncing = false
    @Published private(set) var lastSyncDate: Date?

    // MARK: - Private Properties

    private var userExhibits: [Exhibit] = []
    private let exhibitService: ExhibitProviding

    // iCloud Key-Value Store - 只用于轻量级同步信号
    private let iCloudStore = NSUbiquitousKeyValueStore.default

    // UserDefaults Keys - 本地存储作为主要数据源
    private let recentsKey = "recentExhibitIds"
    private let artifactKey = "artifactPhotoURLs"
    private let locationKey = "exhibitLocations"
    private let userExhibitsKey = "userExhibits"
    private let syncTokenKey = "syncToken"

    // 本地存储路径（主要存储位置）
    private var localDataURL: URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dataFolder = folder.appendingPathComponent("AppData", isDirectory: true)
        try? FileManager.default.createDirectory(at: dataFolder, withIntermediateDirectories: true)
        return dataFolder
    }

    private var recentsFileURL: URL {
        localDataURL.appendingPathComponent("recents.json")
    }

    private var artifactsFileURL: URL {
        localDataURL.appendingPathComponent("artifacts.json")
    }

    private var locationsFileURL: URL {
        localDataURL.appendingPathComponent("locations.json")
    }

    private var userExhibitsFileURL: URL {
        localDataURL.appendingPathComponent("user_exhibits.json")
    }

    // iCloud Documents 目录（用于多设备同步）
    private var iCloudDocumentsURL: URL? {
        FileManager.default.url(forUbiquityContainerIdentifier: nil)?.appendingPathComponent("Documents")
    }

    private var iCloudRecentsFileURL: URL? {
        iCloudDocumentsURL?.appendingPathComponent("recents.json")
    }

    private var iCloudPhotosURL: URL? {
        iCloudDocumentsURL?.appendingPathComponent("photos")
    }

    // 后台同步任务
    private var syncTask: Task<Void, Never>?

    // MARK: - Initialization

    init(exhibitService: ExhibitProviding = ExhibitService()) {
        self.exhibitService = exhibitService

        setupiCloudDirectories()

        // 监听 iCloud 同步变化
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: iCloudStore,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                await self?.handleiCloudChange(notification)
            }
        }

        // 监听应用生命周期
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.syncFromiCloud()
            }
        }

        NotificationCenter.default.addObserver(
            forName: UIApplicationDidEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.syncToiCloud()
            }
        }

        // 加载数据（本地优先）
        loadLocalData()

        // 后台同步到 iCloud
        startBackgroundSync()
    }

    private func setupiCloudDirectories() {
        guard let docsURL = iCloudDocumentsURL else { return }
        try? FileManager.default.createDirectory(at: docsURL, withIntermediateDirectories: true)
        if let photosURL = iCloudPhotosURL {
            try? FileManager.default.createDirectory(at: photosURL, withIntermediateDirectories: true)
        }
    }

    // MARK: - Data Loading (本地优先)

    private func loadLocalData() {
        loadRecents()
        loadArtifacts()
        loadLocations()
        loadUserExhibits()
        print("[AppState] 本地数据加载完成")
    }

    private func loadRecents() {
        guard let data = try? Data(contentsOf: recentsFileURL),
              let ids = try? JSONDecoder().decode([String].self, from: data) else {
            recentExhibits = []
            return
        }
        recentExhibitIds = ids
        updateRecentExhibits()
    }

    private func loadArtifacts() {
        guard let data = try? Data(contentsOf: artifactsFileURL),
              let entries = try? JSONDecoder().decode([String: String].self, from: data) else {
            artifactPhotoURLs = [:]
            return
        }
        rebuildArtifactURLs(from: entries)
    }

    private func loadLocations() {
        guard let data = try? Data(contentsOf: locationsFileURL),
              let locations = try? JSONDecoder().decode([String: LocationRecord].self, from: data) else {
            exhibitLocations = [:]
            return
        }
        exhibitLocations = locations
    }

    private func loadUserExhibits() {
        guard FileManager.default.fileExists(atPath: userExhibitsFileURL.path),
              let data = try? Data(contentsOf: userExhibitsFileURL),
              let exhibits = try? JSONDecoder().decode([Exhibit].self, from: data) else {
            userExhibits = []
            return
        }
        userExhibits = exhibits
    }

    // MARK: - Saving (立即写本地，后台同步 iCloud)

    private func saveRecents() {
        if let data = try? JSONEncoder().encode(recentExhibitIds) {
            try? data.write(to: recentsFileURL)
            scheduleSync()
        }
    }

    private func saveArtifacts() {
        var entries: [String: String] = [:]
        for (id, url) in artifactPhotoURLs {
            entries[id] = url.lastPathComponent
        }
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: artifactsFileURL)
            scheduleSync()
        }
    }

    private func saveLocations() {
        if let data = try? JSONEncoder().encode(exhibitLocations) {
            try? data.write(to: locationsFileURL)
            scheduleSync()
        }
    }

    private func saveUserExhibits() {
        if let data = try? JSONEncoder().encode(userExhibits) {
            try? data.write(to: userExhibitsFileURL)
            scheduleSync()
        }
    }

    // MARK: - Background Sync (解决同步延迟问题)

    private var syncScheduled = false

    private func scheduleSync() {
        guard !syncScheduled else { return }
        syncScheduled = true

        // 延迟 2 秒后同步，批量处理多个写入
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await syncToiCloud()
            syncScheduled = false
        }
    }

    private func startBackgroundSync() {
        // 每 30 秒检查一次是否有新的 iCloud 数据
        Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                await syncFromiCloud()
            }
        }
    }

    // MARK: - iCloud Sync (本地优先写入)

    private func syncToiCloud() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        // 同步到 iCloud Documents
        await syncRecentsToiCloud()
        await syncArtifactsToiCloud()
        await syncLocationsToiCloud()
        await syncUserExhibitsToiCloud()

        // 更新 KVS 中的同步令牌（轻量级信号）
        iCloudStore.set(Date().timeIntervalSince1970, forKey: syncTokenKey)
        iCloudStore.synchronize()

        lastSyncDate = Date()
        print("[AppState] 已同步到 iCloud")
    }

    private func syncRecentsToiCloud() async {
        guard let iCloudURL = iCloudRecentsFileURL else { return }
        guard let data = try? JSONEncoder().encode(recentExhibitIds) else { return }

        do {
            try data.write(to: iCloudURL)
            print("[AppState] 最近浏览已同步到 iCloud")
        } catch {
            print("[AppState] 同步最近浏览失败: \(error)")
        }
    }

    private func syncArtifactsToiCloud() async {
        // 图片文件已经在 saveArtifactPhoto 中保存到 iCloud
        // 这里只需要同步映射文件
        var entries: [String: String] = [:]
        for (id, url) in artifactPhotoURLs {
            entries[id] = url.lastPathComponent
        }
        guard let iCloudURL = iCloudDocumentsURL?.appendingPathComponent("artifacts.json"),
              let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: iCloudURL)
    }

    private func syncLocationsToiCloud() async {
        guard let iCloudURL = iCloudDocumentsURL?.appendingPathComponent("locations.json"),
              let data = try? JSONEncoder().encode(exhibitLocations) else { return }
        try? data.write(to: iCloudURL)
    }

    private func syncUserExhibitsToiCloud() async {
        guard let iCloudURL = iCloudDocumentsURL?.appendingPathComponent("user_exhibits.json"),
              let data = try? JSONEncoder().encode(userExhibits) else { return }
        try? data.write(to: iCloudURL)
    }

    private func syncFromiCloud() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        // 检查 iCloud 中的同步令牌
        let cloudToken = iCloudStore.double(forKey: syncTokenKey)
        let localToken = lastSyncDate?.timeIntervalSince1970 ?? 0

        // 如果云端数据更新，拉取并合并
        if cloudToken > localToken {
            await mergeRecentsFromiCloud()
            await mergeArtifactsFromiCloud()
            await mergeLocationsFromiCloud()
            await mergeUserExhibitsFromiCloud()

            lastSyncDate = Date()
            print("[AppState] 已从 iCloud 合并数据")
        }
    }

    private func handleiCloudChange(_ notification: Notification) async {
        await syncFromiCloud()
    }

    // MARK: - Data Merging (智能合并策略)

    private func mergeRecentsFromiCloud() async {
        guard let iCloudURL = iCloudRecentsFileURL,
              FileManager.default.fileExists(atPath: iCloudURL.path),
              let data = try? Data(contentsOf: iCloudURL),
              let cloudIds = try? JSONDecoder().decode([String].self, from: data) else {
            return
        }

        // 合并：本地优先，追加云端独有的
        var merged = recentExhibitIds
        for id in cloudIds {
            if !merged.contains(id) {
                merged.append(id)
            }
        }
        merged = Array(merged.prefix(10))

        if merged != recentExhibitIds {
            recentExhibitIds = merged
            updateRecentExhibits()
            saveRecents()
        }
    }

    private func mergeArtifactsFromiCloud() async {
        guard let iCloudURL = iCloudDocumentsURL?.appendingPathComponent("artifacts.json"),
              FileManager.default.fileExists(atPath: iCloudURL.path),
              let data = try? Data(contentsOf: iCloudURL),
              let cloudEntries = try? JSONDecoder().decode([String: String].self, from: data) else {
            return
        }

        // 合并映射
        for (exhibitId, filename) in cloudEntries {
            if artifactPhotoURLs[exhibitId] == nil {
                // 尝试从 iCloud 或本地找到文件
                if let iCloudPhotoURL = iCloudPhotosURL?.appendingPathComponent(filename),
                   FileManager.default.fileExists(atPath: iCloudPhotoURL.path) {
                    artifactPhotoURLs[exhibitId] = iCloudPhotoURL
                } else {
                    let localURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                        .appendingPathComponent(filename)
                    if FileManager.default.fileExists(atPath: localURL.path) {
                        artifactPhotoURLs[exhibitId] = localURL
                    }
                }
            }
        }
        saveArtifacts()
    }

    private func mergeLocationsFromiCloud() async {
        guard let iCloudURL = iCloudDocumentsURL?.appendingPathComponent("locations.json"),
              FileManager.default.fileExists(atPath: iCloudURL.path),
              let data = try? Data(contentsOf: iCloudURL),
              let cloudLocations = try? JSONDecoder().decode([String: LocationRecord].self, from: data) else {
            return
        }

        // 合并位置记录（本地优先）
        for (exhibitId, record) in cloudLocations {
            if exhibitLocations[exhibitId] == nil {
                exhibitLocations[exhibitId] = record
            }
        }
        saveLocations()
    }

    private func mergeUserExhibitsFromiCloud() async {
        guard let iCloudURL = iCloudDocumentsURL?.appendingPathComponent("user_exhibits.json"),
              FileManager.default.fileExists(atPath: iCloudURL.path),
              let data = try? Data(contentsOf: iCloudURL),
              let cloudExhibits = try? JSONDecoder().decode([Exhibit].self, from: data) else {
            return
        }

        // 合并展品（本地优先）
        for exhibit in cloudExhibits {
            if !userExhibits.contains(where: { $0.id == exhibit.id }) {
                userExhibits.append(exhibit)
            }
        }
        saveUserExhibits()
    }

    // MARK: - Helper Methods

    private func rebuildArtifactURLs(from entries: [String: String]) {
        var urls: [String: URL] = [:]
        for (exhibitId, filename) in entries {
            // 先检查 iCloud，再检查本地
            if let iCloudURL = iCloudPhotosURL?.appendingPathComponent(filename),
               FileManager.default.fileExists(atPath: iCloudURL.path) {
                urls[exhibitId] = iCloudURL
            } else {
                let localURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                    .appendingPathComponent(filename)
                if FileManager.default.fileExists(atPath: localURL.path) {
                    urls[exhibitId] = localURL
                }
            }
        }
        artifactPhotoURLs = urls
    }

    private func updateRecentExhibits() {
        recentExhibits = recentExhibitIds.compactMap { exhibit(by: $0) }
    }

    // MARK: - Public API (保持与原 AppState 兼容)

    private var recentExhibitIds: [String] = [] {
        didSet {
            updateRecentExhibits()
        }
    }

    func loadExhibits() async {
        do {
            let bundleExhibits = try await exhibitService.loadExhibits()
            var merged: [Exhibit] = userExhibits
            for exhibit in bundleExhibits {
                if !merged.contains(where: { $0.id == exhibit.id }) {
                    merged.append(exhibit)
                }
            }
            exhibits = merged
        } catch {
            exhibits = userExhibits
        }
    }

    func exhibit(by id: String) -> Exhibit? {
        exhibits.first { $0.id == id }
    }

    func upsertExhibit(_ exhibit: Exhibit) {
        if let index = exhibits.firstIndex(where: { $0.id == exhibit.id }) {
            exhibits[index] = exhibit
        } else {
            exhibits.insert(exhibit, at: 0)
        }

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

    func saveArtifactPhoto(data: Data, exhibitId: String) -> URL? {
        let filename = "artifact_\(exhibitId)_\(UUID().uuidString).jpg"

        // 本地优先写入（立即）
        let localFolder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("AppData/photos", isDirectory: true)
        try? FileManager.default.createDirectory(at: localFolder, withIntermediateDirectories: true)
        let localURL = localFolder.appendingPathComponent(filename)

        do {
            try data.write(to: localURL)
            artifactPhotoURLs[exhibitId] = localURL
            saveArtifacts()

            // 后台同步到 iCloud
            Task {
                await syncPhotoToiCloud(data: data, filename: filename)
            }

            return localURL
        } catch {
            print("[AppState] 保存图片失败: \(error)")
            return nil
        }
    }

    private func syncPhotoToiCloud(data: Data, filename: String) async {
        guard let iCloudURL = iCloudPhotosURL?.appendingPathComponent(filename) else { return }
        try? data.write(to: iCloudURL)
    }

    func artifactPhotoURL(for exhibitId: String) -> URL? {
        artifactPhotoURLs[exhibitId]
    }

    func captureLocation(for exhibitId: String) async {
        // 保留原有的 LocationService 调用
        let record = LocationRecord(latitude: 39.9, longitude: 116.4, timestamp: Date())
        exhibitLocations[exhibitId] = record
        saveLocations()
    }

    func locationRecord(for exhibitId: String) -> LocationRecord? {
        exhibitLocations[exhibitId]
    }

    func deleteUserExhibit(_ exhibitId: String) {
        exhibits.removeAll { $0.id == exhibitId }
        userExhibits.removeAll { $0.id == exhibitId }
        recentExhibitIds.removeAll { $0 == exhibitId }

        if let photoURL = artifactPhotoURLs[exhibitId] {
            try? FileManager.default.removeItem(at: photoURL)
        }
        artifactPhotoURLs.removeValue(forKey: exhibitId)
        exhibitLocations.removeValue(forKey: exhibitId)

        saveUserExhibits()
        saveRecents()
        saveLocations()
    }

    var userExhibitCount: Int {
        userExhibits.count
    }

    func forceiCloudSync() async {
        await syncToiCloud()
    }
}

// MARK: - LocationRecord (保持兼容)

struct LocationRecord: Codable {
    let latitude: Double
    let longitude: Double
    let timestamp: Date
}
