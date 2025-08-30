import Foundation
import UserNotifications
import UIKit

// MARK: - Notification History Model
/// 通知履歴のデータモデル
struct NotificationHistory: Identifiable, Codable {
    /// 履歴の一意識別子
    let id: UUID
    /// 関連するメモのID
    let memoId: UUID
    /// メモのタイトル
    let memoTitle: String
    /// 通知の種類
    let notificationType: NotificationType
    /// 通知が送信された日時
    let sentAt: Date
    /// 既読状態
    var isRead: Bool
    
    /// 通知の種類を定義
    enum NotificationType: String, Codable, CaseIterable {
        case main = "main"              // メイン通知（期日当日）
        case preNotification = "pre"    // 予備通知（期日前）
        
        /// 表示用の名前
        var displayName: String {
            switch self {
            case .main:
                return "期日通知"
            case .preNotification:
                return "予備通知"
            }
        }
    }
    
    /// 初期化
    init(memoId: UUID, memoTitle: String, notificationType: NotificationType) {
        self.id = UUID()
        self.memoId = memoId
        self.memoTitle = memoTitle
        self.notificationType = notificationType
        self.sentAt = Date()
        self.isRead = false
    }
    
    /// 既読にする
    mutating func markAsRead() {
        isRead = true
    }
}

// MARK: - Notification Manager
/// 通知の管理を行うクラス
/// メモの期日通知のスケジューリングと権限管理を担当
class NotificationManager: NSObject, ObservableObject {
    static let shared = NotificationManager()
    
    @Published var isNotificationPermissionGranted = false
    @Published var notificationHistory: [NotificationHistory] = []
    
    private let historyFile: URL
    
