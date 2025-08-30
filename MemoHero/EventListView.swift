import SwiftUI
import Foundation
import FirebaseFirestore

// MARK: - Event List View
/// イベント一覧を表示するビュー（Firebaseから読み込み）
struct EventListView: View {
    // MARK: - Environment Objects
    @EnvironmentObject private var firebaseService: FirebaseService
    @Environment(\.dismiss) private var dismiss
    
    // MARK: - State Properties
    @State private var selectedEvent: Event?
    @State private var showingEventContent = false
    
    // MARK: - Callback
    var onMemoCreated: ((Memo) -> Void)?
    
    // MARK: - Initializer
    init(onMemoCreated: ((Memo) -> Void)? = nil) {
        self.onMemoCreated = onMemoCreated
    }
    
    // MARK: - Computed Properties
    /// テストデータを除外した実際のイベントのみを返す
    private var filteredEvents: [Event] {
        return firebaseService.events.filter { event in
            // テストデータのタイトルパターンを除外
            let testTitles = [
                "プログラミングコンテスト",
                "デザインワークショップ", 
                "AI・ML セミナー",
                "スタートアップピッチ",
                "モバイルアプリ開発講座"
            ]
            
            return !testTitles.contains(event.title)
        }
    }
    
    var body: some View {
        NavigationView {
            VStack {
                if firebaseService.isLoading && filteredEvents.isEmpty {
                    loadingView
                } else if firebaseService.errorMessage != nil {
                    errorStateView
                } else if filteredEvents.isEmpty {
                    emptyStateView
                } else {
                    eventTitleList
                }
            }
            .navigationTitle("イベント一覧")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingEventContent) {
                SheetContentView(selectedEvent: selectedEvent, onMemoCreated: onMemoCreated)
            }
            .onChange(of: selectedEvent) {
                print("🔍 selectedEvent が変更されました")
                print("  - 新しい値 == nil: \(selectedEvent == nil)")
                print("  - 新しい値?.title: '\(selectedEvent?.title ?? "nil")'")
            }
            .onChange(of: showingEventContent) {
                print("🔍 showingEventContent が変更されました")
                print("  - 新しい値: \(showingEventContent)")
                print("  - その時のselectedEvent == nil: \(selectedEvent == nil)")
            }
            .alert("エラー", isPresented: .constant(firebaseService.errorMessage != nil)) {
                Button("OK") {
                    firebaseService.clearError()
                }
            } message: {
                Text(firebaseService.errorMessage ?? "")
            }
        }
        .onAppear {
            print("🔄 EventListView onAppear - イベント読み込み開始")
            print("  - 現在の全イベント数: \(firebaseService.events.count)")
            print("  - フィルタ後イベント数: \(filteredEvents.count)")
            print("  - 読み込み中?: \(firebaseService.isLoading)")
            
            // Firebaseからイベントデータを読み込み
            firebaseService.fetchEvents()
            
            // 少し待ってから状態確認
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                print("🔄 2秒後の状態確認:")
                print("  - 全イベント数: \(firebaseService.events.count)")
                print("  - フィルタ後イベント数: \(filteredEvents.count)")
                print("  - 読み込み中?: \(firebaseService.isLoading)")
                for (index, event) in filteredEvents.enumerated() {
                    print("  [\(index)] '\(event.title)' - content: \(event.content.count)文字")
                }
            }
        }
    }
    
    // MARK: - Loading View
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("イベントを読み込み中...")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Empty State View
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("イベントがありません")
                .font(.title2)
                .fontWeight(.medium)
            
            Text("Firebaseの「event」コレクションにイベントデータがありません")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Error State View
    private var errorStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 60))
                .foregroundColor(.red)
            
            Text("イベント情報が取得できませんでした。")
                .font(.title2)
                .fontWeight(.medium)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Event Title List
    private var eventTitleList: some View {
        List {
            ForEach(filteredEvents) { event in
                EventTitleRow(event: event) {
                    print("🔍 EventTitleRow onTap 実行")
                    print("  - event.title: '\(event.title)'")
                    print("  - event.content: \(event.content.count)文字")
                    print("  - event.id: '\(event.id ?? "nil")'")
                    
                    print("🔍 状態更新前:")
                    print("  - selectedEvent == nil: \(selectedEvent == nil)")
                    print("  - showingEventContent: \(showingEventContent)")
                    
                    selectedEvent = event
                    showingEventContent = true
                    
                    print("🔍 状態更新後:")
                    print("  - selectedEvent == nil: \(selectedEvent == nil)")
                    print("  - selectedEvent?.title: '\(selectedEvent?.title ?? "nil")'")
                    print("  - showingEventContent: \(showingEventContent)")
                    
                    // 少し遅れてもう一度確認
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        print("🔍 0.1秒後の状態確認:")
                        print("  - selectedEvent == nil: \(selectedEvent == nil)")
                        print("  - selectedEvent?.title: '\(selectedEvent?.title ?? "nil")'")
                        print("  - showingEventContent: \(showingEventContent)")
                    }
                }
            }
        }
    }
    
}

