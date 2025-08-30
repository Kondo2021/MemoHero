import SwiftUI
import UIKit
import Firebase

// MARK: - MemoHero
/// メモアプリのメインエントリーポイント
/// アプリのライフサイクルとグローバル設定を管理
@main
struct MemoHero: App {
    // MARK: - App Delegate
    /// AppDelegateアダプター（プッシュ通知対応）
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    // MARK: - State Objects
    /// メモデータストア（アプリ全体で共有）
    @StateObject private var memoStore = MemoStore()
    /// フォルダデータストア（アプリ全体で共有）
    @StateObject private var folderStore = FolderStore()
    /// 通知管理（アプリ全体で共有）
    @StateObject private var notificationManager = NotificationManager.shared
    /// Firebase サービス（アプリ全体で共有）
    @StateObject private var firebaseService = FirebaseService.shared
    
    // MARK: - Initializer
    /// アプリの初期化
    /// 言語設定の強制適用を含む
    init() {
        let timestamp = DateFormatter.debugFormatter.string(from: Date())
        print("🚀 MemoHero.init() 開始 [\(timestamp)]")
        
        // Firebase初期化はAppDelegateで実行されるため、ここでは実行しない
        print("ℹ️ Firebase初期化はAppDelegateで実行済み")
        
        // Firebase初期化完了を待ってからFirestore設定
        // 直接実行（init内でのself使用を回避）
        configureFirestoreDirectly()
        
        // 強制的に日本語ロケールを設定
        UserDefaults.standard.set(["ja"], forKey: "AppleLanguages")
        UserDefaults.standard.synchronize()
        
        print("✅ MemoHero.init() 完了 [\(DateFormatter.debugFormatter.string(from: Date()))]")
        print("   言語設定: 日本語に強制設定")
        print("   次: @StateObject の初期化が開始されます")
    }
    
    // MARK: - Private Methods
    
    /// Firestore設定の最適化（init内から直接呼び出し用）
    private func configureFirestoreDirectly() {
        // init内では直接設定はせず、onAppearで実行するためのフラグのみ設定
        print("ℹ️ Firestore設定は onAppear で実行されます")
    }
    
    /// Firestore設定の最適化
    /// AppDelegate での Firebase 初期化完了後に実行
    private func configureFirestore() {
        // Firebase が初期化されているかチェック
        guard FirebaseApp.app() != nil else {
            print("⚠️ Firebaseがまだ初期化されていません")
            // 再試行
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.configureFirestore()
            }
            return
        }
        
        // Firestore設定を最適化
        let db = Firestore.firestore()
        
        // 新しいキャッシュ設定を使用（iOS 17対応）
        let settings = FirestoreSettings()
        settings.cacheSettings = PersistentCacheSettings(sizeBytes: NSNumber(value: FirestoreCacheSizeUnlimited))
        db.settings = settings
        print("✅ Firestore設定最適化完了（iOS 17新方式）")
        
