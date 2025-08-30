import SwiftUI
import UIKit
import UserNotifications
import FirebaseCore
import FirebaseMessaging
import FirebaseFirestore

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {
    
    // MARK: - Application Lifecycle
    
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        
        // Firebase初期化
        FirebaseApp.configure()
        
        // プッシュ通知登録
        registerPushNotifications()
        
        // FCM設定
        setupFirebaseMessaging()
        
        // 起動時にFCMトークンを強制取得してログ出力
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.logCurrentFCMToken()
        }
        
        return true
    }
    
    // MARK: - Push Notifications Setup
    
    private func registerPushNotifications() {
        print("🔔 プッシュ通知の登録を開始")
        
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        
        center.requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, error in
            DispatchQueue.main.async {
                if granted {
                    print("✅ プッシュ通知が許可されました")
                    UIApplication.shared.registerForRemoteNotifications()
                    self?.updateNotificationSettings(enabled: true)
                } else {
                    print("❌ プッシュ通知が拒否されました: \(error?.localizedDescription ?? "不明なエラー")")
                    self?.updateNotificationSettings(enabled: false)
                }
            }
        }
    }
    
    private func setupFirebaseMessaging() {
        print("🔧 Firebase Messaging設定開始")
        Messaging.messaging().delegate = self
        
        // FCMトークンの即座取得
        print("📲 FCMトークン取得中...")
        Messaging.messaging().token { token, error in
            if let error = error {
                print("❌ FCMトークンの取得に失敗: \(error)")
            } else if let token = token {
                print("FCMToken: \(String(describing: token))")
                print("✅ FCMトークン取得成功")
                print("📝 トークンをUserDefaultsに保存")
                // トークンをUserDefaultsに保存
                UserDefaults.standard.set(token, forKey: "fcm_token")
            } else {
                print("⚠️ FCMトークンがnilです")
            }
        }
    }
    
    // MARK: - APNs Device Token
    
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        print("✅ APNsデバイストークン: \(token)")
        
        // FCMにAPNsトークンを設定
        Messaging.messaging().apnsToken = deviceToken
        
        // トークンをUserDefaultsに保存
        UserDefaults.standard.set(token, forKey: "apns_token")
    }
    
    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("❌ リモート通知の登録に失敗: \(error)")
        updateNotificationSettings(enabled: false)
    }
    
    // MARK: - UNUserNotificationCenterDelegate
    
    // アプリがフォアグラウンドにある時の通知表示
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo
        let title = notification.request.content.title
        let body = notification.request.content.body
        let notificationId = notification.request.identifier
        
        print("=== FCM通知デバッグ開始 ===")
        print("Receive: \(userInfo)")
        print("🔔 フォアグラウンドで通知受信: \(title) (ID: \(notificationId))")
        print("📋 userInfoのキー一覧: \(Array(userInfo.keys).map(String.init(describing:)))")
        
        // 通知履歴に記録（重複を防ぐため1つのメソッドのみ使用）
        recordNotificationInHistory(
            title: title,
            body: body,
            notificationId: notificationId,
            userInfo: userInfo,
            wasTapped: false
        )
        print("=== FCM通知デバッグ終了 ===")
        print("")
        
        // FCMリモートメッセージの処理（フォアグラウンドでも実行）
        handleRemoteMessage(userInfo)
        
        // iOS 14以降での通知表示オプション（バッジなし）
        completionHandler([.banner, .sound])
    }
    
    // 通知をタップした時の処理
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let title = response.notification.request.content.title
        let body = response.notification.request.content.body
        let notificationId = response.notification.request.identifier
        let actionId = response.actionIdentifier
        
        print("=== FCM通知タップデバッグ開始 ===")
        print("Tap: \(userInfo)")
        print("🔔 通知タップ処理: \(title) (ID: \(notificationId), Action: \(actionId))")
        print("📋 userInfoのキー一覧: \(Array(userInfo.keys).map(String.init(describing:)))")
        
        // 通知履歴に記録（重複を防ぐため1つのメソッドのみ使用）
        recordNotificationInHistory(
            title: title,
            body: body,
            notificationId: notificationId,
            userInfo: userInfo,
            wasTapped: true
        )
        print("=== FCM通知タップデバッグ終了 ===")
        print("")
        
        // ローカル通知（期日通知）の場合の特別処理
        handleLocalNotificationTap(
            notificationId: notificationId,
            actionId: actionId,
            userInfo: userInfo
        )
        
        // FCMリモートメッセージの処理
        handleRemoteMessage(userInfo)
        
        // 通知タップの処理
        handleNotificationTap(userInfo: userInfo)
        
        completionHandler()
    }
    
    // MARK: - MessagingDelegate
    
    // FCMトークンが更新された時
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        print("FCMToken: \(String(describing: fcmToken))")
        print("🔄 FCMトークンが更新されました: \(fcmToken ?? "nil")")
        
        if let token = fcmToken {
            UserDefaults.standard.set(token, forKey: "fcm_token")
            
            // サーバーにトークンを送信する処理をここに追加
            sendTokenToServer(token: token)
        }
    }
    
    // MARK: - Remote Message Handling
    
    /// バックグラウンドでのFCM通知処理（サイレント通知対応）
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        print("=== バックグラウンドFCM通知デバッグ開始 ===")
        print("🔔 バックグラウンドでリモート通知受信: \(userInfo)")
        print("📋 userInfoのキー一覧: \(Array(userInfo.keys).map(String.init(describing:)))")
        
        // タイトルと本文を抽出
        var title = ""
        var body = ""
        if let aps = userInfo["aps"] as? [String: Any] {
            if let alert = aps["alert"] as? [String: Any] {
                title = alert["title"] as? String ?? ""
                body = alert["body"] as? String ?? ""
            } else if let alertString = aps["alert"] as? String {
                body = alertString
            }
        }
        
        // バックグラウンド通知を記録（タイトル・本文がある場合のみ）
        if !title.isEmpty || !body.isEmpty {
            recordNotificationInHistory(
                title: title.isEmpty ? "バックグラウンド通知" : title,
                body: body.isEmpty ? "サイレント通知" : body,
                notificationId: "background_fcm_\(Date().timeIntervalSince1970)",
                userInfo: userInfo,
                wasTapped: false
            )
        }
        
        // FirebaseServiceに処理を委譲
        FirebaseService.shared.handleRemoteNotification(userInfo)
        
        print("=== バックグラウンドFCM通知デバッグ終了 ===")
        print("")
        
        // 処理完了を通知
        completionHandler(.newData)
    }
    
    // MARK: - Private Methods
    
    /// 通知を履歴に記録する統一メソッド
    /// - Parameters:
    ///   - title: 通知のタイトル
    ///   - body: 通知の本文
    ///   - notificationId: 通知のID
    ///   - userInfo: 通知のユーザー情報
    ///   - wasTapped: タップされたかどうか
    private func recordNotificationInHistory(
        title: String,
        body: String,
        notificationId: String,
        userInfo: [AnyHashable: Any],
        wasTapped: Bool
    ) {
        // 通知タイプを判定
        var notificationType = "unknown"
        var isFromFCM = false
        
        // FCM通知かローカル通知かを判定（複数の判定方法で確実にFCMを検出）
        if userInfo["gcm.message_id"] != nil ||
           userInfo["google.c.sender.id"] != nil ||
           userInfo["google.c.a.e"] != nil ||
           userInfo["from"] != nil ||
           userInfo["collapse_key"] != nil {
            // 標準的なFCM判定条件
            isFromFCM = true
            notificationType = userInfo["type"] as? String ?? "fcm_notification"
            print("🔥 FCM通知として検出: userInfo keys = \(userInfo.keys.map { String(describing: $0) })")
        } else if let aps = userInfo["aps"] as? [String: Any],
                  aps["alert"] != nil,
                  !notificationId.hasPrefix("memo_") && !notificationId.hasPrefix("test_") {
            // APS経由のFCM通知（ローカル通知でない場合）
            isFromFCM = true
            notificationType = userInfo["type"] as? String ?? "fcm_notification"
            print("🔥 APS経由FCM通知として検出: userInfo keys = \(userInfo.keys.map { String(describing: $0) })")
        } else if notificationId.hasPrefix("memo_due_") {
            // メイン期日通知
            notificationType = "main"
        } else if notificationId.hasPrefix("memo_pre_") {
            // 予備期日通知
            notificationType = "preNotification"
        } else if notificationId == "test_notification" {
            // テスト通知
            notificationType = "test_notification"
        } else {
            // 判定できない場合は、明らかにローカル通知でない限りFCMとして扱う
            if !notificationId.hasPrefix("memo_") && !notificationId.hasPrefix("test_") {
                print("⚠️ 不明な通知をFCMとして扱います: ID=\(notificationId)")
                isFromFCM = true
                notificationType = "unknown_fcm"
            }
        }
        
        print("📝 通知履歴記録: \(title) - タイプ: \(notificationType), FCM: \(isFromFCM), タップ: \(wasTapped)")
        print("📝 userInfo詳細: \(userInfo)")
        print("📝 notificationId: \(notificationId)")
        
        // NotificationHistoryManagerに記録
        NotificationHistoryManager.shared.addNotification(
            title: title,
            body: body,
            notificationType: notificationType,
            userInfo: userInfo,
            isFromFCM: isFromFCM,
            wasTapped: wasTapped
        )
        
        // ローカル通知の場合はNotificationManagerの履歴にも記録
        if !isFromFCM, let memoIdString = userInfo["memoId"] as? String, let memoId = UUID(uuidString: memoIdString) {
            var localNotificationType: NotificationHistory.NotificationType?
            if notificationId.hasPrefix("memo_due_") {
                localNotificationType = .main
            } else if notificationId.hasPrefix("memo_pre_") {
                localNotificationType = .preNotification
            }
            
            if let type = localNotificationType {
                NotificationManager.shared.addNotificationHistory(
                    memoId: memoId,
                    memoTitle: body,
                    notificationType: type
                )
            }
        }
    }
    
    /// ローカル通知タップの処理
    /// - Parameters:
    ///   - notificationId: 通知ID
    ///   - actionId: アクションID
    ///   - userInfo: ユーザー情報
    private func handleLocalNotificationTap(
        notificationId: String,
        actionId: String,
        userInfo: [AnyHashable: Any]
    ) {
        // 期日通知の場合
        if notificationId.hasPrefix("memo_due_") || notificationId.hasPrefix("memo_pre_") {
            // メモIDを取得
            var memoId: UUID?
            
            if let memoIdString = userInfo["memoId"] as? String {
                memoId = UUID(uuidString: memoIdString)
            } else {
                // 通知IDからメモIDを抽出
                if notificationId.hasPrefix("memo_due_") {
                    let uuidString = String(notificationId.dropFirst("memo_due_".count))
                    memoId = UUID(uuidString: uuidString)
                } else if notificationId.hasPrefix("memo_pre_") {
                    let uuidString = String(notificationId.dropFirst("memo_pre_".count))
                    memoId = UUID(uuidString: uuidString)
                }
            }
            
            // アクションに応じて処理
            switch actionId {
            case "OPEN_MEMO_ACTION", UNNotificationDefaultActionIdentifier:
                // メモを開く
                if let memoId = memoId {
                    openMemoFromNotification(memoId: memoId)
                }
            case "COMPLETE_ACTION":
                // 完了処理（将来実装）
                print("📋 完了アクション実行")
            case "POSTPONE_ACTION":
                // 延期処理（将来実装）  
                print("⏰ 延期アクション実行")
            default:
                break
            }
        }
    }
    
    /// 通知からメモを開く
    /// - Parameter memoId: メモID
    private func openMemoFromNotification(memoId: UUID) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: NSNotification.Name("OpenMemoFromNotification"),
                object: nil,
                userInfo: ["memoId": memoId, "source": "notification_tap"]
            )
        }
    }
    
    /// 起動時にFCMトークンをログ出力
    private func logCurrentFCMToken() {
        print("🔍 起動時FCMトークン取得開始")
        
        // 現在のFCMトークンを取得
        Messaging.messaging().token { token, error in
            if let error = error {
                print("❌ 起動時FCMトークン取得失敗: \(error)")
            } else if let token = token {
                print("FCMToken: \(String(describing: token))")
                print("✅ 起動時FCMトークン取得成功")
                print("📱 トークン長: \(token.count) 文字")
            } else {
                print("⚠️ 起動時FCMトークンが取得できませんでした")
            }
        }
    }
    
    private func updateNotificationSettings(enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "push_notifications_enabled")
        
        // メイン画面に設定変更を通知
        NotificationCenter.default.post(
            name: NSNotification.Name("PushNotificationSettingsChanged"),
            object: nil,
            userInfo: ["enabled": enabled]
        )
    }
    
    private func sendTokenToServer(token: String) {
        // TODO: サーバーにFCMトークンを送信する処理
        // 現在はログ出力のみ
        print("📡 サーバーにFCMトークンを送信: \(token)")
        
        // Firebase Firestoreにトークンを保存する例
        // FirebaseService.shared.updateFCMToken(token: token)
    }
    
    private func handleNotificationTap(userInfo: [AnyHashable: Any]) {
        print("🔔 通知タップ処理開始")
        
        // 通知のタイプに応じた処理、または通知内容から推測
        var notificationType = userInfo["type"] as? String
        
        // 通知タイプが指定されていない場合、内容から推測
        if notificationType == nil {
            if let aps = userInfo["aps"] as? [String: Any],
               let alert = aps["alert"] as? [String: Any],
               let title = alert["title"] as? String {
                
                if title.contains("期日になりました") || title.contains("期日が近づいています") {
                    notificationType = "memo_deadline"
                } else if title.contains("新しいイベント") {
                    notificationType = "new_event"
                }
            }
        }
        
        if let notificationType = notificationType {
            switch notificationType {
            case "new_event":
                // 新しいイベント通知
                if let eventId = userInfo["event_id"] as? String {
                    print("📅 新しいイベント通知: \(eventId)")
                    // イベント詳細画面に遷移する処理
                    openEventDetail(eventId: eventId)
                }
                
            case "reminder":
                // リマインダー通知
                if let memoIdString = userInfo["memo_id"] as? String,
                   let memoId = UUID(uuidString: memoIdString) {
                    print("📝 メモリマインダー: \(memoId)")
                    // メモ編集画面に遷移する処理
                    openMemoFromNotification(memoId: memoId)
                }
                
            case "memo_deadline":
                // メモ期日通知（統合通知システム用）
                var memoId: UUID? = nil
                
                // 複数の方法でメモIDを取得
                if let memoIdString = userInfo["memo_id"] as? String {
                    memoId = UUID(uuidString: memoIdString)
                } else if let memoIdString = userInfo["memoId"] as? String {
                    memoId = UUID(uuidString: memoIdString)
                }
                
                if let memoId = memoId {
                    print("📝 メモ期日通知: \(memoId)")
                    // メモ編集画面に遷移する処理
                    openMemoFromNotification(memoId: memoId)
                } else {
                    print("⚠️ メモ期日通知: メモIDが見つかりません")
                }
                
            case "backup_reminder":
                // バックアップリマインダー
                print("💾 バックアップリマインダー")
                // バックアップ画面に遷移する処理
                openBackupSettings()
                
            default:
                print("🔔 不明な通知タイプ: \(notificationType)")
                
                // 通知タイプが不明でもmemo_idがある場合は、メモ通知として処理
                if let memoIdString = userInfo["memo_id"] as? String,
                   let memoId = UUID(uuidString: memoIdString) {
                    print("📝 タイプ不明のメモ通知: \(memoId)")
                    openMemoFromNotification(memoId: memoId)
                }
            }
        }
    }
    
    private func handleRemoteMessage(_ messageData: [AnyHashable: Any]) {
        print("=== handleRemoteMessageでのFCM処理開始 ===")
        print("🔔 リモートメッセージ処理: \(messageData)")
        print("📋 messageDataのキー一覧: \(Array(messageData.keys).map(String.init(describing:)))")
        
        // タイトルと本文を抽出
        var title = ""
        var body = ""
        if let aps = messageData["aps"] as? [String: Any] {
            if let alert = aps["alert"] as? [String: Any] {
                title = alert["title"] as? String ?? ""
                body = alert["body"] as? String ?? ""
            } else if let alertString = aps["alert"] as? String {
                body = alertString
            }
        }
        
        // リモートメッセージを記録（タイトル・本文がある場合のみ）
        if !title.isEmpty || !body.isEmpty {
            recordNotificationInHistory(
                title: title,
                body: body,
                notificationId: "remote_message_\(Date().timeIntervalSince1970)",
                userInfo: messageData,
                wasTapped: false
            )
        }
        
        // メッセージに応じた処理
        // 例：新しいイベント情報の同sync、アプリ内データの更新等
        
        // FirebaseServiceに処理を委譲
        FirebaseService.shared.handleRemoteNotification(messageData)
        
        print("=== handleRemoteMessageでのFCM処理終了 ===")
        print("")
    }
    
    /// FCM通知が確実に履歴に記録されるように保証する
    /// - Parameter messageData: FCMメッセージデータ
    private func ensureFCMNotificationIsRecorded(_ messageData: [AnyHashable: Any]) {
        print("🔔 FCM通知履歴記録確認開始")
        
        // APSペイロードから通知内容を取得
        var title = ""
        var body = ""
        
        if let aps = messageData["aps"] as? [String: Any] {
            if let alert = aps["alert"] as? [String: Any] {
                title = alert["title"] as? String ?? ""
                body = alert["body"] as? String ?? ""
            } else if let alertString = aps["alert"] as? String {
                body = alertString
            }
        }
        
        // タイトルやボディが直接メッセージデータに含まれている場合
        if title.isEmpty {
            title = messageData["title"] as? String ?? ""
        }
        if body.isEmpty {
            body = messageData["body"] as? String ?? ""
        }
        
        // 通知内容がある場合は強制的に履歴に記録
        if !title.isEmpty || !body.isEmpty {
            print("🔔 FCM通知を強制的に履歴に記録: \(title) - \(body)")
            
            NotificationHistoryManager.shared.addFCMNotification(
                title: title.isEmpty ? "FCM通知" : title,
                body: body,
                userInfo: messageData,
                wasTapped: false
            )
        } else {
            print("⚠️ FCM通知内容が空のため履歴記録をスキップ")
        }
    }
    
    /// 通知を問答無用で履歴に強制保存する（デバッグ用）
    /// - Parameters:
    ///   - title: 通知タイトル
    ///   - body: 通知本文
    ///   - notificationId: 通知ID
    ///   - userInfo: 通知のユーザー情報
    ///   - wasTapped: タップされたかどうか
    ///   - source: 呼び出し元
    private func forceSaveFCMNotificationToHistory(
        title: String,
        body: String,
        notificationId: String,
        userInfo: [AnyHashable: Any],
        wasTapped: Bool,
        source: String
    ) {
        print("🚨 強制FCM履歴保存開始 - 呼び出し元: \(source)")
        print("🚨 タイトル: '\(title)'")
        print("🚨 本文: '\(body)'")
        print("🚨 notificationId: '\(notificationId)'")
        print("🚨 userInfo全体: \(userInfo)")
        
        // タイトルまたは本文がある場合のみFCM通知として記録
        if !title.isEmpty || !body.isEmpty {
            NotificationHistoryManager.shared.addNotification(
                title: title,
                body: body,
                notificationType: "forced_fcm_\(source)",
                userInfo: userInfo,
                isFromFCM: true,
                wasTapped: wasTapped
            )
        }
        
        print("✅ 強制FCM履歴保存完了")
    }
    
    /// 🚨 緊急パッチ: NotificationHistoryManagerを迂回してUserDefaultsに直接保存
    /// - Parameters:
    ///   - title: 通知タイトル
    ///   - body: 通知本文
    ///   - notificationId: 通知ID
    ///   - userInfo: 通知のユーザー情報
    ///   - source: 呼び出し元
    private func emergencyDirectSaveToUserDefaults(
        title: String,
        body: String,
        notificationId: String,
        userInfo: [AnyHashable: Any],
        source: String
    ) {
        print("🚨🚨🚨 === 緊急パッチ: 直接UserDefaults保存開始 ===")
        print("🚨 呼び出し元: \(source)")
        print("🚨 タイトル: '\(title)'")
        print("🚨 本文: '\(body)'")
        print("🚨 通知ID: '\(notificationId)'")
        
        // タイトルまたは本文がない場合は記録しない
        guard !title.isEmpty || !body.isEmpty else {
            print("🚨 タイトル・本文が空のため緊急保存をスキップ")
            return
        }
        
        // 緊急用の通知エントリを作成
        let emergencyEntry: [String: Any] = [
            "id": UUID().uuidString,
            "title": title,
            "body": body,
            "notificationType": "emergency_fcm_\(source)",
            "userInfo": userInfo,
            "isFromFCM": true,
            "wasTapped": false,
            "receivedAt": Date().timeIntervalSince1970
        ]
        
        // UserDefaultsから既存の緊急履歴を取得
        let emergencyKey = "emergency_notification_history"
        var emergencyHistory = UserDefaults.standard.array(forKey: emergencyKey) as? [[String: Any]] ?? []
        
        print("🚨 既存の緊急履歴数: \(emergencyHistory.count)")
        
        // 新しいエントリを先頭に追加
        emergencyHistory.insert(emergencyEntry, at: 0)
        
        // 最大100件に制限
        if emergencyHistory.count > 100 {
            emergencyHistory = Array(emergencyHistory.prefix(100))
        }
        
        // UserDefaultsに保存
        UserDefaults.standard.set(emergencyHistory, forKey: emergencyKey)
        UserDefaults.standard.synchronize()
        
        print("🚨 緊急保存完了: 履歴数=\(emergencyHistory.count)")
        print("🚨🚨🚨 === 緊急パッチ: 直接UserDefaults保存終了 ===")
        print("")
    }
    
    // MARK: - Navigation Helpers
    
    private func openEventDetail(eventId: String) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: NSNotification.Name("OpenEventDetail"),
                object: nil,
                userInfo: ["eventId": eventId]
            )
        }
    }
    
    private func openMemoEditor(memoId: String) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: NSNotification.Name("OpenMemoEditor"),
                object: nil,
                userInfo: ["memoId": memoId]
            )
        }
    }
    
    private func openBackupSettings() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: NSNotification.Name("OpenBackupSettings"),
                object: nil
            )
        }
    }
}

// MARK: - Push Notification Helper Methods

extension AppDelegate {
    
    /// 現在のプッシュ通知設定状態を取得
    static func getCurrentNotificationSettings() -> Bool {
        return UserDefaults.standard.bool(forKey: "push_notifications_enabled")
    }
    
    /// FCMトークンを取得
    static func getFCMToken() -> String? {
        return UserDefaults.standard.string(forKey: "fcm_token")
    }
    
    /// APNsトークンを取得
    static func getAPNsToken() -> String? {
        return UserDefaults.standard.string(forKey: "apns_token")
    }
    
    /// プッシュ通知設定を再確認
    static func checkNotificationPermissions() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                let enabled = settings.authorizationStatus == .authorized
                UserDefaults.standard.set(enabled, forKey: "push_notifications_enabled")
                
                NotificationCenter.default.post(
                    name: NSNotification.Name("PushNotificationSettingsChanged"),
                    object: nil,
                    userInfo: ["enabled": enabled]
                )
            }
        }
    }
}