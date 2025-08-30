import Foundation
import FirebaseFirestore
import FirebaseMessaging
import UserNotifications
import Combine

// MARK: - Firebase Service
/// Firebaseとの通信を管理するサービスクラス
class FirebaseService: ObservableObject {
    private let db = Firestore.firestore()
    
    // MARK: - Published Properties
    @Published var events: [Event] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    
    // MARK: - Private Properties
    private var hasAccessedFirebaseEvents = false
    private var lastFetchTimestamp: Date?
    
    // MARK: - Singleton
    static let shared = FirebaseService()
    
    private init() {
        print("🔧 FirebaseService初期化開始")
        print("🔧 イベントデータは1時間ごとに再読み込み")
    }
    
    // MARK: - Event CRUD Operations
    
    /// イベント一覧を取得
    func fetchEvents() {
        // 1時間以内に取得済みの場合はスキップ（コスト削減）
        if let lastFetch = lastFetchTimestamp {
            let timeInterval = Date().timeIntervalSince(lastFetch)
            let hoursElapsed = timeInterval / 3600
            
            if hoursElapsed < 1 {
                let remainingMinutes = Int((1 - hoursElapsed) * 60)
                print("⚠️ イベントデータは\(Int(hoursElapsed * 60))分前に取得済み - あと\(remainingMinutes)分後に再読み込み可能")
                return
            }
        }
        
        print("🔥 Firebaseにアクセスします。")
        lastFetchTimestamp = Date()
        hasAccessedFirebaseEvents = true
        
        print("🚀 fetchEvents() 開始")
        isLoading = true
        errorMessage = nil
        
        // Firebase接続確認のため少し待機
        print("⏳ Firebase接続の安定化を待機...")
        
        // 段階的にデータ取得を試行
        performInitialFetch(retryCount: 0)
    }
    