// MARK: - Sheet Content View
/// シート表示用のビュー（ログ付き）
struct SheetContentView: View {
    let selectedEvent: Event?
    let onMemoCreated: ((Memo) -> Void)?
    @State private var debugMessage = ""
    
    var body: some View {
        Group {
            if let selectedEvent = selectedEvent {
                EventContentView(event: selectedEvent, onMemoCreated: onMemoCreated)
            } else {
                VStack {
                    Text("エラー: イベントが選択されていません")
                        .foregroundColor(.red)
                }
            }
        }
        .onAppear {
            print("🔍 SheetContentView.body が呼ばれました")
            print("  - selectedEvent != nil: \(selectedEvent != nil)")
            if let event = selectedEvent {
                print("  - selectedEvent.title: '\(event.title)'")
                print("  - selectedEvent.content: \(event.content.count)文字")
            }
        }
    }
}

// MARK: - Event Title Row
/// イベントタイトル行ビュー
struct EventTitleRow: View {
    let event: Event
    let onTap: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                // 応募締切日と開催日の表示
                HStack {
                    if let deadlineDate = event.formattedDeadlineDate {
                        Text("締切: \(deadlineDate)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    if let eventDate = event.formattedEventDate {
                        Text("開催: \(eventDate)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // 会場と定員の表示
                HStack {
                    if let venue = event.venue, !venue.isEmpty {
                        Text("会場: \(venue)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    if let capacity = event.capacity, !capacity.isEmpty {
                        Text("定員: \(capacity)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .opacity((event.venue?.isEmpty != false && event.capacity?.isEmpty != false) ? 0 : 1)
                .frame(height: (event.venue?.isEmpty != false && event.capacity?.isEmpty != false) ? 0 : nil)
                
                // 対象の表示
                if let target = event.target, !target.isEmpty {
                    Text("対象: \(target)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                if event.content.isEmpty {
                    Text("内容が空です")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle()) // 全体をタップ可能にする
        .onTapGesture {
            // 🎯 イベント選択時の詳細ログ出力
            print("🎯🎯🎯 === イベント選択タイミング ===")
            print("📱 イベントタイトルがタップされました:")
            print("  - タイトル: '\(event.title)'")
            print("  - タイトル文字数: \(event.title.count) 文字")
            print("  - 内容文字数: \(event.content.count) 文字")
            print("  - 内容が空?: \(event.content.isEmpty)")
            print("  - ID: '\(event.id ?? "nil")'")
            print("  - 内容の最初の200文字:")
            print("    '\(event.content.prefix(200))...'")
            if event.content.count > 200 {
                print("  - 内容の最後の100文字:")
                print("    '...\(event.content.suffix(100))'")
            }
            print("🎯🎯🎯 ========================")
            onTap()
        }
        .onAppear {
            // リスト表示時のデバッグ情報
            print("📝 EventTitleRow表示: '\(event.title)' - 内容: \(event.content.count)文字")
            print("  - venue: '\(event.venue ?? "nil")'")
            print("  - capacity: '\(event.capacity ?? "nil")'")
            print("  - target: '\(event.target ?? "nil")'")
        }
    }
}

// MARK: - Event Content View
/// イベント内容表示ビュー（マークダウンプレビュー）
struct EventContentView: View {
    let event: Event
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var memoStore: MemoStore
    
    var onMemoCreated: ((Memo) -> Void)?
    
    @State private var displayTitle: String
    @State private var displayContent: String
    @State private var isLoading = true
    @State private var loadingMessage = "読み込み中..."
    
    // 初期化時に即座にデータを設定
    init(event: Event, onMemoCreated: ((Memo) -> Void)? = nil) {
        self.event = event
        self.onMemoCreated = onMemoCreated
        
        // State変数を初期値で初期化
        self._displayTitle = State(initialValue: event.title)
        self._displayContent = State(initialValue: event.content)
        self._isLoading = State(initialValue: event.content.isEmpty)
        
        print("🎯 EventContentView init()")
        print("  - event.title: '\(event.title)'")
        print("  - event.content: \(event.content.count)文字")
        print("  - 初期isLoading: \(event.content.isEmpty)")
    }
    
    var body: some View {
        NavigationView {
            VStack {
                if isLoading {
                    // 読み込み中表示
                    VStack(spacing: 16) {
                        ProgressView()
                        Text(loadingMessage)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // 内容表示
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            // タイトル表示（中央揃え）
                            Text(displayTitle)
                                .font(.title)
                                .fontWeight(.bold)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .onAppear {
                                    print("🔍 タイトルTextが表示されました: '\(displayTitle)'")
                                }
                            
                            Divider()
                                .onAppear {
                                    print("🔍 Dividerが表示されました")
                                }
                            
                            // 内容表示
                            if !displayContent.isEmpty {
                                MarkdownText(displayContent)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                VStack(spacing: 12) {
                                    Text("内容が読み込めませんでした")
                                        .font(.body)
                                        .foregroundColor(.secondary)
                                    
                                    Button("再読み込み") {
                                        retryLoading()
                                    }
                                    .buttonStyle(.bordered)
                                }
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 40)
                            }
                            
                            Spacer(minLength: 20)
                        }
                        .padding()
                        .onAppear {
                            print("🔍 メインコンテンツのVStackが表示されました")
                        }
                    }
                    .onAppear {
                        print("🔍 ScrollViewが表示されました")
                    }
                }
            }
            .onAppear {
                print("🔍 外側のVStackが表示されました")
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("閉じる") {
                        print("🔍 閉じるボタンがタップされました")
                        dismiss()
                    }
                    .onAppear {
                        print("🔍 閉じるボタンが表示されました")
                    }
                }
                
                ToolbarItem(placement: .principal) {
                    // 自己分析ボタン（中央）
                    if let analysisTemplate = event.analysis_template, !analysisTemplate.isEmpty {
                        Button("自己分析") {
                            createMemoFromTemplate(analysisTemplate)
                        }
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    // 応募ボタン
                    if let applicationFormURL = event.application_form_url, !applicationFormURL.isEmpty {
                        Button("応募") {
                            openApplicationForm(applicationFormURL)
                        }
                    }
                }
            }
            .onAppear {
                print("🔍 NavigationViewの中身が表示されました")
                print("🔍 Event データ詳細:")
                print("  - id: \(event.id ?? "nil")")
                print("  - title: '\(event.title)'")
                print("  - content length: \(event.content.count)")
                print("  - application_form_url: '\(event.application_form_url ?? "nil")'")
                print("  - analysis_template: '\(event.analysis_template ?? "nil")'")
                print("  - analysis_template isEmpty: \(event.analysis_template?.isEmpty ?? true)")
                print("  - application_form_url isEmpty: \(event.application_form_url?.isEmpty ?? true)")
                
                print("🚨🚨🚨 FIREBASE フィールド絶対確認 🚨🚨🚨")
                if let url = event.application_form_url {
                    print("✅ APPLICATION_FORM_URL 存在: '\(url)'")
                    print("✅ URL長さ: \(url.count) 文字")
                    print("✅ URL空文字チェック: \(url.isEmpty ? "空" : "データあり")")
                } else {
                    print("❌ APPLICATION_FORM_URL が nil です")
                }
                
                if let analysisTemplate = event.analysis_template {
                    print("✅ ANALYSIS_TEMPLATE 存在: '\(analysisTemplate.prefix(200))...'")
                    print("✅ テンプレート長さ: \(analysisTemplate.count) 文字")
                    print("✅ テンプレート空文字チェック: \(analysisTemplate.isEmpty ? "空" : "データあり")")
                } else {
                    print("❌ ANALYSIS_TEMPLATE が nil です")
                }
                print("🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨")
            }
        }
        .onAppear {
            print("🔍 EventContentView.body が呼ばれました")
            print("  - isLoading: \(isLoading)")
            print("  - displayTitle: '\(displayTitle)'")
            print("  - displayContent文字数: \(displayContent.count)")
            print("🔍 NavigationView全体が表示されました")
            startLoadingProcess()
        }
    }
    
    /// イベント読み込みプロセスを開始（段階的に丁寧に実行）
    private func startLoadingProcess() {
        print("🎯 === イベント詳細読み込み開始 ===")
        print("🎯 イベントID: '\(event.id ?? "nil")'")
        print("🎯 イベントタイトル: '\(event.title)'")
        print("🎯 イベント内容文字数: \(event.content.count)")
        
        // ステップ1: まず渡されたイベント情報を確実に表示
        step1_SetInitialData()
    }
    
    /// ステップ1: 初期データを設定
    private func step1_SetInitialData() {
        print("📋 ステップ1: 初期データ設定")
        print("📋 受け取ったevent.title: '\(event.title)'")
        print("📋 受け取ったevent.content: \(event.content.count)文字")
        print("📋 受け取ったevent.content内容: '\(event.content.prefix(100))...'")
        
        // 即座に初期データを設定（DispatchQueue.main.asyncを使わない）
        self.displayTitle = self.event.title
        self.displayContent = self.event.content
        self.loadingMessage = "初期データ設定中..."
        
        print("✅ 初期データ設定完了:")
        print("  - displayTitle: '\(self.displayTitle)'")
        print("  - displayContent: \(self.displayContent.count)文字")
        print("  - displayContent内容: '\(self.displayContent.prefix(100))...'")
        
        // 内容があればそのまま表示完了
        if !self.event.content.isEmpty {
            print("✅ 初期データに内容あり - 即座に表示完了")
            self.isLoading = false
            
            // 強制的にUI更新を確実にする
            DispatchQueue.main.async {
                print("🔄 UI更新強制実行")
                print("  - 最終確認 displayTitle: '\(self.displayTitle)'")
                print("  - 最終確認 displayContent: \(self.displayContent.count)文字")
                print("  - 最終確認 isLoading: \(self.isLoading)")
            }
        } else {
            print("⚠️ 初期データに内容なし - Firebaseから取得開始")
            self.step2_LoadFromFirebase()
        }
    }
    
    /// ステップ2: Firebaseから詳細データを取得
    private func step2_LoadFromFirebase() {
        print("🔥 ステップ2: Firebase取得開始")
        
        guard let eventId = event.id else {
            print("❌ イベントIDなし - 読み込み終了")
            isLoading = false
            return
        }
        
        DispatchQueue.main.async {
            self.loadingMessage = "Firebaseから取得中..."
        }
        
        let db = Firestore.firestore()
        
        // 最も確実な方法でFirebaseから取得
        db.collection("event").document(eventId).getDocument { document, error in
            DispatchQueue.main.async {
                self.step3_ProcessFirebaseResult(document: document, error: error)
            }
        }
    }
    
    /// ステップ3: Firebase取得結果を処理
    private func step3_ProcessFirebaseResult(document: DocumentSnapshot?, error: Error?) {
        print("📥 ステップ3: Firebase結果処理")
        
        if let error = error {
            print("❌ Firebase取得エラー: \(error)")
            self.step4_HandleError()
            return
        }
        
        guard let document = document, document.exists else {
            print("❌ ドキュメント存在しない")
            self.step4_HandleError()
            return
        }
        
        let data = document.data() ?? [:]
        print("🔍 取得データ:")
        print("  - title: '\(data["title"] ?? "nil")'")
        print("  - content: '\(data["content"] ?? "nil")'")
        
        // データを確実に設定
        if let title = data["title"] as? String,
           let content = data["content"] as? String {
            
            print("✅ データ取得成功 - UI更新")
            self.displayTitle = title
            self.displayContent = content
            self.isLoading = false
            
            print("🎉 読み込み完了!")
            print("  - 最終タイトル: '\(self.displayTitle)'")
            print("  - 最終内容: \(self.displayContent.count)文字")
            
        } else {
            print("❌ データ形式エラー")
            self.step4_HandleError()
        }
    }
    
    /// ステップ4: エラー処理
    private func step4_HandleError() {
        print("❌ ステップ4: エラー処理")
        
        DispatchQueue.main.async {
            self.isLoading = false
            self.loadingMessage = "読み込みに失敗しました"
            
            // 最低限、タイトルは表示
            if self.displayTitle.isEmpty {
                self.displayTitle = self.event.title
            }
            
            print("⚠️ エラー処理完了 - 可能な限り表示")
        }
    }
    
    /// 再読み込み処理
    private func retryLoading() {
        print("🔄 再読み込み開始")
        
        isLoading = true
        displayTitle = ""
        displayContent = ""
        loadingMessage = "再読み込み中..."
        
        startLoadingProcess()
    }
    
    private func createMemoFromTemplate(_ analysisTemplate: String) {
        print("📝 自己分析テンプレートからメモ作成: \(analysisTemplate.prefix(50))")
        
        // プロフィール情報を取得
        let profileManager = ProfileManager.shared
        let profileText = profileManager.generateProfileText()
        
        // テンプレートにプロフィール情報を追加
        var finalTemplate = analysisTemplate
        if !profileText.isEmpty {
            finalTemplate += "\n\n---\n\n\(profileText)"
        }
        
        // 新規メモを作成（タイトルは本文から抽出）
        let newMemo = Memo(title: "", content: finalTemplate)
        
        // MemoStoreに追加
        memoStore.addMemo(newMemo)
        
        print("✅ 自己分析メモ作成完了: \(newMemo.title)")
        
        // コールバックで作成したメモを編集画面で開く
        onMemoCreated?(newMemo)
        
        // イベント詳細画面を閉じる
        dismiss()
    }
    
    private func openApplicationForm(_ urlString: String) {
        print("🌐 応募フォームURL起動: \(urlString)")
        
        guard let url = URL(string: urlString) else {
            print("❌ 無効なURL: \(urlString)")
            return
        }
        
        UIApplication.shared.open(url)
        print("✅ ブラウザでURL起動完了")
    }
}


#Preview {
    EventListView()
        .environmentObject(FirebaseService.shared)
}
