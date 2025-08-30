import Foundation
import CloudKit
import Combine
import UIKit
import SwiftUI

// MARK: - BackupItem
/// 実際のバックアップデータ項目
struct BackupItem: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let memoCount: Int
    let recordName: String
    let comment: String
    
    init(memoCount: Int, comment: String = "") {
        self.id = UUID()
        self.timestamp = Date()
        self.memoCount = memoCount
        self.recordName = "backup_\(UUID().uuidString)"
        self.comment = comment
    }
    
    init(id: UUID, timestamp: Date, memoCount: Int, recordName: String, comment: String = "") {
        self.id = id
        self.timestamp = timestamp
        self.memoCount = memoCount
        self.recordName = recordName
        self.comment = comment
    }
    
    /// 日時の表示用フォーマット
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy/MM/dd HH:mm:ss"
        return formatter.string(from: timestamp)
    }
    
    /// 表示用テキスト
    var displayText: String {
        if comment.isEmpty {
            return "\(memoCount)件のメモ - \(formattedDate)"
        } else {
            return "\(comment) (\(memoCount)件) - \(formattedDate)"
        }
    }
    
    /// バックアップ識別名（履歴表示用）
    var identifierName: String {
        if !comment.isEmpty {
            return "「\(comment)」"
        } else {
            return "\(formattedDate)のバックアップ"
        }
    }
}

// MARK: - BackupHistoryItem
/// バックアップ履歴項目（記録専用）
struct BackupHistoryItem: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let action: BackupAction  // バックアップ、復元、削除の記録
    let memoCount: Int?       // バックアップ・復元時のメモ数（削除時はnil）
    let backupId: UUID?       // 対象バックアップのID（削除・復元時）
    let backupComment: String? // 対象バックアップのコメント
    
    init(action: BackupAction, memoCount: Int? = nil, backupId: UUID? = nil, backupComment: String? = nil) {
        self.id = UUID()
        self.timestamp = Date()
        self.action = action
        self.memoCount = memoCount
        self.backupId = backupId
        self.backupComment = backupComment
    }
    
    /// 日時の表示用フォーマット
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy/MM/dd HH:mm:ss"
        return formatter.string(from: timestamp)
    }
    
    /// 履歴の表示用テキスト
    var displayText: String {
        let backupName: String
        if let comment = backupComment, !comment.isEmpty {
            backupName = "「\(comment)」"
        } else {
            // バックアップIDから対応するバックアップアイテムを探してidentifierNameを使用
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "ja_JP")
            formatter.dateFormat = "yyyy/MM/dd HH:mm:ss"
            backupName = "\(formatter.string(from: timestamp))のバックアップ"
        }
        
        switch action {
        case .backup:
            if let count = memoCount {
                return "\(backupName)(\(count)件) をバックアップ"
            }
            return "\(backupName) をバックアップ"
        case .restore:
            if let count = memoCount {
                return "\(backupName)(\(count)件) から復元"
            }
            return "\(backupName) から復元"
        case .delete:
            return "\(backupName) を削除"
        }
    }
    
    /// アクションアイコン
    var actionIcon: String {
        switch action {
        case .backup:
            return "icloud.and.arrow.up"
        case .restore:
            return "icloud.and.arrow.down"
        case .delete:
            return "trash"
        }
    }
    
    /// アクションカラー
    var actionColor: Color {
        switch action {
        case .backup:
            return .blue
        case .restore:
            return .green
        case .delete:
            return .red
        }
    }
}

// MARK: - BackupAction
/// バックアップアクションの種類
enum BackupAction: String, Codable {
    case backup = "backup"     // バックアップ作成
    case restore = "restore"   // バックアップ復元
    case delete = "delete"     // バックアップ削除
}


// MARK: - iCloudBackupManager
/// iCloudバックアップ管理クラス（記録専用）
class iCloudBackupManager: ObservableObject {
    // MARK: - Published Properties
    @Published var isAvailable = false
    @Published var isBackingUp = false
    @Published var isRestoring = false
    @Published var isDeleting = false
    @Published var backupItems: [BackupItem] = []
    @Published var backupHistory: [BackupHistoryItem] = []
    @Published var lastError: Error?
    @Published var latestBackupInfo: String = "バックアップなし"
    
    // MARK: - Private Properties
    private let container: CKContainer
    private let privateDatabase: CKDatabase
    private let recordType = "MemoBackup"
    private let historyKey = "backup_history"
    private let latestBackupKey = "latest_backup_info"
    private let backupItemsKey = "backup_items"
    
    
    // MARK: - Singleton
    static let shared = iCloudBackupManager()
    
    // MARK: - Initializer
    private init() {
        self.container = CKContainer.default()
        self.privateDatabase = container.privateCloudDatabase
        
        checkiCloudAvailability()
        loadBackupHistory()
        loadLatestBackupInfo()
        loadBackupItems()
    }
    