    private override init() {
        // 通知履歴ファイルのパスを設定
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        historyFile = documentsDirectory.appendingPathComponent("notification_history.json")
        
        super.init()
        
        print("📱 NotificationManager 初期化開始")
        
        // バッジを絶対に表示させない
        disableBadge()
        
        loadNotificationHistory()
        checkNotificationPermission()
        
        // デリゲートはAppDelegateで設定されるため、ここでは設定しない
        print("ℹ️ UNUserNotificationCenter デリゲートはAppDelegateで設定済み")
        
        // 通知カテゴリーを設定
        setupNotificationCategories()
        print("📋 通知カテゴリー設定完了")
        
        // 通知権限がない場合は履歴をクリア
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if !self.isNotificationPermissionGranted && !self.notificationHistory.isEmpty {
                print("🧹 通知権限なしのため履歴をクリア")
                self.clearAllHistory()
            }
            // バッジを再度無効化
            self.disableBadge()
        }
    }
    
    
    // MARK: - Badge Management
    /// バッジを絶対に無効化する（iOS 17.0対応）
    func disableBadge() {
        if #available(iOS 17.0, *) {
            UNUserNotificationCenter.current().setBadgeCount(0) { error in
                if let error = error {
                    print("⚠️ バッジ無効化エラー: \(error)")
                }
            }
        } else {
            DispatchQueue.main.async {
                UIApplication.shared.applicationIconBadgeNumber = 0
            }
        }
    }
    
    // MARK: - Permission Management
    /// 通知権限をリクエスト
    func requestNotificationPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            
            await MainActor.run {
                self.isNotificationPermissionGranted = granted
                // バッジを絶対に表示させない
                self.disableBadge()
            }
            
            return granted
        } catch {
            print("通知権限リクエストエラー: \(error)")
            return false
        }
    }
    
    /// 現在の通知権限状態をチェック
    func checkNotificationPermission() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.isNotificationPermissionGranted = settings.authorizationStatus == .authorized
                // バッジを絶対に表示させない
                self.disableBadge()
            }
        }
    }
    
    // MARK: - Notification Scheduling
    /// メモの期日通知をスケジュール
    /// - Parameter memo: 通知をスケジュールするメモ
    func scheduleNotification(for memo: Memo) {
        guard let dueDate = memo.dueDate else { 
            print("⚠️ 期日が設定されていないため通知をスキップ")
            return 
        }
        
        print("📅 通知スケジュール開始: \(memo.displayTitle) - 期日: \(dueDate)")
        
        // 通知権限を確認
        guard isNotificationPermissionGranted else {
            print("❌ 通知権限がないため通知をスキップ")
            return
        }
        
        // 既存の通知を削除
        removeNotifications(for: memo)
        print("🗑️ 既存通知を削除")
        
        // メイン通知をスケジュール
        scheduleMainNotification(for: memo, dueDate: dueDate)
        print("📩 メイン通知をスケジュール")
        
        // 予備通知をスケジュール（有効な場合）
        if memo.hasPreNotification {
            schedulePreNotification(for: memo, dueDate: dueDate)
            print("📬 予備通知をスケジュール (\(memo.preNotificationMinutes)分前)")
        }
        
        print("✅ 通知スケジュール完了")
    }
    
    /// メモの通知を削除
    /// - Parameter memo: 通知を削除するメモ
    func removeNotifications(for memo: Memo) {
        let center = UNUserNotificationCenter.current()
        let identifiers = [
            getMainNotificationId(for: memo),
            getPreNotificationId(for: memo)
        ]
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }
    
    /// 全ての通知を削除
    func removeAllNotifications() {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
    }
    
    // MARK: - Private Methods
    /// メイン通知をスケジュール
    private func scheduleMainNotification(for memo: Memo, dueDate: Date) {
        let content = UNMutableNotificationContent()
        content.title = "期日になりました"
        content.body = memo.displayTitle
        content.sound = .default
        content.categoryIdentifier = "MEMO_DUE"
        content.userInfo = ["memoId": memo.id.uuidString]
        
        // 期日の時刻に通知
        let dateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: dueDate)
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: dateComponents,
            repeats: false
        )
        
        let identifier = getMainNotificationId(for: memo)
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )
        
        print("📅 メイン通知の詳細:")
        print("   ID: \(identifier)")
        print("   タイトル: \(content.title)")
        print("   本文: \(content.body)")
        print("   期日: \(dueDate)")
        print("   トリガー: \(dateComponents)")
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ 通知のスケジュールエラー: \(error)")
            } else {
                print("✅ 通知のスケジュール成功")
            }
        }
    }
    
    /// 予備通知をスケジュール
    private func schedulePreNotification(for memo: Memo, dueDate: Date) {
        let preNotificationDate = Calendar.current.date(
            byAdding: .minute,
            value: -memo.preNotificationMinutes,
            to: dueDate
        )
        
        guard let preDate = preNotificationDate, preDate > Date() else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "期日が近づいています"
        content.body = "\(memo.displayTitle) (\(formatTimeRemaining(memo.preNotificationMinutes))後)"
        content.sound = .default
        content.categoryIdentifier = "MEMO_DUE"
        content.userInfo = ["memoId": memo.id.uuidString]
        
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: preDate),
            repeats: false
        )
        
        let request = UNNotificationRequest(
            identifier: getPreNotificationId(for: memo),
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ 通知のスケジュールエラー: \(error)")
            } else {
                print("✅ 通知のスケジュール成功")
            }
        }
    }
    
    /// メイン通知のIDを取得
    private func getMainNotificationId(for memo: Memo) -> String {
        return "memo_due_\(memo.id.uuidString)"
    }
    
    /// 予備通知のIDを取得
    private func getPreNotificationId(for memo: Memo) -> String {
        return "memo_pre_\(memo.id.uuidString)"
    }
    
    /// 時間の残り時間を文字列に変換
    private func formatTimeRemaining(_ minutes: Int) -> String {
        if minutes < 60 {
            return "\(minutes)分"
        } else {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            if remainingMinutes == 0 {
                return "\(hours)時間"
            } else {
                return "\(hours)時間\(remainingMinutes)分"
            }
        }
    }
    
    // MARK: - Notification History Management
    /// 通知履歴を追加
    /// - Parameters:
    ///   - memoId: メモのID
    ///   - memoTitle: メモのタイトル
    ///   - notificationType: 通知の種類
    func addNotificationHistory(memoId: UUID, memoTitle: String, notificationType: NotificationHistory.NotificationType) {
        let history = NotificationHistory(memoId: memoId, memoTitle: memoTitle, notificationType: notificationType)
        
        DispatchQueue.main.async {
            self.notificationHistory.insert(history, at: 0) // 最新を先頭に追加
            self.saveNotificationHistory()
            
            // バッジを絶対に表示させない
            self.disableBadge()
        }
    }
    
    /// 通知履歴を既読にする
    /// - Parameter historyId: 履歴のID
    func markHistoryAsRead(_ historyId: UUID) {
        DispatchQueue.main.async {
            if let index = self.notificationHistory.firstIndex(where: { $0.id == historyId }) {
                self.notificationHistory[index].markAsRead()
                self.saveNotificationHistory()
                
                // バッジを絶対に表示させない
                self.disableBadge()
            }
        }
    }
    
    /// すべての通知履歴を既読にする
    func markAllHistoryAsRead() {
        DispatchQueue.main.async {
            for i in 0..<self.notificationHistory.count {
                self.notificationHistory[i].markAsRead()
            }
            
            self.saveNotificationHistory()
            
            // バッジを絶対に表示させない
            self.disableBadge()
        }
    }
    
    
    /// 通知履歴をメモIDで検索
    /// - Parameter memoId: メモのID
    /// - Returns: 該当するメモの通知履歴
    func getNotificationHistory(for memoId: UUID) -> [NotificationHistory] {
        return notificationHistory.filter { $0.memoId == memoId }
    }
    
    /// 通知履歴を削除
    /// - Parameter historyId: 削除する履歴のID
    func deleteNotificationHistory(_ historyId: UUID) {
        DispatchQueue.main.async {
            self.notificationHistory.removeAll { $0.id == historyId }
            self.saveNotificationHistory()
        }
    }
    
    /// 指定日数以前の通知履歴を削除
    /// - Parameter days: 保持日数
    func cleanupOldHistory(olderThan days: Int = 30) {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        
        DispatchQueue.main.async {
            self.notificationHistory.removeAll { $0.sentAt < cutoffDate }
            self.saveNotificationHistory()
        }
    }
    
    /// 全ての通知履歴をクリア
    func clearAllHistory() {
        DispatchQueue.main.async {
            self.notificationHistory.removeAll()
            self.saveNotificationHistory()
            
            // バッジを絶対に表示させない
            self.disableBadge()
        }
    }
    
    // MARK: - Private History Persistence Methods
    /// 通知履歴をファイルに保存
    private func saveNotificationHistory() {
        DispatchQueue.global(qos: .utility).async {
            do {
                let encoder = JSONEncoder()
                let data = try encoder.encode(self.notificationHistory)
                try data.write(to: self.historyFile)
            } catch {
                // 保存失敗時は静かに無視
            }
        }
    }
    
    /// 通知履歴をファイルから読み込み
    private func loadNotificationHistory() {
        guard FileManager.default.fileExists(atPath: historyFile.path) else {
            return
        }
        
        do {
            let data = try Data(contentsOf: historyFile)
            let decoder = JSONDecoder()
            let loadedHistory = try decoder.decode([NotificationHistory].self, from: data)
            
            DispatchQueue.main.async {
                self.notificationHistory = loadedHistory
            }
        } catch {
            notificationHistory = []
        }
    }
}

