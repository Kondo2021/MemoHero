import SwiftUI
import UIKit
import UserNotifications
import FirebaseMessaging

// MARK: - Notification History Models

/// 通知履歴エントリ
struct NotificationHistoryEntry: Identifiable, Codable {
    let id: UUID
    let title: String
    let body: String
    let receivedAt: Date
    let notificationType: String
    let userInfo: [String: String] // シリアライズ可能な形に変換
    let isFromFCM: Bool
    let wasTapped: Bool
    
    init(title: String, body: String, notificationType: String = "unknown", userInfo: [AnyHashable: Any] = [:], isFromFCM: Bool = false, wasTapped: Bool = false) {
        self.id = UUID()
        self.title = title
        self.body = body
        self.receivedAt = Date()
        self.notificationType = notificationType
        self.isFromFCM = isFromFCM
        self.wasTapped = wasTapped
        
        // [AnyHashable: Any]を[String: String]に変換
        var convertedUserInfo: [String: String] = [:]
        for (key, value) in userInfo {
            if let keyString = key as? String {
                convertedUserInfo[keyString] = String(describing: value)
            }
        }
        self.userInfo = convertedUserInfo
    }
    
    /// 表示用の短いタイトル
    var displayTitle: String {
        return title.isEmpty ? "通知" : title
    }
    
    /// 表示用の日時文字列
    var displayTime: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.string(from: receivedAt)
    }
    
    /// 「新しいイベント」の文字が含まれているかどうか
    var containsNewEventText: Bool {
        let fullMessage = "\(title) \(body)"
        return fullMessage.contains("新しいイベント")
    }
}

/// 通知履歴管理クラス
class NotificationHistoryManager: ObservableObject {
    // MARK: - Singleton
    static let shared = NotificationHistoryManager()
    
    // MARK: - Published Properties
    @Published var notifications: [NotificationHistoryEntry] = [] {
        didSet {
            print("🔄 === @Published notifications 変更検知 ===")
            print("🔄 変更前の件数: \(oldValue.count)")
            print("🔄 変更後の件数: \(notifications.count)")
            print("🔄 === notifications変更詳細 ===")
            for (index, notification) in notifications.enumerated() {
                print("🔄 [\(index)] '\(notification.displayTitle)' - FCM:\(notification.isFromFCM)")
            }
            print("🔄 === notifications変更終了 ===")
            print("")
        }
    }
    
    // MARK: - Private Properties
    private let maxHistoryCount = 100 // 最大保存件数
    private let userDefaultsKey = "notification_history"
    
    // MARK: - Initialization
    private init() {
        print("🏗️ === NotificationHistoryManager初期化開始 ===")
        loadHistory()
        print("🏗️ NotificationHistoryManager初期化完了")
        print("🏗️   初期化後の履歴件数: \(notifications.count)")
        print("🏗️   maxHistoryCount: \(maxHistoryCount)")
        print("🏗️   userDefaultsKey: \(userDefaultsKey)")
        print("🏗️ === NotificationHistoryManager初期化終了 ===")
        print("")
    }
    