    // MARK: - iCloud Availability Check
    /// iCloudの利用可能性をチェック
    func checkiCloudAvailability() {
        container.accountStatus { [weak self] accountStatus, error in
            DispatchQueue.main.async {
                self?.isAvailable = (accountStatus == .available)
                if accountStatus != .available {
                    self?.lastError = error
                }
            }
        }
    }
    
    // MARK: - Backup Methods
    /// メモデータをiCloudにバックアップ
    func backupMemos(_ memos: [Memo], comment: String = "") async throws {
        guard isAvailable else {
            throw NSError(domain: "iCloud", code: 1, userInfo: [NSLocalizedDescriptionKey: "iCloudが利用できません"])
        }
        
        await MainActor.run {
            isBackingUp = true
            lastError = nil
        }
        
        do {
            // 新しいバックアップアイテムを作成
            let backupItem = BackupItem(memoCount: memos.count, comment: comment)
            
            // メモデータをJSONにシリアライズ
            let jsonData = try JSONEncoder().encode(memos)
            
            // CloudKitレコードを作成
            let record = CKRecord(recordType: recordType, recordID: CKRecord.ID(recordName: backupItem.recordName))
            record["data"] = jsonData
            record["timestamp"] = backupItem.timestamp
            record["memoCount"] = backupItem.memoCount
            record["backupId"] = backupItem.id.uuidString
            record["comment"] = backupItem.comment
            
            // iCloudに保存
            let _ = try await privateDatabase.save(record)
            
            await MainActor.run {
                // バックアップリストに追加
                self.backupItems.insert(backupItem, at: 0)
                
                // 古いバックアップを削除（最新10件まで保持）
                if self.backupItems.count > 10 {
                    let oldBackups = Array(self.backupItems.suffix(from: 10))
                    self.backupItems = Array(self.backupItems.prefix(10))
                    
                    // 古いバックアップをiCloudからも削除
                    Task {
                        for oldBackup in oldBackups {
                            try? await self.deleteBackupFromiCloud(oldBackup)
                        }
                    }
                }
                
                self.saveBackupItems()
                
                // 最新バックアップ情報を更新
                self.latestBackupInfo = backupItem.displayText
                self.saveLatestBackupInfo()
                
                // 履歴に記録
                let historyItem = BackupHistoryItem(action: .backup, memoCount: memos.count, backupId: backupItem.id, backupComment: comment.isEmpty ? nil : comment)
                self.addToHistory(historyItem)
                
                self.isBackingUp = false
            }
            
        } catch {
            await MainActor.run {
                self.isBackingUp = false
                self.lastError = error
            }
            throw error
        }
    }
    
    /// すべてのバックアップを取得
    func fetchAllBackups() async throws {
        guard isAvailable else {
            throw NSError(domain: "iCloud", code: 1, userInfo: [NSLocalizedDescriptionKey: "iCloudが利用できません"])
        }
        
        let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        
        let result = try await privateDatabase.records(matching: query)
        var fetchedItems: [BackupItem] = []
        
        for (_, record) in result.matchResults {
            switch record {
            case .success(let ckRecord):
                if let backupIdString = ckRecord["backupId"] as? String,
                   let backupId = UUID(uuidString: backupIdString),
                   let timestamp = ckRecord["timestamp"] as? Date,
                   let memoCount = ckRecord["memoCount"] as? Int {
                    
                    let comment = ckRecord["comment"] as? String ?? ""
                    
                    let backupItem = BackupItem(
                        id: backupId,
                        timestamp: timestamp,
                        memoCount: memoCount,
                        recordName: ckRecord.recordID.recordName,
                        comment: comment
                    )
                    fetchedItems.append(backupItem)
                }
            case .failure(_):
                continue
            }
        }
        
        let items = fetchedItems
        let latestInfo = items.first?.displayText
        
        await MainActor.run {
            self.backupItems = items
            self.saveBackupItems()
            
            if let info = latestInfo {
                self.latestBackupInfo = info
                self.saveLatestBackupInfo()
            }
        }
    }
    
    // MARK: - Restore Methods
    /// 最新のバックアップから復元
    func restoreLatestBackup() async throws -> [Memo] {
        guard let latestBackup = backupItems.first else {
            throw NSError(domain: "iCloud", code: 2, userInfo: [NSLocalizedDescriptionKey: "復元可能なバックアップがありません"])
        }
        
        return try await restoreFromBackup(latestBackup)
    }
    