        // Firebase初期化後の確認
        if let app = FirebaseApp.app() {
            print("🔥 Firebaseアプリ確認: \(app.name), プロジェクトID: \(app.options.projectID ?? "nil")")
        }
    }
    
    // MARK: - Scene
    /// アプリのシーン構成
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(memoStore)
                .environmentObject(folderStore)
                .environmentObject(notificationManager)
                .environmentObject(firebaseService)
                .onAppear {
                    // バッジを絶対に表示させない（念のため再実行）
                    notificationManager.disableBadge()
                    
                    // プッシュ通知設定を確認
                    AppDelegate.checkNotificationPermissions()
                    
                    // Firestore設定を実行
                    configureFirestore()
                }
                .onOpenURL { url in
                    handleURLScheme(url)
                }
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenEventDetail"))) { notification in
                    handleOpenEventDetail(notification)
                }
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenMemoEditor"))) { notification in
                    handleOpenMemoEditor(notification)
                }
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenBackupSettings"))) { notification in
                    handleOpenBackupSettings()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowEventList"))) { notification in
                    handleShowEventList(notification)
                }
        }
    }
    
    // MARK: - Push Notification Handlers
    
    /// イベント詳細画面を開く通知処理
    /// - Parameter notification: 通知情報
    private func handleOpenEventDetail(_ notification: Notification) {
        guard let eventId = notification.userInfo?["eventId"] as? String else {
            print("❌ イベントID取得失敗")
            return
        }
        
        print("📅 イベント詳細画面を開く: \(eventId)")
        
        // EventListViewを表示する処理をここに実装
        // 例：isShowingEventListをtrueにする等
        NotificationCenter.default.post(
            name: NSNotification.Name("ShowEventList"),
            object: nil,
            userInfo: ["targetEventId": eventId]
        )
    }
    
    /// メモ編集画面を開く通知処理
    /// - Parameter notification: 通知情報
    private func handleOpenMemoEditor(_ notification: Notification) {
        guard let memoIdString = notification.userInfo?["memoId"] as? String,
              let memoId = UUID(uuidString: memoIdString) else {
            print("❌ メモID取得失敗")
            return
        }
        
        print("📝 メモ編集画面を開く: \(memoId)")
        
        // 該当メモを検索して画面を開く
        if memoStore.memos.contains(where: { $0.id == memoId }) {
            // メモ編集画面を開く処理
            NotificationCenter.default.post(
                name: NSNotification.Name("OpenMemoFromNotification"),
                object: nil,
                userInfo: ["memoId": memoId, "source": "push_notification"]
            )
        } else {
            print("❌ 指定されたメモが見つかりません: \(memoId)")
        }
    }
    
    /// バックアップ設定画面を開く通知処理
    private func handleOpenBackupSettings() {
        print("💾 バックアップ設定画面を開く")
        
        // バックアップ設定画面を表示する処理
        NotificationCenter.default.post(
            name: NSNotification.Name("ShowBackupSettings"),
            object: nil
        )
    }
    
    /// イベント一覧を表示する通知処理
    /// - Parameter notification: 通知情報
    private func handleShowEventList(_ notification: Notification) {
        print("📅 イベント一覧表示要求を受信")
        if let source = notification.userInfo?["source"] as? String {
            print("📅 要求元: \(source)")
        }
        
        // ContentViewでイベント一覧を表示する処理のための通知を送信
        NotificationCenter.default.post(
            name: NSNotification.Name("PresentEventList"),
            object: nil,
            userInfo: notification.userInfo ?? [:]
        )
    }
    
    // MARK: - URL Scheme Handling
    /// URLスキームハンドリング
    /// ウィジェットや外部アプリからの起動に対応
    /// - Parameter url: 処理するURL
    private func handleURLScheme(_ url: URL) {
        let timestamp = DateFormatter.debugFormatter.string(from: Date())
        print("🔗 URLスキーム処理開始 [\(timestamp)] - URL: \(url)")
        
        guard url.scheme == "memohero" else {
            print("❌ 無効なスキーム: \(url.scheme ?? "nil")")
            return
        }
        
        // 初期化完了チェック
        guard memoStore.isInitialized && folderStore.isInitialized else {
            print("❌ 初期化未完了のためURLスキーム処理をスキップ")
            print("   MemoStore初期化状態: \(memoStore.isInitialized)")
            print("   FolderStore初期化状態: \(folderStore.isInitialized)")
            
            // 初期化完了後に再試行
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if self.memoStore.isInitialized && self.folderStore.isInitialized {
                    print("🔄 初期化完了後にURLスキーム処理を再試行")
                    self.handleURLScheme(url)
                } else {
                    print("❌ 再試行時も初期化未完了のためURLスキーム処理を中止")
                }
            }
            return
        }
        
        if url.host == "new-memo" {
            print("📝 新規メモ作成スキーム")
            let newMemo = Memo()
            memoStore.addMemo(newMemo)
            print("✅ URLスキーム処理完了")
        } else if url.host == "open" {
            print("📖 メモ開閉スキーム（ウィジェットから）")
            let pathComponents = url.pathComponents
            if pathComponents.count > 1 {
                let memoIdString = pathComponents[1]
                if let memoId = UUID(uuidString: memoIdString),
                   let targetMemo = memoStore.memos.first(where: { $0.id == memoId }) {
                    print("🎯 対象メモ発見: \(targetMemo.displayTitle)")
                    
                    // メモをプレビュー状態で開く通知を送信
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        NotificationCenter.default.post(
                            name: NSNotification.Name("OpenMemoFromWidget"),
                            object: nil,
                            userInfo: ["memoId": memoId, "source": "widget"]
                        )
                    }
                } else {
                    print("❌ 指定されたメモが見つかりません: \(memoIdString)")
                }
            } else {
                print("❌ 無効なパス構造")
            }
        } else if url.host == "toggle-checkbox" {
            print("☑️ チェックボックス切り替えスキーム（ウィジェットから）")
            let pathComponents = url.pathComponents
            // URL形式: memohero://toggle-checkbox/MEMO_ID/LINE_INDEX/checked_or_unchecked
            if pathComponents.count >= 4 {
                let memoIdString = pathComponents[1]
                let lineIndexString = pathComponents[2]
                let currentState = pathComponents[3]
                
                if let memoId = UUID(uuidString: memoIdString),
                   let lineIndex = Int(lineIndexString),
                   let targetMemo = memoStore.memos.first(where: { $0.id == memoId }) {
                    
                    print("🎯 チェックボックス切り替え対象: \(targetMemo.displayTitle)")
                    print("   行インデックス: \(lineIndex), 現在の状態: \(currentState)")
                    
                    // チェックボックスの状態を切り替える
                    toggleCheckboxInMemo(memo: targetMemo, lineIndex: lineIndex, currentState: currentState)
                    
                } else {
                    print("❌ チェックボックス切り替え - 無効なパラメータ")
                    print("   メモID: \(memoIdString), 行インデックス: \(lineIndexString)")
                }
            } else {
                print("❌ チェックボックス切り替え - 無効なパス構造")
            }
        } else {
            print("❌ 未対応のホスト: \(url.host ?? "nil")")
        }
    }
    
    // MARK: - Checkbox Toggle Helper
    /// ウィジェットからのチェックボックス切り替え処理
    /// - Parameters:
    ///   - memo: 対象のメモ
    ///   - lineIndex: チェックボックスの行インデックス
    ///   - currentState: 現在の状態（"checked" or "unchecked"）
    private func toggleCheckboxInMemo(memo: Memo, lineIndex: Int, currentState: String) {
        print("🔄 チェックボックス切り替え開始")
        
        // メモ内容の行を分割
        var lines = memo.content.components(separatedBy: .newlines)
        
        // 実際のマークダウン行のインデックスを計算（空行をスキップ）
        var markdownLineIndex = 0
        var actualLineIndex = 0
        
        for (index, line) in lines.enumerated() {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            
            // 空行でない場合のみカウント
            if !trimmedLine.isEmpty {
                if markdownLineIndex == lineIndex {
                    actualLineIndex = index
                    break
                }
                markdownLineIndex += 1
            }
        }
        
        // 該当行がチェックリスト項目かチェック & 状態を更新
        if actualLineIndex < lines.count {
            let line = lines[actualLineIndex]
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            var updated = false
            
            // 現在の状態に基づいて反対の状態に切り替える
            if currentState == "checked" {
                // 現在チェック済み → 未チェックに変更
                if trimmedLine.hasPrefix("- [x] ") || trimmedLine.hasPrefix("- [X] ") {
                    lines[actualLineIndex] = line.replacingOccurrences(of: "- [x] ", with: "- [ ] ")
                        .replacingOccurrences(of: "- [X] ", with: "- [ ] ")
                    updated = true
                    print("✅ チェック済み → 未チェックに変更")
                }
            } else if currentState == "unchecked" {
                // 現在未チェック → チェック済みに変更
                if trimmedLine.hasPrefix("- [ ] ") {
                    lines[actualLineIndex] = line.replacingOccurrences(of: "- [ ] ", with: "- [x] ")
                    updated = true
                    print("✅ 未チェック → チェック済みに変更")
                }
            }
            
            if updated {
                // 更新されたメモを作成
                var updatedMemo = memo
                updatedMemo.content = lines.joined(separator: "\n")
                updatedMemo.updatedAt = Date()
                
                memoStore.updateMemo(updatedMemo)
                
                // ウィジェットデータも更新
                WidgetDataManager.shared.setWidgetMemo(updatedMemo)
                
                print("💾 チェックボックス切り替え完了 - メモ更新済み")
            } else {
                print("⚠️ チェックボックス切り替え - 該当行はチェックリスト項目ではありません")
            }
        } else {
            print("⚠️ チェックボックス切り替え - 行インデックスが範囲外")
        }
    }
}