    /// 新しい通知を履歴に追加
    func addNotification(
        title: String,
        body: String,
        notificationType: String = "unknown",
        userInfo: [AnyHashable: Any] = [:],
        isFromFCM: Bool = false,
        wasTapped: Bool = false
    ) {
        print("🚨 === NotificationHistoryManager.addNotification 開始 ===")
        print("🚨 引数詳細:")
        print("🚨   title: '\(title)'")
        print("🚨   body: '\(body)'")
        print("🚨   notificationType: '\(notificationType)'")
        print("🚨   isFromFCM: \(isFromFCM)")
        print("🚨   wasTapped: \(wasTapped)")
        print("🚨   userInfo: \(userInfo)")
        
        let entry = NotificationHistoryEntry(
            title: title,
            body: body,
            notificationType: notificationType,
            userInfo: userInfo,
            isFromFCM: isFromFCM,
            wasTapped: wasTapped
        )
        
        print("🚨 作成されたエントリ:")
        print("🚨   entry.title: '\(entry.title)'")
        print("🚨   entry.body: '\(entry.body)'")
        print("🚨   entry.displayTitle: '\(entry.displayTitle)'")
        print("🚨   entry.notificationType: '\(entry.notificationType)'")
        print("🚨   entry.isFromFCM: \(entry.isFromFCM)")
        print("🚨   entry.containsNewEventText: \(entry.containsNewEventText)")
        
        DispatchQueue.main.async {
            print("🚨 メインキューでの処理開始")
            print("🚨   追加前の通知履歴数: \(self.notifications.count)")
            
            // 🛡️ 厳格な重複チェック（同じタイトル・本文・FCMフラグ・5秒以内）
            let isDuplicate = self.notifications.contains { existing in
                existing.title == entry.title &&
                existing.body == entry.body &&
                existing.isFromFCM == entry.isFromFCM &&
                abs(existing.receivedAt.timeIntervalSinceNow) < 5.0
            }
            
            if isDuplicate {
                print("🚨 ⚠️ 重複通知を検出 - 追加をスキップ: '\(entry.title)'")
                print("🚨 === NotificationHistoryManager.addNotification 終了（重複） ===")
                print("")
                return
            }
            
            // 新しい通知を先頭に追加
            self.notifications.insert(entry, at: 0)
            print("🚨   追加後の通知履歴数: \(self.notifications.count)")
            
            // 最大件数を超えた場合は古い通知を削除
            if self.notifications.count > self.maxHistoryCount {
                let beforeCount = self.notifications.count
                self.notifications = Array(self.notifications.prefix(self.maxHistoryCount))
                print("🚨   最大件数超過により削除: \(beforeCount) -> \(self.notifications.count)")
            }
            
            // 現在の全履歴をダンプ
            print("🚨 === 現在の通知履歴一覧 (\(self.notifications.count)件) ===")
            for (index, notification) in self.notifications.enumerated() {
                print("🚨 [\(index)] '\(notification.displayTitle)' - FCM:\(notification.isFromFCM) - タイプ:\(notification.notificationType)")
            }
            print("🚨 === 通知履歴一覧終了 ===")
            
            self.saveHistory()
            print("🚨 履歴保存完了")
            print("📱 通知履歴追加: \(entry.displayTitle) - タイプ: \(entry.notificationType)")
            print("🚨 === NotificationHistoryManager.addNotification 終了 ===")
            print("")
        }
    }
    
    /// Firebase Cloud Messagingからの通知を追加（便利メソッド）
    func addFCMNotification(
        title: String,
        body: String,
        userInfo: [AnyHashable: Any],
        wasTapped: Bool = false
    ) {
        print("🔥 === NotificationHistoryManager.addFCMNotification 開始 ===")
        print("🔥 FCM通知追加リクエスト:")
        print("🔥   title: '\(title)'")
        print("🔥   body: '\(body)'")
        print("🔥   wasTapped: \(wasTapped)")
        print("🔥   userInfo: \(userInfo)")
        
        // FCMから通知タイプを推定
        let notificationType = userInfo["type"] as? String ?? "fcm_notification"
        print("🔥   推定された通知タイプ: '\(notificationType)'")
        
        addNotification(
            title: title,
            body: body,
            notificationType: notificationType,
            userInfo: userInfo,
            isFromFCM: true,
            wasTapped: wasTapped
        )
        
        print("🔥 === NotificationHistoryManager.addFCMNotification 終了 ===")
        print("")
    }
    
    /// 重複通知を手動で削除
    func removeDuplicates() {
        removeDuplicateNotifications()
    }
    
    /// 通知履歴をクリア
    func clearHistory() {
        print("🗑️ === NotificationHistoryManager.clearHistory 開始 ===")
        print("🗑️ クリア前の履歴数: \(notifications.count)")
        
        DispatchQueue.main.async {
            self.notifications.removeAll()
            self.saveHistory()
            print("🗑️ クリア後の履歴数: \(self.notifications.count)")
            print("📱 通知履歴をクリアしました")
            print("🗑️ === NotificationHistoryManager.clearHistory 終了 ===")
            print("")
        }
    }
    
    // MARK: - Private Methods
    