    /// 指定したバックアップから復元
    func restoreFromBackup(_ backupItem: BackupItem) async throws -> [Memo] {
        guard isAvailable else {
            throw NSError(domain: "iCloud", code: 1, userInfo: [NSLocalizedDescriptionKey: "iCloudが利用できません"])
        }
        
        await MainActor.run {
            isRestoring = true
            lastError = nil
        }
        
        do {
            let recordID = CKRecord.ID(recordName: backupItem.recordName)
            let record = try await privateDatabase.record(for: recordID)
            
            guard let jsonData = record["data"] as? Data else {
                throw NSError(domain: "iCloud", code: 2, userInfo: [NSLocalizedDescriptionKey: "バックアップデータが見つかりません"])
            }
            
            let memos = try JSONDecoder().decode([Memo].self, from: jsonData)
            
            await MainActor.run {
                // 履歴に記録
                let historyItem = BackupHistoryItem(action: .restore, memoCount: memos.count, backupId: backupItem.id, backupComment: backupItem.comment.isEmpty ? nil : backupItem.comment)
                self.addToHistory(historyItem)
                
                self.isRestoring = false
            }
            
            return memos
            
        } catch {
            await MainActor.run {
                self.isRestoring = false
                self.lastError = error
            }
            throw error
        }
    }
    
    // MARK: - Delete Methods
    /// 指定したバックアップを削除
    func deleteBackup(_ backupItem: BackupItem) async throws {
        guard isAvailable else {
            throw NSError(domain: "iCloud", code: 1, userInfo: [NSLocalizedDescriptionKey: "iCloudが利用できません"])
        }
        
        await MainActor.run {
            isDeleting = true
            lastError = nil
        }
        
        do {
            // iCloudから削除
            try await deleteBackupFromiCloud(backupItem)
            
            await MainActor.run {
                // ローカルリストから削除
                self.backupItems.removeAll { $0.id == backupItem.id }
                self.saveBackupItems()
                
                // 最新バックアップ情報を更新
                if let newLatest = self.backupItems.first {
                    self.latestBackupInfo = newLatest.displayText
                } else {
                    self.latestBackupInfo = "バックアップなし"
                }
                self.saveLatestBackupInfo()
                
                // 履歴に記録
                let historyItem = BackupHistoryItem(action: .delete, backupId: backupItem.id, backupComment: backupItem.comment.isEmpty ? nil : backupItem.comment)
                self.addToHistory(historyItem)
                
                self.isDeleting = false
            }
            
        } catch {
            await MainActor.run {
                self.isDeleting = false
                self.lastError = error
            }
            throw error
        }
    }
    
    // MARK: - Helper Methods
    /// iCloudからバックアップを削除
    private func deleteBackupFromiCloud(_ backupItem: BackupItem) async throws {
        let recordID = CKRecord.ID(recordName: backupItem.recordName)
        try await privateDatabase.deleteRecord(withID: recordID)
    }
    
    /// 履歴に項目を追加（最新20件まで保持）
    private func addToHistory(_ item: BackupHistoryItem) {
        backupHistory.insert(item, at: 0)
        if backupHistory.count > 20 {
            backupHistory = Array(backupHistory.prefix(20))
        }
        saveBackupHistory()
    }
    
    /// バックアップ履歴をローカルに保存
    private func saveBackupHistory() {
        do {
            let data = try JSONEncoder().encode(backupHistory)
            UserDefaults.standard.set(data, forKey: historyKey)
        } catch {
            print("❌ 履歴保存エラー: \(error)")
        }
    }
    
    /// バックアップ履歴をローカルから読み込み
    private func loadBackupHistory() {
        guard let data = UserDefaults.standard.data(forKey: historyKey) else { return }
        
        do {
            backupHistory = try JSONDecoder().decode([BackupHistoryItem].self, from: data)
        } catch {
            print("❌ 履歴読み込みエラー: \(error)")
            backupHistory = []
        }
    }
    
    /// 最新バックアップ情報を保存
    private func saveLatestBackupInfo() {
        UserDefaults.standard.set(latestBackupInfo, forKey: latestBackupKey)
    }
    
    /// 最新バックアップ情報を読み込み
    private func loadLatestBackupInfo() {
        latestBackupInfo = UserDefaults.standard.string(forKey: latestBackupKey) ?? "バックアップなし"
    }
    
    /// バックアップアイテムをローカルに保存
    private func saveBackupItems() {
        do {
            let data = try JSONEncoder().encode(backupItems)
            UserDefaults.standard.set(data, forKey: backupItemsKey)
        } catch {
            print("❌ バックアップリスト保存エラー: \(error)")
        }
    }
    
    /// バックアップアイテムをローカルから読み込み
    private func loadBackupItems() {
        guard let data = UserDefaults.standard.data(forKey: backupItemsKey) else { return }
        
        do {
            backupItems = try JSONDecoder().decode([BackupItem].self, from: data)
        } catch {
            print("❌ バックアップリスト読み込みエラー: \(error)")
            backupItems = []
        }
    }
    
    /// すべての操作履歴を削除
    func clearAllHistory() {
        backupHistory = []
        saveBackupHistory()
    }
}