    /// 初回データ取得を段階的に試行
    private func performInitialFetch(retryCount: Int) {
        let maxRetries = 3
        
        db.collection("event")
            .order(by: "title", descending: false)
            .getDocuments(source: .default) { [weak self] querySnapshot, error in  // source: .default で確実取得
                DispatchQueue.main.async {
                    print("📥 初回データ取得試行 #\(retryCount + 1)")
                    
                    if let error = error {
                        print("❌ 初回データ取得エラー: \(error)")
                        
                        if retryCount < maxRetries {
                            print("🔄 \(retryCount + 1)回目失敗、1秒後に再試行...")
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                self?.performInitialFetch(retryCount: retryCount + 1)
                            }
                            return
                        } else {
                            self?.errorMessage = "イベントの取得に失敗しました: \(error.localizedDescription)"
                            self?.isLoading = false
                            return
                        }
                    }
                    
                    guard let documents = querySnapshot?.documents else {
                        print("📝 初回データ: ドキュメントなし")
                        
                        if retryCount < maxRetries {
                            print("🔄 ドキュメントなし、1秒後に再試行...")
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                self?.performInitialFetch(retryCount: retryCount + 1)
                            }
                            return
                        } else {
                            self?.events = []
                            self?.isLoading = false
                            return
                        }
                    }
                    
                    print("📝 初回データ: \(documents.count) 件のドキュメント発見")
                    var initialEvents: [Event] = []
                    
                    for document in documents {
                        let rawData = document.data()
                        print("🔍 初回データ - ドキュメント: \(document.documentID)")
                        print("  ═══ 全フィールドRAWデータ ═══")
                        for (key, value) in rawData {
                            print("    \(key): '\(value)'")
                        }
                        print("  ═══════════════════════════")
                        print("  - title: '\(rawData["title"] ?? "nil")'")
                        print("  - content: '\(rawData["content"] ?? "nil")'")
                        print("  - application_form_url: '\(rawData["application_form_url"] ?? "nil")'")
                        print("  - analysis_template: '\(rawData["analysis_template"] ?? "nil")'")
                        
                        // 手動でEventを作成（Codable問題回避）
                        if let title = rawData["title"] as? String,
                           let content = rawData["content"] as? String {
                            
                            // 日付フィールドの処理
                            var deadlineDate: Date? = nil
                            var eventDate: Date? = nil
                            
                            if let timestamp = rawData["deadline_date"] as? Timestamp {
                                deadlineDate = timestamp.dateValue()
                            }
                            
                            if let timestamp = rawData["event_date"] as? Timestamp {
                                eventDate = timestamp.dateValue()
                            }
                            
                            // 新しいフィールドを取得
                            let applicationFormURL = rawData["application_form_url"] as? String
                            let analysisTemplate = rawData["analysis_template"] as? String
                            let venue = rawData["venue"] as? String
                            let capacity = rawData["capacity"] as? String
                            let target = rawData["target"] as? String
                            
                            print("  🔍 新フィールド詳細取得:")
                            print("    - applicationFormURL: '\(applicationFormURL ?? "nil")'")
                            print("    - analysisTemplate: '\(analysisTemplate ?? "nil")'")
                            print("    - venue: '\(venue ?? "nil")'")
                            print("    - capacity: '\(capacity ?? "nil")'")
                            print("    - target: '\(target ?? "nil")'")
                            
                            let event = Event(title: title, content: content, deadline_date: deadlineDate, event_date: eventDate, application_form_url: applicationFormURL, analysis_template: analysisTemplate, venue: venue, capacity: capacity, target: target)
                            var eventWithId = event
                            eventWithId.id = document.documentID
                            initialEvents.append(eventWithId)
                            print("  ✅ 手動作成成功: title='\(eventWithId.title)', content=\(eventWithId.content.count)文字")
                            print("  ✅ 新フィールド確認: URL='\(eventWithId.application_form_url ?? "nil")', Template='\(eventWithId.analysis_template ?? "nil")'")
                            print("  ✅ venue='\(eventWithId.venue ?? "nil")', capacity='\(eventWithId.capacity ?? "nil")', target='\(eventWithId.target ?? "nil")'")
                        } else {
                            // title または content がない場合もスキップ
                            print("  ❌ 必須フィールドなし: title または content が見つかりません")
                        }
                    }
                    
                    // 初回データを即座に反映
                    self?.events = initialEvents
                    self?.isLoading = false
                    print("✅ 初回データ設定完了: \(initialEvents.count) 件のイベントを読み込みました")
                }
            }
    }
    
    
    /// 特定のイベントを個別に取得（絶対確実）
    func fetchSingleEvent(eventId: String, completion: @escaping (Event?) -> Void) {
        print("🎯 個別イベント取得開始: \(eventId)")
        
        // source: .server で必ずサーバーから最新データを取得
        db.collection("event").document(eventId).getDocument(source: .server) { document, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ 個別イベント取得エラー: \(error)")
                    // サーバー取得失敗時はキャッシュから再試行
                    self.db.collection("event").document(eventId).getDocument(source: .cache) { cacheDocument, cacheError in
                        DispatchQueue.main.async {
                            if let cacheDocument = cacheDocument, cacheDocument.exists {
                                self.processEventDocument(cacheDocument, completion: completion, source: "cache")
                            } else {
                                print("❌ キャッシュからも取得失敗")
                                completion(nil)
                            }
                        }
                    }
                    return
                }
                
                guard let document = document, document.exists else {
                    print("❌ 個別イベント: ドキュメントが存在しません")
                    completion(nil)
                    return
                }
                
                self.processEventDocument(document, completion: completion, source: "server")
            }
        }
    }
    
    /// ドキュメントからEventオブジェクトを確実に作成
    private func processEventDocument(_ document: DocumentSnapshot, completion: @escaping (Event?) -> Void, source: String) {
        let rawData = document.data() ?? [:]
        print("🔍 個別イベント RAWデータ (\(source)):")
        print("  - ドキュメントID: \(document.documentID)")
        print("  - title: '\(rawData["title"] ?? "nil")'")
        print("  - content: '\(rawData["content"] ?? "nil")'")
        print("  - application_form_url: '\(rawData["application_form_url"] ?? "nil")'")
        print("  - analysis_template: '\(rawData["analysis_template"] ?? "nil")'")
        print("  - venue: '\(rawData["venue"] ?? "nil")'")
        
        // 最優先：手動でEventを作成（最も確実）
        if let title = rawData["title"] as? String,
           let content = rawData["content"] as? String {
            
            // 日付フィールドの処理
            var deadlineDate: Date? = nil
            var eventDate: Date? = nil
            
            if let timestamp = rawData["deadline_date"] as? Timestamp {
                deadlineDate = timestamp.dateValue()
            }
            
            if let timestamp = rawData["event_date"] as? Timestamp {
                eventDate = timestamp.dateValue()
            }
            
            // 新しいフィールドを取得
            let applicationFormURL = rawData["application_form_url"] as? String
            let analysisTemplate = rawData["analysis_template"] as? String
            let venue = rawData["venue"] as? String
            let capacity = rawData["capacity"] as? String
            let target = rawData["target"] as? String
            
            print("  🔍 新フィールド詳細取得 (\(source)):")
            print("    - applicationFormURL: '\(applicationFormURL ?? "nil")'")
            print("    - analysisTemplate: '\(analysisTemplate ?? "nil")'")
            print("    - venue: '\(venue ?? "nil")'")
            print("    - capacity: '\(capacity ?? "nil")'")
            print("    - target: '\(target ?? "nil")'")
            
            let event = Event(title: title, content: content, deadline_date: deadlineDate, event_date: eventDate, application_form_url: applicationFormURL, analysis_template: analysisTemplate, venue: venue, capacity: capacity, target: target)
            var eventWithId = event
            eventWithId.id = document.documentID
            print("  ✅ 手動Event作成成功 (\(source)): title='\(eventWithId.title)', content=\(eventWithId.content.count)文字")
            print("  ✅ 新フィールド最終確認: URL='\(eventWithId.application_form_url ?? "nil")', Template='\(eventWithId.analysis_template ?? "nil")'")
            print("  ✅ venue='\(eventWithId.venue ?? "nil")', capacity='\(eventWithId.capacity ?? "nil")', target='\(eventWithId.target ?? "nil")'")
            completion(eventWithId)
            return
        }
        
        // Codableは信頼できないため、手動フォールバック処理
        var deadlineDate: Date? = nil
        var eventDate: Date? = nil
        
        if let timestamp = rawData["deadline_date"] as? Timestamp {
            deadlineDate = timestamp.dateValue()
        }
        
        if let timestamp = rawData["event_date"] as? Timestamp {
            eventDate = timestamp.dateValue()
        }
        
        let fallbackEvent = Event(title: rawData["title"] as? String ?? "タイトル不明", 
                                content: rawData["content"] as? String ?? "",
                                deadline_date: deadlineDate,
                                event_date: eventDate,
                                application_form_url: rawData["application_form_url"] as? String,
                                analysis_template: rawData["analysis_template"] as? String,
                                venue: rawData["venue"] as? String,
                                capacity: rawData["capacity"] as? String,
                                target: rawData["target"] as? String)
        var eventWithId = fallbackEvent
        eventWithId.id = document.documentID
        print("⚠️ フォールバックEvent作成: title='\(eventWithId.title)', content=\(eventWithId.content.count)文字")
        print("⚠️ フォールバック capacity='\(eventWithId.capacity ?? "nil")', target='\(eventWithId.target ?? "nil")'")
        completion(eventWithId)
    }
    
    /// イベントを追加
    func addEvent(title: String, content: String) {
        let event = Event(title: title, content: content)
        
        do {
            _ = try db.collection("event").addDocument(from: event) { [weak self] error in
                DispatchQueue.main.async {
                    if let error = error {
                        self?.errorMessage = "イベントの追加に失敗しました: \(error.localizedDescription)"
                        print("Error adding event: \(error)")
                    } else {
                        print("✅ イベントを追加しました: \(title)")
                    }
                }
            }
        } catch {
            DispatchQueue.main.async {
                self.errorMessage = "イベントの追加に失敗しました: \(error.localizedDescription)"
                print("Error encoding event: \(error)")
            }
        }
    }
    
    /// イベントを更新
    func updateEvent(_ event: Event, title: String, content: String) {
        guard let eventId = event.id else {
            errorMessage = "イベントIDが見つかりません"
            return
        }
        
        let updatedData: [String: Any] = [
            "title": title,
            "content": content
        ]
        
        db.collection("event").document(eventId).updateData(updatedData) { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.errorMessage = "イベントの更新に失敗しました: \(error.localizedDescription)"
                    print("Error updating event: \(error)")
                } else {
                    print("✅ イベントを更新しました: \(title)")
                }
            }
        }
    }
    
    /// イベントを削除
    func deleteEvent(_ event: Event) {
        guard let eventId = event.id else {
            errorMessage = "イベントIDが見つかりません"
            return
        }
        
        db.collection("event").document(eventId).delete { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.errorMessage = "イベントの削除に失敗しました: \(error.localizedDescription)"
                    print("Error deleting event: \(error)")
                } else {
                    print("✅ イベントを削除しました")
                }
            }
        }
    }
    
    /// 全てのイベントを削除（データクリア用）
    func clearAllEvents() {
        print("🗑️ 全イベントデータの削除を開始")
        
        db.collection("event").getDocuments { [weak self] querySnapshot, error in
            if let error = error {
                DispatchQueue.main.async {
                    self?.errorMessage = "イベントデータの取得に失敗しました: \(error.localizedDescription)"
                    print("❌ イベント取得エラー: \(error)")
                }
                return
            }
            
            guard let documents = querySnapshot?.documents else {
                print("📝 削除するイベントデータがありません")
                return
            }
            
            print("📝 \(documents.count) 件のイベントを削除します")
            let batch = self?.db.batch()
            
            for document in documents {
                batch?.deleteDocument(document.reference)
                print("🗑️ 削除予定: \(document.documentID)")
            }
            
            batch?.commit { error in
                DispatchQueue.main.async {
                    if let error = error {
                        self?.errorMessage = "イベントデータの削除に失敗しました: \(error.localizedDescription)"
                        print("❌ バッチ削除エラー: \(error)")
                    } else {
                        print("✅ 全イベントデータの削除が完了しました")
                        self?.events = []
                    }
                }
            }
        }
    }
    
    // MARK: - Push Notifications
    
    /// FCMトークンをFirestoreに保存
    /// - Parameter token: FCMトークン
    func updateFCMToken(token: String) {
        print("📡 FCMトークンをFirestoreに保存: \(token)")
        
        // デバイス固有のドキュメントID（トークンのハッシュ値など）
        let tokenHash = token.hash
        let documentId = "device_\(abs(tokenHash))"
        
        let tokenData: [String: Any] = [
            "fcm_token": token,
            "updated_at": Timestamp(date: Date()),
            "platform": "ios",
            "app_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        ]
        
        db.collection("fcm_tokens").document(documentId).setData(tokenData, merge: true) { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ FCMトークン保存エラー: \(error)")
                    self?.errorMessage = "通知設定の保存に失敗しました: \(error.localizedDescription)"
                } else {
                    print("✅ FCMトークン保存成功")
                }
            }
        }
    }
    
    /// リモート通知メッセージの処理
    /// - Parameter messageData: 通知データ
    func handleRemoteNotification(_ messageData: [AnyHashable: Any]) {
        print("🔔 FirebaseService: リモート通知メッセージ処理開始")
        print("📋 メッセージデータ: \(messageData)")
        print("📋 messageDataのキー一覧: \(Array(messageData.keys).map(String.init(describing:)))")
        
        // 通知履歴の記録はAppDelegateで行われるため、ここでは記録しない
        // forceRecordFCMFromFirebaseService(messageData)
        
        // 通知タイプに応じた処理
        if let notificationType = messageData["type"] as? String {
            switch notificationType {
            case "new_event":
                handleNewEventNotification(messageData)
            case "event_update":
                handleEventUpdateNotification(messageData)
            case "reminder":
                handleReminderNotification(messageData)
            default:
                print("🔔 未対応の通知タイプ: \(notificationType)")
            }
        }
        
        // アプリ内データの同期更新
        refreshDataFromNotification(messageData)
        
        print("🔔 FirebaseService: リモート通知メッセージ処理終了")
    }
    
    /// FirebaseServiceからFCM通知を強制的に履歴に記録
    /// - Parameter messageData: 通知データ
    private func forceRecordFCMFromFirebaseService(_ messageData: [AnyHashable: Any]) {
        print("🚨 FirebaseService: FCM通知強制記録開始")
        
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
        
        // 直接指定の場合
        if title.isEmpty {
            title = messageData["title"] as? String ?? ""
        }
        if body.isEmpty {
            body = messageData["body"] as? String ?? ""
        }
        
        // NotificationHistoryManagerに直接記録
        DispatchQueue.main.async {
            if !title.isEmpty || !body.isEmpty {
                NotificationHistoryManager.shared.addNotification(
                    title: title,
                    body: body,
                    notificationType: "firebase_service_fcm",
                    userInfo: messageData,
                    isFromFCM: true,
                    wasTapped: false
                )
            }
        }
        
        print("✅ FirebaseService: FCM通知強制記録完了")
    }
    
    /// 新しいイベント通知の処理
    private func handleNewEventNotification(_ messageData: [AnyHashable: Any]) {
        print("📅 新しいイベント通知を処理")
        
        if let eventId = messageData["event_id"] as? String {
            print("🆕 新しいイベントID: \(eventId)")
            
            // 新しいイベントを取得してローカルデータに追加
            fetchSingleEvent(eventId: eventId) { [weak self] event in
                if let event = event {
                    DispatchQueue.main.async {
                        // 既存リストに存在しない場合のみ追加
                        guard let self = self else { return }
                        let isAlreadyExists = self.events.contains(where: { $0.id == event.id })
                        if !isAlreadyExists {
                            self.events.append(event)
                            print("✅ 新しいイベントをローカルに追加: \(event.title)")
                        }
                    }
                }
            }
        }
    }
    
    /// イベント更新通知の処理
    private func handleEventUpdateNotification(_ messageData: [AnyHashable: Any]) {
        print("🔄 イベント更新通知を処理")
        
        if let eventId = messageData["event_id"] as? String {
            print("🔄 更新されたイベントID: \(eventId)")
            
            // 更新されたイベントを取得してローカルデータを更新
            fetchSingleEvent(eventId: eventId) { [weak self] event in
                if let event = event {
                    DispatchQueue.main.async {
                        // 既存イベントを更新
                        guard let self = self else { return }
                        if let index = self.events.firstIndex(where: { $0.id == event.id }) {
                            self.events[index] = event
                            print("✅ イベント更新完了: \(event.title)")
                        } else {
                            // 存在しない場合は新規追加
                            self.events.append(event)
                            print("✅ 新しいイベントとして追加: \(event.title)")
                        }
                    }
                }
            }
        }
    }
    
    /// リマインダー通知の処理
    private func handleReminderNotification(_ messageData: [AnyHashable: Any]) {
        print("⏰ リマインダー通知を処理")
        
        // リマインダーの種類に応じた処理
        if let reminderType = messageData["reminder_type"] as? String {
            switch reminderType {
            case "backup":
                print("💾 バックアップリマインダー")
                // バックアップ処理の実行は通知ハンドラで行う
                
            case "memo_deadline":
                print("📝 メモ期日リマインダー")
                if let memoId = messageData["memo_id"] as? String {
                    print("📝 対象メモID: \(memoId)")
                    // メモ期日リマインダーの処理
                }
                
            default:
                print("⏰ 未対応のリマインダータイプ: \(reminderType)")
            }
        }
    }
    
    /// 通知からのデータ同期更新
    private func refreshDataFromNotification(_ messageData: [AnyHashable: Any]) {
        print("🔄 通知によるデータ同期開始")
        
        // データ更新が必要な場合は強制的に最新データを取得
        if messageData["force_refresh"] as? Bool == true {
            print("🔄 強制的なデータ更新を実行")
            // 最終取得時刻をリセットして強制更新
            lastFetchTimestamp = nil
            fetchEvents()
        }
        
        // メッセージ本文に「新しいイベント」が含まれている場合、イベント一覧を表示
        if let title = messageData["title"] as? String,
           let body = messageData["body"] as? String {
            let fullMessage = "\(title) \(body)"
            if fullMessage.contains("新しいイベント") {
                print("🎯 「新しいイベント」を検出 - イベント一覧表示をトリガー")
                showEventList()
            }
        }
        
        // FCM の aps payload からも確認
        if let aps = messageData["aps"] as? [String: Any],
           let alert = aps["alert"] as? [String: Any] {
            let title = alert["title"] as? String ?? ""
            let body = alert["body"] as? String ?? ""
            let fullMessage = "\(title) \(body)"
            if fullMessage.contains("新しいイベント") {
                print("🎯 APSペイロードで「新しいイベント」を検出 - イベント一覧表示をトリガー")
                showEventList()
            }
        }
    }
    
    /// イベント一覧を表示するメソッド
    private func showEventList() {
        DispatchQueue.main.async {
            print("📅 イベント一覧表示通知を送信")
            NotificationCenter.default.post(
                name: NSNotification.Name("ShowEventList"),
                object: nil,
                userInfo: ["source": "fcm_notification"]
            )
        }
    }
    
    /// 通知権限の確認とFCMトークン再送信
    func checkAndUpdateNotificationStatus() {
        // FCMトークンが利用可能な場合は再送信
        if let token = AppDelegate.getFCMToken() {
            updateFCMToken(token: token)
        }
        
        // 通知設定の状態を確認
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                let isEnabled = settings.authorizationStatus == .authorized
                print("🔔 通知権限状態: \(isEnabled ? "許可" : "未許可")")
                
                // 設定変更の通知
                NotificationCenter.default.post(
                    name: NSNotification.Name("NotificationPermissionChanged"),
                    object: nil,
                    userInfo: ["enabled": isEnabled]
                )
            }
        }
    }
    
    // MARK: - Utility Methods
    
    /// エラーメッセージをクリア
    func clearError() {
        errorMessage = nil
    }
}