    /// 履歴をUserDefaultsから読み込み
    private func loadHistory() {
        print("💾 === NotificationHistoryManager.loadHistory 開始 ===")
        print("💾 UserDefaultsキー: \(userDefaultsKey)")
        
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else {
            print("💾 通知履歴データなし - 緊急履歴をチェック")
            notifications = []
            
            // 🚨 緊急履歴を読み込んで通常の履歴に復旧
            loadEmergencyHistoryAsBackup()
            
            print("💾 === NotificationHistoryManager.loadHistory 終了 ===")
            print("")
            return
        }
        
        print("💾 データサイズ: \(data.count) bytes")
        
        do {
            let decoder = JSONDecoder()
            notifications = try decoder.decode([NotificationHistoryEntry].self, from: data)
            print("💾 通知履歴読み込み成功: \(notifications.count)件")
            
            print("💾 === 読み込まれた履歴一覧 ===")
            for (index, notification) in notifications.enumerated() {
                print("💾 [\(index)] '\(notification.displayTitle)' - FCM:\(notification.isFromFCM) - タイプ:\(notification.notificationType)")
            }
            print("💾 === 読み込み履歴一覧終了 ===")
        } catch {
            print("❌ 通知履歴読み込みエラー: \(error)")
            notifications = []
            
            // 🚨 エラー時は緊急履歴を読み込んで復旧
            loadEmergencyHistoryAsBackup()
        }
        
        // 🚨 緊急履歴もチェックして統合
        mergeEmergencyHistory()
        
        print("💾 === NotificationHistoryManager.loadHistory 終了 ===")
        
        // 読み込み後に重複削除を実行
        removeDuplicateNotifications()
        
        print("")
    }
    
    /// 重複した通知を削除する
    private func removeDuplicateNotifications() {
        print("🧹 === 重複通知削除開始 ===")
        print("🧹 削除前の履歴数: \(notifications.count)")
        
        var uniqueNotifications: [NotificationHistoryEntry] = []
        var seenNotifications: Set<String> = []
        
        for notification in notifications {
            // ユニーク識別子：タイトル+本文+FCMフラグ+受信時刻（分単位）
            let dateMinute = Calendar.current.dateInterval(of: .minute, for: notification.receivedAt)?.start ?? notification.receivedAt
            let uniqueKey = "\(notification.title)|\(notification.body)|\(notification.isFromFCM)|\(dateMinute.timeIntervalSince1970)"
            
            if !seenNotifications.contains(uniqueKey) {
                seenNotifications.insert(uniqueKey)
                uniqueNotifications.append(notification)
            } else {
                print("🧹 重複削除: '\(notification.title)' - タイプ:\(notification.notificationType)")
            }
        }
        
        if notifications.count != uniqueNotifications.count {
            notifications = uniqueNotifications
            saveHistory()
            print("🧹 重複削除完了: \(notifications.count != uniqueNotifications.count ? "\(notifications.count - uniqueNotifications.count)件削除" : "重複なし")")
        } else {
            print("🧹 重複なし")
        }
        
        print("🧹 削除後の履歴数: \(notifications.count)")
        print("🧹 === 重複通知削除終了 ===")
        print("")
    }
    
    /// 🚨 緊急履歴を通常の履歴に復旧する
    private func loadEmergencyHistoryAsBackup() {
        print("🚨 === 緊急履歴からの復旧開始 ===")
        
        let emergencyKey = "emergency_notification_history"
        guard let emergencyHistory = UserDefaults.standard.array(forKey: emergencyKey) as? [[String: Any]] else {
            print("🚨 緊急履歴なし")
            print("🚨 === 緊急履歴からの復旧終了 ===")
            return
        }
        
        print("🚨 緊急履歴発見: \(emergencyHistory.count)件")
        
        var recoveredNotifications: [NotificationHistoryEntry] = []
        
        for emergencyEntry in emergencyHistory {
            if let title = emergencyEntry["title"] as? String,
               let body = emergencyEntry["body"] as? String,
               let notificationType = emergencyEntry["notificationType"] as? String,
               let isFromFCM = emergencyEntry["isFromFCM"] as? Bool,
               let wasTapped = emergencyEntry["wasTapped"] as? Bool,
               let _ = emergencyEntry["receivedAt"] as? TimeInterval,
               let userInfo = emergencyEntry["userInfo"] as? [AnyHashable: Any] {
                
                let recoveredEntry = NotificationHistoryEntry(
                    title: title,
                    body: body,
                    notificationType: notificationType,
                    userInfo: userInfo,
                    isFromFCM: isFromFCM,
                    wasTapped: wasTapped
                )
                
                recoveredNotifications.append(recoveredEntry)
                print("🚨 復旧: '\(title)' - FCM:\(isFromFCM)")
            }
        }
        
        self.notifications = recoveredNotifications
        
        print("🚨 復旧完了: \(recoveredNotifications.count)件")
        print("🚨 === 緊急履歴からの復旧終了 ===")
        
        // 復旧した履歴を正式に保存
        if !recoveredNotifications.isEmpty {
            saveHistory()
        }
    }
    