// MARK: - Notification Categories
extension NotificationManager {
    /// 通知カテゴリーを設定
    func setupNotificationCategories() {
        let center = UNUserNotificationCenter.current()
        
        // アクションを定義
        let completeAction = UNNotificationAction(
            identifier: "COMPLETE_ACTION",
            title: "完了",
            options: []
        )
        
        let postponeAction = UNNotificationAction(
            identifier: "POSTPONE_ACTION",
            title: "1時間後に再通知",
            options: []
        )
        
        let openMemoAction = UNNotificationAction(
            identifier: "OPEN_MEMO_ACTION",
            title: "メモを開く",
            options: [.foreground]
        )
        
        // カテゴリーを作成
        let category = UNNotificationCategory(
            identifier: "MEMO_DUE",
            actions: [openMemoAction, completeAction, postponeAction],
            intentIdentifiers: [],
            options: []
        )
        
        center.setNotificationCategories([category])
        
        // デリゲートはAppDelegateで設定されるため、ここでは設定しない
        print("ℹ️ UNUserNotificationCenter デリゲートはAppDelegateで管理")
    }
}

// MARK: - UNUserNotificationCenterDelegate (Deprecated)
// 注意: 通知デリゲートの処理は AppDelegate に移管されました
// すべての通知（FCM/ローカル）はAppDelegateで一元管理されます

/*
extension NotificationManager: UNUserNotificationCenterDelegate {
    // この拡張は使用されなくなりました
    // すべての通知処理は AppDelegate で行われます
}
*/