    /// 🚨 緊急履歴と通常履歴を統合
    private func mergeEmergencyHistory() {
        print("🚨 === 緊急履歴統合開始 ===")
        
        let emergencyKey = "emergency_notification_history"
        guard let emergencyHistory = UserDefaults.standard.array(forKey: emergencyKey) as? [[String: Any]],
              !emergencyHistory.isEmpty else {
            print("🚨 統合すべき緊急履歴なし")
            print("🚨 === 緊急履歴統合終了 ===")
            return
        }
        
        print("🚨 緊急履歴統合: \(emergencyHistory.count)件")
        
        var mergedNotifications = notifications
        
        for emergencyEntry in emergencyHistory {
            if let title = emergencyEntry["title"] as? String,
               let body = emergencyEntry["body"] as? String,
               let notificationType = emergencyEntry["notificationType"] as? String,
               let isFromFCM = emergencyEntry["isFromFCM"] as? Bool,
               let wasTapped = emergencyEntry["wasTapped"] as? Bool,
               let _ = emergencyEntry["receivedAt"] as? TimeInterval,
               let userInfo = emergencyEntry["userInfo"] as? [AnyHashable: Any] {
                
                let mergedEntry = NotificationHistoryEntry(
                    title: title,
                    body: body,
                    notificationType: notificationType,
                    userInfo: userInfo,
                    isFromFCM: isFromFCM,
                    wasTapped: wasTapped
                )
                
                // 重複チェック（タイトルで判定）
                let isDuplicate = mergedNotifications.contains { existing in
                    existing.title == title
                }
                
                if !isDuplicate {
                    mergedNotifications.append(mergedEntry)
                    print("🚨 統合追加: '\(title)' - FCM:\(isFromFCM)")
                }
            }
        }
        
        // 受信日時でソート（新しい順）
        mergedNotifications.sort { $0.receivedAt > $1.receivedAt }
        
        // 最大件数に制限
        if mergedNotifications.count > maxHistoryCount {
            mergedNotifications = Array(mergedNotifications.prefix(maxHistoryCount))
        }
        
        self.notifications = mergedNotifications
        
        print("🚨 統合完了: 最終履歴数=\(notifications.count)件")
        print("🚨 === 緊急履歴統合終了 ===")
        
        // 統合結果を保存
        saveHistory()
        
        // 緊急履歴をクリア（統合済みのため）
        UserDefaults.standard.removeObject(forKey: emergencyKey)
    }
    
    /// 履歴をUserDefaultsに保存
    private func saveHistory() {
        print("💾 === NotificationHistoryManager.saveHistory 開始 ===")
        print("💾 保存する履歴数: \(notifications.count)")
        
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(notifications)
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
            print("💾 エンコード後のデータサイズ: \(data.count) bytes")
            print("📱 通知履歴保存成功: \(notifications.count)件")
            
            print("💾 === 保存された履歴一覧 ===")
            for (index, notification) in notifications.enumerated() {
                print("💾 [\(index)] '\(notification.displayTitle)' - FCM:\(notification.isFromFCM) - タイプ:\(notification.notificationType)")
            }
            print("💾 === 保存履歴一覧終了 ===")
        } catch {
            print("❌ 通知履歴保存エラー: \(error)")
        }
        
        print("💾 === NotificationHistoryManager.saveHistory 終了 ===")
        print("")
    }
}

// MARK: - Push Notification Settings View

/// プッシュ通知設定画面
struct PushNotificationSettingsView: View {
    // MARK: - Environment Objects
    @EnvironmentObject private var firebaseService: FirebaseService
    @Environment(\.dismiss) private var dismiss
    
    // MARK: - State Properties
    @State private var isNotificationEnabled = false
    @State private var isLoading = false
    @State private var showingPermissionAlert = false
    @State private var showingNotificationHistory = false
    @State private var fcmToken: String?
    @State private var apnsToken: String?
    @State private var notificationSettings: UNNotificationSettings?
    
    // 通知カテゴリ設定
    @State private var enableNewEventNotifications = true
    @State private var enableEventUpdateNotifications = true
    @State private var enableBackupReminders = true
    @State private var enableMemoDeadlineReminders = true
    
    // MARK: - Body
    
    var body: some View {
        NavigationView {
            Form {
                // 通知許可設定セクション
                notificationPermissionSection
                
                // 通知カテゴリ設定セクション
                if isNotificationEnabled {
                    notificationCategoriesSection
                }
                
                // トークン情報セクション（デバッグ用）
                if isNotificationEnabled {
                    tokenInformationSection
                }
                
                // 操作セクション
                actionSection
            }
            .navigationTitle("プッシュ通知設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                loadNotificationSettings()
            }
            .alert("通知許可が必要", isPresented: $showingPermissionAlert) {
                Button("設定を開く") {
                    openAppSettings()
                }
                Button("キャンセル", role: .cancel) { }
            } message: {
                Text("プッシュ通知を受け取るには、設定アプリでこのアプリの通知を許可してください。")
            }
        }
    }
    
    // MARK: - View Components
    
    /// 通知許可設定セクション
    private var notificationPermissionSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: notificationStatusIcon)
                        .foregroundColor(notificationStatusColor)
                    Text("プッシュ通知")
                        .fontWeight(.medium)
                    Spacer()
                    Text(notificationStatusText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if !isNotificationEnabled {
                    Text("新しいイベントやリマインダーの通知を受け取ることができます")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
            }
            
            if !isNotificationEnabled {
                Button("通知を許可する") {
                    requestNotificationPermission()
                }
                .foregroundColor(.blue)
                .disabled(isLoading)
            }
            
            if isNotificationEnabled {
                Button("通知設定を管理") {
                    openAppSettings()
                }
                .foregroundColor(.blue)
            }
        } header: {
            Text("通知許可")
        } footer: {
            if isNotificationEnabled {
                Text("通知はiOS設定アプリからも管理できます")
            } else {
                Text("通知を許可すると、新しいイベントやリマインダーを受け取れます")
            }
        }
    }
    
    /// 通知カテゴリ設定セクション
    private var notificationCategoriesSection: some View {
        Section {
            Toggle("新しいイベント", isOn: $enableNewEventNotifications)
                .onChange(of: enableNewEventNotifications) {
                    saveNotificationPreferences()
                }
            
            Toggle("イベント更新", isOn: $enableEventUpdateNotifications)
                .onChange(of: enableEventUpdateNotifications) {
                    saveNotificationPreferences()
                }
            
            Toggle("バックアップリマインダー", isOn: $enableBackupReminders)
                .onChange(of: enableBackupReminders) {
                    saveNotificationPreferences()
                }
            
            Toggle("メモ期日リマインダー", isOn: $enableMemoDeadlineReminders)
                .onChange(of: enableMemoDeadlineReminders) {
                    saveNotificationPreferences()
                }
        } header: {
            Text("通知の種類")
        } footer: {
            Text("受け取りたい通知の種類を選択してください")
        }
    }
    
    /// トークン情報セクション
    private var tokenInformationSection: some View {
        Section {
            if let fcm = fcmToken {
                VStack(alignment: .leading, spacing: 4) {
                    Text("FCM トークン")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(fcm)
                        .font(.caption)
                        .foregroundColor(.primary)
                        .textSelection(.enabled)
                }
                .padding(.vertical, 4)
            }
            
            if let apns = apnsToken {
                VStack(alignment: .leading, spacing: 4) {
                    Text("APNS トークン")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(apns)
                        .font(.caption)
                        .foregroundColor(.primary)
                        .textSelection(.enabled)
                }
                .padding(.vertical, 4)
            }
            
            Button("トークンを更新") {
                refreshTokens()
            }
            .foregroundColor(.blue)
            .disabled(isLoading)
        } header: {
            Text("技術情報")
        } footer: {
            Text("デバッグ用のトークン情報です")
        }
    }
    
    /// 操作セクション
    private var actionSection: some View {
        Section {
            Button("設定を再読み込み") {
                loadNotificationSettings()
            }
            .foregroundColor(.blue)
            .disabled(isLoading)
            
            Button("通知履歴を見る") {
                showingNotificationHistory = true
            }
            .foregroundColor(.purple)
            
            Button("🧹重複通知削除") {
                NotificationHistoryManager.shared.removeDuplicates()
            }
            .foregroundColor(.orange)
            
            if isNotificationEnabled {
                Button("テスト通知を送信") {
                    sendTestNotification()
                }
                .foregroundColor(.green)
                .disabled(isLoading)
            }
        } footer: {
            Text("設定に問題がある場合は再読み込みをお試しください")
        }
        .sheet(isPresented: $showingNotificationHistory) {
            SimpleNotificationHistoryView()
        }
    }
    
    // MARK: - Computed Properties
    
    private var notificationStatusIcon: String {
        if isLoading {
            return "hourglass"
        }
        return isNotificationEnabled ? "bell.fill" : "bell.slash"
    }
    
    private var notificationStatusColor: Color {
        isNotificationEnabled ? .green : .orange
    }
    
    private var notificationStatusText: String {
        if isLoading {
            return "確認中..."
        }
        return isNotificationEnabled ? "許可" : "未許可"
    }
    
    // MARK: - Methods
    
    /// 通知設定を読み込み
    private func loadNotificationSettings() {
        print("🔔 プッシュ通知設定を読み込み開始")
        isLoading = true
        
        // 現在の通知設定を取得
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.notificationSettings = settings
                self.isNotificationEnabled = settings.authorizationStatus == .authorized
                
                // 保存された通知設定を読み込み
                self.loadNotificationPreferences()
                
                // トークン情報を読み込み
                self.loadTokens()
                
                self.isLoading = false
                print("✅ プッシュ通知設定読み込み完了: \(self.isNotificationEnabled ? "許可" : "未許可")")
            }
        }
    }
    
    /// 保存された通知設定を読み込み
    private func loadNotificationPreferences() {
        enableNewEventNotifications = UserDefaults.standard.bool(forKey: "enable_new_event_notifications") 
        enableEventUpdateNotifications = UserDefaults.standard.bool(forKey: "enable_event_update_notifications")
        enableBackupReminders = UserDefaults.standard.bool(forKey: "enable_backup_reminders")
        enableMemoDeadlineReminders = UserDefaults.standard.bool(forKey: "enable_memo_deadline_reminders")
        
        // 初回起動時はデフォルトでtrueに設定
        if UserDefaults.standard.object(forKey: "enable_new_event_notifications") == nil {
            enableNewEventNotifications = true
            enableEventUpdateNotifications = true
            enableBackupReminders = true
            enableMemoDeadlineReminders = true
            saveNotificationPreferences()
        }
    }
    
    /// 通知設定を保存
    private func saveNotificationPreferences() {
        UserDefaults.standard.set(enableNewEventNotifications, forKey: "enable_new_event_notifications")
        UserDefaults.standard.set(enableEventUpdateNotifications, forKey: "enable_event_update_notifications")
        UserDefaults.standard.set(enableBackupReminders, forKey: "enable_backup_reminders")
        UserDefaults.standard.set(enableMemoDeadlineReminders, forKey: "enable_memo_deadline_reminders")
        
        print("💾 通知設定を保存: 新イベント=\(enableNewEventNotifications), 更新=\(enableEventUpdateNotifications)")
    }
    
    /// トークン情報を読み込み
    private func loadTokens() {
        fcmToken = AppDelegate.getFCMToken()
        apnsToken = AppDelegate.getAPNsToken()
    }
    
    /// 通知許可を要求
    private func requestNotificationPermission() {
        print("🔔 通知許可を要求")
        isLoading = true
        
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            DispatchQueue.main.async {
                self.isLoading = false
                
                if granted {
                    print("✅ 通知許可が承認されました")
                    UIApplication.shared.registerForRemoteNotifications()
                    self.loadNotificationSettings()
                } else {
                    print("❌ 通知許可が拒否されました: \(error?.localizedDescription ?? "不明なエラー")")
                    self.showingPermissionAlert = true
                }
            }
        }
    }
    
    /// トークンを更新
    private func refreshTokens() {
        print("🔄 トークンを更新")
        isLoading = true
        
        // Firebase Cloud Messaging トークンを再取得
        Messaging.messaging().token { token, error in
            DispatchQueue.main.async {
                self.isLoading = false
                
                if let error = error {
                    print("❌ FCMトークン更新エラー: \(error)")
                } else if let token = token {
                    print("✅ FCMトークン更新成功: \(token)")
                    UserDefaults.standard.set(token, forKey: "fcm_token")
                    self.fcmToken = token
                    
                    // FirestoreにFCMトークンを保存
                    self.firebaseService.updateFCMToken(token: token)
                }
            }
        }
    }
    
    /// テスト通知を送信
    private func sendTestNotification() {
        print("🧪 テスト通知を送信")
        
        let content = UNMutableNotificationContent()
        content.title = "MemoHero テスト通知"
        content.body = "プッシュ通知が正常に動作しています！"
        content.sound = .default
        content.userInfo = [
            "type": "test_notification",
            "test_data": "テストデータ",
            "timestamp": String(Int(Date().timeIntervalSince1970))
        ]
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "test_notification", content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ テスト通知送信エラー: \(error)")
                } else {
                    print("✅ テスト通知送信完了")
                    
                    // テスト通知を履歴に追加（送信時）
                    NotificationHistoryManager.shared.addNotification(
                        title: content.title,
                        body: content.body,
                        notificationType: "test_notification",
                        userInfo: content.userInfo,
                        isFromFCM: false,
                        wasTapped: false
                    )
                    print("📝 テスト通知を送信時履歴に追加")
                    
                    // 🚨 追加: FCMテスト通知もシミュレート
                    simulateFCMNotification()
                }
            }
        }
    }
    
    /// 🚨 FCM通知をシミュレートしてテスト
    private func simulateFCMNotification() {
        print("🧪 === FCM通知シミュレート開始 ===")
        
        let simulatedFCMData: [AnyHashable: Any] = [
            "aps": [
                "alert": [
                    "title": "🚨テストFCM通知",
                    "body": "新しいイベントが追加されました（テスト）"
                ]
            ],
            "type": "new_event",
            "gcm.message_id": "test_message_id_\(Date().timeIntervalSince1970)"
        ]
        
        // NotificationHistoryManagerに直接追加
        NotificationHistoryManager.shared.addFCMNotification(
            title: "🚨テストFCM通知",
            body: "新しいイベントが追加されました（テスト）",
            userInfo: simulatedFCMData,
            wasTapped: false
        )
        
        print("🧪 FCM通知シミュレート完了")
        print("🧪 === FCM通知シミュレート終了 ===")
    }
    
    /// アプリの設定画面を開く
    private func openAppSettings() {
        if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsURL)
        }
    }
}

// MARK: - Push Notification Preferences Manager

/// プッシュ通知設定管理クラス
class PushNotificationPreferences {
    
    /// 新しいイベント通知が有効かどうか
    static var isNewEventNotificationEnabled: Bool {
        return UserDefaults.standard.bool(forKey: "enable_new_event_notifications")
    }
    
    /// イベント更新通知が有効かどうか
    static var isEventUpdateNotificationEnabled: Bool {
        return UserDefaults.standard.bool(forKey: "enable_event_update_notifications")
    }
    
    /// バックアップリマインダーが有効かどうか
    static var isBackupReminderEnabled: Bool {
        return UserDefaults.standard.bool(forKey: "enable_backup_reminders")
    }
    
    /// メモ期日リマインダーが有効かどうか
    static var isMemoDeadlineReminderEnabled: Bool {
        return UserDefaults.standard.bool(forKey: "enable_memo_deadline_reminders")
    }
    
    /// 全ての通知設定を取得
    static func getAllPreferences() -> [String: Bool] {
        return [
            "new_event": isNewEventNotificationEnabled,
            "event_update": isEventUpdateNotificationEnabled,
            "backup_reminder": isBackupReminderEnabled,
            "memo_deadline_reminder": isMemoDeadlineReminderEnabled
        ]
    }
}

// MARK: - Preview

// MARK: - Simple Notification History View

/// 簡単な通知履歴ビュー
struct SimpleNotificationHistoryView: View {
    @StateObject private var historyManager = {
        print("🎬 === SimpleNotificationHistoryView @StateObject 初期化 ===")
        let manager = NotificationHistoryManager.shared
        print("🎬 取得したmanagerの履歴件数: \(manager.notifications.count)")
        print("🎬 === @StateObject 初期化終了 ===")
        print("")
        return manager
    }()
    @Environment(\.dismiss) private var dismiss
    @State private var showingClearConfirmation = false
    @State private var showingEventList = false
    
    var body: some View {
        print("📺 === SimpleNotificationHistoryView.body 描画開始 ===")
        print("📺 historyManager.notifications.count: \(historyManager.notifications.count)")
        print("📺 historyManager.notifications.isEmpty: \(historyManager.notifications.isEmpty)")
        
        // UserDefaultsから直接読み込んで確認
        if let savedData = UserDefaults.standard.array(forKey: "notification_history") as? [[String: Any]] {
            print("📺 UserDefaults通常キーから読み込み: \(savedData.count)件")
            for (index, item) in savedData.enumerated() {
                print("📺   UserDefaults[\(index)]: title='\(item["title"] ?? "nil")', FCM=\(item["isFromFCM"] ?? false)")
            }
        } else {
            print("📺 UserDefaults通常キー: データなし")
        }
        
        // 緊急キーからも確認
        if let emergencyData = UserDefaults.standard.array(forKey: "emergency_notification_history") as? [[String: Any]] {
            print("📺 UserDefaults緊急キーから読み込み: \(emergencyData.count)件")
            for (index, item) in emergencyData.enumerated() {
                print("📺   緊急[\(index)]: title='\(item["title"] ?? "nil")', type='\(item["notificationType"] ?? "nil")'")
            }
        } else {
            print("📺 UserDefaults緊急キー: データなし")
        }
        
        if !historyManager.notifications.isEmpty {
            print("📺 === 表示する通知履歴詳細 ===")
            for (index, notification) in historyManager.notifications.enumerated() {
                print("📺 [\(index)] タイトル: '\(notification.displayTitle)'")
                print("📺      本文: '\(notification.body)'")
                print("📺      FCM: \(notification.isFromFCM)")
                print("📺      タイプ: '\(notification.notificationType)'")
                print("📺      新しいイベント含む: \(notification.containsNewEventText)")
                print("📺      タップ済み: \(notification.wasTapped)")
                print("📺      受信時刻: \(notification.receivedAt)")
                print("📺      ID: \(notification.id)")
            }
            print("📺 === 表示通知履歴詳細終了 ===")
        } else {
            print("📺 ⚠️ 履歴が空です")
        }
        
        return NavigationView {
            Group {
                if historyManager.notifications.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "bell.slash")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)
                        
                        Text("通知履歴がありません")
                            .font(.title2)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                        
                        Text("プッシュ通知を受信すると、ここに履歴が表示されます")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        Section("\(historyManager.notifications.count)件の通知") {
                            ForEach(historyManager.notifications) { notification in
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text(notification.displayTitle)
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                        
                                        Spacer()
                                        
                                        if notification.isFromFCM {
                                            Text("FCM")
                                                .font(.caption2)
                                                .fontWeight(.medium)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.blue.opacity(0.1))
                                                .foregroundColor(.blue)
                                                .cornerRadius(4)
                                        }
                                    }
                                    
                                    if !notification.body.isEmpty {
                                        Text(notification.body)
                                            .font(.body)
                                            .foregroundColor(.secondary)
                                            .lineLimit(3)
                                    }
                                    
                                    HStack {
                                        Text(notification.displayTime)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        
                                        Spacer()
                                        
                                        if notification.wasTapped {
                                            HStack(spacing: 4) {
                                                Image(systemName: "hand.tap")
                                                Text("タップ済み")
                                            }
                                            .font(.caption)
                                            .foregroundColor(.green)
                                        }
                                        
                                        // 「新しいイベント」が含まれている場合は矢印を表示
                                        if notification.containsNewEventText {
                                            Image(systemName: "chevron.right")
                                                .font(.caption)
                                                .foregroundColor(.blue)
                                        }
                                    }
                                }
                                .frame(minHeight: 60)
                                .padding(.vertical, 4)
                                .contentShape(Rectangle()) // 全体をタップ可能にする
                                .onTapGesture {
                                    handleNotificationTap(notification)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("通知履歴")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
                
                if !historyManager.notifications.isEmpty {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("クリア") {
                            showingClearConfirmation = true
                        }
                        .foregroundColor(.red)
                    }
                }
            }
            .alert("履歴をクリア", isPresented: $showingClearConfirmation) {
                Button("キャンセル", role: .cancel) { }
                Button("クリア", role: .destructive) {
                    historyManager.clearHistory()
                }
            } message: {
                Text("すべての通知履歴を削除しますか？")
            }
            .sheet(isPresented: $showingEventList) {
                EventListView()
                    .environmentObject(FirebaseService.shared)
            }
        }
    }
    
    /// 通知履歴のタップを処理
    private func handleNotificationTap(_ notification: NotificationHistoryEntry) {
        print("📱 通知履歴がタップされました: \(notification.displayTitle)")
        print("📱 通知本文: \(notification.body)")
        print("📱 「新しいイベント」含有: \(notification.containsNewEventText)")
        
        if notification.containsNewEventText {
            print("🎯 「新しいイベント」を含む通知がタップ - イベント一覧を表示")
            showingEventList = true
        } else {
            print("ℹ️ 「新しいイベント」を含まない通知 - 何も実行しない")
        }
    }
}

#Preview {
    PushNotificationSettingsView()
        .environmentObject(FirebaseService.shared)
}
