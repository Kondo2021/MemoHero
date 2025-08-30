import SwiftUI
import PhotosUI
import WebKit
import UniformTypeIdentifiers
import UserNotifications

// MARK: - Error Types
enum MemoEditorError: Error, LocalizedError {
    case contentTooLarge(size: Int)
    case invalidMemoState
    case saveOperationFailed(underlyingError: Error)
    
    var errorDescription: String? {
        switch self {
        case .contentTooLarge(let size):
            return "メモのサイズが制限を超えています: \(size) 文字"
        case .invalidMemoState:
            return "メモの状態が無効です"
        case .saveOperationFailed(let error):
            return "保存操作に失敗しました: \(error.localizedDescription)"
        }
    }
}

// MARK: - MemoEditorView
/// メモの編集・表示を行うメインビュー
/// マークダウンプレビュー、検索・置換、画像追加などの機能を提供
struct MemoEditorView: View {
    // MARK: - Properties
    /// 編集中のメモデータ
    @State private var memo: Memo
    /// 元のメモデータ（キャンセル時の復元用）
    @State private var originalMemo: Memo
    /// マークダウンプレビューモードの状態
    @State private var isMarkdownPreview: Bool = false
    /// セグメントコントロール用の選択状態 (0: 編集, 1: プレビュー)
    @State private var editorMode: Int = 0
    /// 新規メモかどうかのフラグ
    private let isNewMemo: Bool
    
    // MARK: - Search & Replace Properties
    /// 検索テキスト
    @State private var searchText = ""
    /// 置換テキスト
    @State private var replaceText = ""
    /// 検索モードの状態
    @State private var isSearching = false
    /// 置換モードの状態
    @State private var isReplaceMode = false
    /// 検索結果の範囲配列
    @State private var searchResults: [NSRange] = []
    /// 現在の検索結果インデックス
    @State private var currentSearchIndex = 0
    
    /// テキスト選択範囲
    @State private var selectedRange: NSRange? = nil
    
    // MARK: - UI State Properties
    /// ファイルエクスポート画面の表示状態
    @State private var showingFileExporter = false
    /// 写真選択画面の表示状態
    @State private var showingImagePicker = false
    /// 選択された写真アイテム
    @State private var selectedPhotoItem: PhotosPickerItem?
    /// 写真権限アラートの表示状態
    @State private var showingPhotoPermissionAlert = false
    /// ファイル選択画面の表示状態
    @State private var showingFileImporter = false
    /// 画像選択方法の確認ダイアログの表示状態
    @State private var showingImageSourceSelection = false
    /// 編集開始時のメモ内容（変更検知用）
    @State private var originalContent: String = ""
    /// 明示的に完了ボタンが押されたかどうか
    @State private var isExplicitlySaved = false
    /// 明示的に破棄が選択されたかどうか
    @State private var isExplicitlyDiscarded = false
    /// 一度でも内容が入力されたかどうか（自動削除防止用）
    @State private var hasHadContent = false
    /// ユーザーが実際に編集したかどうか（クリップボード・テンプレート用）
    @State private var hasUserEdited = false
    /// 共有機能の表示状態
    @State private var showingShareSheet = false
    /// 生成されたPDFデータ
    @State private var pdfData: Data?
    /// PDFエクスポート画面の表示状態
    @State private var showingPDFExporter = false
    /// 全てクリア確認ダイアログの表示状態
    @State private var showingClearConfirmation = false
    
    // MARK: - Dependencies
    /// メモストア（データ管理）
    let memoStore: MemoStore
    /// フォルダストア（環境オブジェクト）
    @EnvironmentObject private var folderStore: FolderStore
    /// アプリ設定（シングルトン）
    @StateObject private var appSettings = AppSettings.shared
    /// 通知管理（シングルトン）
    @StateObject private var notificationManager = NotificationManager.shared
    /// 画面閉じる時のコールバック
    let onDismiss: () -> Void
    /// 編集状態変更時のコールバック
    let onEditingStateChanged: (Bool) -> Void
    /// メモ更新時のコールバック
    let onMemoUpdated: (Memo) -> Void
    
    // MARK: - Computed Properties
    /// 文字数カウント
    private var characterCount: Int {
        memo.content.count
    }
    
    /// メモに変更があるかどうか
    private var hasChanges: Bool {
        memo.content != originalContent
    }
    
    /// 単語数カウント（空白文字区切り）
    private var wordCount: Int {
        memo.content.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .count
    }
    
    /// 行数カウント
    private var lineCount: Int {
        if memo.content.isEmpty {
            return 0
        }
        return memo.content.components(separatedBy: .newlines).count
    }
    
    // MARK: - Number Format Helpers
    
    /// インデントレベルに応じた番号形式を取得
    /// - Parameters:
    ///   - number: 番号
    ///   - indentLevel: インデントレベル (0=数字, 1=①, 2=ローマ数字, 3=小文字アルファベット)
    /// - Returns: フォーマットされた番号文字列
    private func formatNumberForIndentLevel(_ number: Int, indentLevel: Int) -> String {
        switch indentLevel {
        case 0:
            return "\(number)"
        case 1:
            return convertToCircledNumber(number)
        case 2:
            return convertToRomanNumeral(number)
        case 3:
            return convertToLowerAlphabet(number)
        default:
            // 4レベル以上は通常の数字に戻す
            return "\(number)"
        }
    }
    
    /// 数字を①②③形式に変換（1-50まで対応）
    private func convertToCircledNumber(_ number: Int) -> String {
        let circledNumbers = ["①", "②", "③", "④", "⑤", "⑥", "⑦", "⑧", "⑨", "⑩",
                             "⑪", "⑫", "⑬", "⑭", "⑮", "⑯", "⑰", "⑱", "⑲", "⑳",
                             "㉑", "㉒", "㉓", "㉔", "㉕", "㉖", "㉗", "㉘", "㉙", "㉚",
                             "㉛", "㉜", "㉝", "㉞", "㉟", "㊱", "㊲", "㊳", "㊴", "㊵",
                             "㊶", "㊷", "㊸", "㊹", "㊺", "㊻", "㊼", "㊽", "㊾", "㊿"]
        
        if number >= 1 && number <= circledNumbers.count {
            return circledNumbers[number - 1]
        } else {
            return "\(number)" // 範囲外は通常の数字
        }
    }
    
    /// 数字をローマ数字に変換（1-50まで対応）
    private func convertToRomanNumeral(_ number: Int) -> String {
        if number < 1 || number > 50 {
            return "\(number)" // 範囲外は通常の数字
        }
        
        let values = [40, 10, 9, 5, 4, 1]
        let symbols = ["xl", "x", "ix", "v", "iv", "i"]
        
        var result = ""
        var num = number
        
        for (i, value) in values.enumerated() {
            let count = num / value
            if count > 0 {
                result += String(repeating: symbols[i], count: count)
                num %= value
            }
        }
        
        return result
    }
    
    /// 数字を小文字アルファベットに変換（1-26まで対応）
    private func convertToLowerAlphabet(_ number: Int) -> String {
        if number < 1 || number > 26 {
            return "\(number)" // 範囲外は通常の数字
        }
        
        let alphabets = ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z"]
        return alphabets[number - 1]
    }
    
    
    // MARK: - Initializer
    /// MemoEditorViewの初期化
    /// - Parameters:
    ///   - memo: 編集するメモ（nilの場合は新規メモを作成）
    ///   - memoStore: メモストア
    ///   - isNewMemo: 新規メモかどうか
    ///   - onDismiss: 画面閉じる時のコールバック
    init(memo: Memo?, memoStore: MemoStore, isNewMemo: Bool = false, onDismiss: @escaping () -> Void, onEditingStateChanged: @escaping (Bool) -> Void = { _ in }, onMemoUpdated: @escaping (Memo) -> Void = { _ in }) {
        print("==== MemoEditorView初期化開始 ====")
        print("init - 受け取ったmemoパラメータ:")
        if let memo = memo {
            print("  - memo ID: \(memo.id)")
            print("  - memo content: '\(memo.content.prefix(100))'")
            print("  - memo title: '\(memo.title)'")
            print("  - memo 作成日: \(memo.createdAt)")
            print("  - memo 更新日: \(memo.updatedAt)")
        } else {
            print("  - memo: nil")
        }
        
        let memoToEdit = memo ?? Memo()
        print("init - 実際に使用するmemo:")
        print("  - memoToEdit ID: \(memoToEdit.id)")
        print("  - memoToEdit content: '\(memoToEdit.content.prefix(100))'")
        print("  - memoToEdit title: '\(memoToEdit.title)'")
        print("  - isNewMemo: \(isNewMemo)")
        
        self._memo = State(initialValue: memoToEdit)
        self._originalMemo = State(initialValue: memoToEdit)
        self.memoStore = memoStore
        self.isNewMemo = isNewMemo
        self.onDismiss = onDismiss
        self.onEditingStateChanged = onEditingStateChanged
        self.onMemoUpdated = onMemoUpdated
        
        // 新規メモのみ編集モード、既存メモは全てプレビューモードで開始
        if isNewMemo {
            self._isMarkdownPreview = State(initialValue: false)
            self._editorMode = State(initialValue: 0)
            print("  - 新規メモなので編集モードで開始")
        } else {
            self._isMarkdownPreview = State(initialValue: true)
            self._editorMode = State(initialValue: 1)
            print("  - 既存メモなのでプレビューモードで開始")
        }
        print("==== MemoEditorView初期化完了 ====\n")
    }
    
    // MARK: - Body
    var body: some View {
        VStack(spacing: 0) {
            // ツールバー（プレビューボタン、書式メニューなど）
            toolbarView
            
            // 検索バー（検索モード時のみ表示）
            if isSearching {
                searchBarView
            }
            
            // メインコンテンツエリア（プレビューまたはテキストエディタ）
            if isMarkdownPreview && appSettings.isMarkdownEnabled {
                markdownPreviewView
            } else {
                textEditorView
            }
            
            // ステータスバー（文字数、編集時間など）
            statusBarView
        }
        // スワイプダウンで閉じる機能
        .gesture(
            DragGesture()
                .onEnded { value in
                    // 下向きスワイプ（Y軸で100ポイント以上の移動）
                    if value.translation.height > 100 && abs(value.translation.width) < 50 {
                        print("🔄 スワイプダウンで強制保存して戻る")
                        saveMemo()  // 変更の有無に関係なく強制保存
                        onDismiss()
                    }
                }
        )
        // ナビゲーション設定
        .navigationTitle(isMarkdownPreview && !hasChanges ? "メモ表示" : "メモ編集")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        // ファイルエクスポート機能
        .fileExporter(
            isPresented: $showingFileExporter,
            document: MarkdownDocument(content: memo.content),
            contentType: .plainText,
            defaultFilename: "\(memo.displayTitle).md"
        ) { result in
            switch result {
            case .success(let url):
                print("ファイルが保存されました: \(url)")
            case .failure(let error):
                print("保存エラー: \(error)")
            }
        }
        // PDF共有機能
        .sheet(isPresented: $showingShareSheet) {
            if let pdfData = pdfData {
                ShareSheet(activityItems: [pdfData])
            }
        }
        // PDFファイルエクスポート機能
        .fileExporter(
            isPresented: $showingPDFExporter,
            document: PDFDocument(data: pdfData ?? Data()),
            contentType: .pdf,
            defaultFilename: "\(memo.displayTitle).pdf"
        ) { result in
            switch result {
            case .success(let url):
                print("PDFが保存されました: \(url)")
            case .failure(let error):
                print("PDF保存エラー: \(error)")
            }
        }
        // 画像選択方法の確認ダイアログ
        .confirmationDialog("画像の選択方法", isPresented: $showingImageSourceSelection) {
            Button("写真から選択") {
                selectFromPhotos()
            }
            Button("ファイルから選択") {
                selectFromFiles()
            }
            Button("キャンセル", role: .cancel) {}
        }
        // 写真選択
        .photosPicker(
            isPresented: $showingImagePicker,
            selection: $selectedPhotoItem,
            matching: .images,
            photoLibrary: .shared()
        )
        .onChange(of: selectedPhotoItem) {
            handleSelectedPhoto()
            selectedPhotoItem = nil
        }
        // ファイル選択
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            handleFileImportResult(result)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                if hasChanges || !isMarkdownPreview {
                    Button("完了") {
                        print("🔴 編集完了 - メモ ID: \(memo.id.uuidString.prefix(8))")
                        isExplicitlySaved = true
                        saveMemo()
                        onDismiss()
                    }
                    .fontWeight(.semibold)
                } else {
                    Button("戻る") {
                        print("↩️ メモ表示から戻る - メモ ID: \(memo.id.uuidString.prefix(8))")
                        print("🔄 強制保存して戻る")
                        saveMemo()  // 変更の有無に関係なく強制保存
                        onDismiss()
                    }
                }
            }
            
            if hasChanges || !isMarkdownPreview {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("キャンセル") {
                        print("❌ 編集キャンセル - メモ ID: \(memo.id.uuidString.prefix(8))")
                        handleCancel()
                    }
                }
            }
            
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if !isMarkdownPreview {
                    Button(action: toggleSearch) {
                        Image(systemName: "magnifyingglass")
                    }
                }
                
                Menu {
                    Button(action: showClearConfirmation) {
                        HStack {
                            Image(systemName: "trash")
                            Text("すべてクリア")
                        }
                    }
                    .disabled(memo.content.isEmpty)
                    
                    Button(action: showShareOptions) {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("共有")
                        }
                    }
                    .disabled(memo.content.isEmpty)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .onAppear {
            // 編集開始時の内容を記録
            originalContent = memo.content
            print("📝 編集開始時のメモ内容を記録: \(originalContent.count) 文字")
            
            // 初期状態で内容があるかチェック
            hasHadContent = !memo.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !memo.title.isEmpty
            
            // メインスレッドでの重い処理を避けるため、バックグラウンドで初期化処理を実行
            DispatchQueue.global(qos: .userInitiated).async {
                let timestamp = DateFormatter.debugFormatter.string(from: Date())
                print("🧵 バックグラウンドスレッドの開始 - MemoEditorView.onAppear 初期化処理 [\(timestamp)]")
                print("👁️ MemoEditorView.onAppear 呼び出し [\(timestamp)]")
                print("   メモ ID: \(memo.id.uuidString.prefix(8))")
                print("   isMarkdownPreview: \(isMarkdownPreview)")
                print("   isNewMemo: \(isNewMemo)")
                print("   hasHadContent: \(hasHadContent)")
                print("   MemoStore初期化状態: \(memoStore.isInitialized)")
                
            }
        }
        .onDisappear {
            // 削除条件を判定
            let shouldDelete = isNewMemo && (
                // 1. 元々空で、何も変更されていない場合
                (originalContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && 
                 memo.title.isEmpty && 
                 !hasHadContent) ||
                // 2. クリップボード・テンプレートから作成されたが、ユーザーが編集していない場合
                (!originalContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && 
                 !hasUserEdited && 
                 !isExplicitlySaved)
            )
            
            if shouldDelete {
                print("🗑️ 新規メモを自動削除: \(memo.id.uuidString.prefix(8)), 理由: \(originalContent.isEmpty ? "空メモ" : "未編集")")
                memoStore.deleteMemo(memo)
                return
            }
            
            // 保存処理の判定 - キャンセル以外はすべて保存
            if isExplicitlyDiscarded {
                // キャンセルボタンで破棄が選択された場合のみ保存しない
                print("🗑️ キャンセルによる破棄 - 保存をスキップ")
            } else {
                // キャンセル以外のすべての終了パターンで保存
                print("💾 自動保存実行 - すべての変更を保存")
                saveMemo()
            }
        }
        .alert("全てクリア", isPresented: $showingClearConfirmation) {
            Button("クリア", role: .destructive) {
                clearText()
            }
            Button("キャンセル", role: .cancel) {
                // 何もしない
            }
        } message: {
            Text("メモの内容を全て削除しますか？この操作は取り消すことができません。")
        }
    }
    
    // MARK: - UI Components
    /// ツールバービュー（プレビューボタンと書式メニュー）
    private var toolbarView: some View {
        HStack {
            Spacer()
            
            // セグメントコントロール（プレビュー/編集切り替え）
            if appSettings.isMarkdownEnabled {
                Picker("モード選択", selection: $editorMode) {
                    Text("プレビュー").tag(1)
                    Text("編集").tag(0)
                }
                .pickerStyle(SegmentedPickerStyle())
                .frame(width: 160)
                .onChange(of: editorMode) { oldValue, newValue in
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isMarkdownPreview = newValue == 1
                        onEditingStateChanged(newValue == 0)
                    }
                }
            }
            
            Spacer()
        }
        .padding()
        .background(Color(.systemGray6))
    }
    
    private var textEditorView: some View {
        HighlightableTextEditor(
            text: $memo.content,
            searchResults: searchResults,
            currentIndex: currentSearchIndex,
            onTextChange: { newText in
                let timestamp = DateFormatter.debugFormatter.string(from: Date())
                print("📝 MemoEditorView.onTextChange 呼び出し [\(timestamp)]")
                print("   新しいテキスト長: \(newText.count)")
                
                // メモ内容の更新のみ行い、保存処理は行わない
                memo.content = newText
                
                // 内容が変更されたことを記録
                if newText != originalContent {
                    hasUserEdited = true
                }
                
                // 内容が入力されたことを記録（自動削除防止）
                if !newText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    hasHadContent = true
                }
                
                // 編集状態を通知（UI更新用）
                onEditingStateChanged(true)
                
                // 編集内容をMemoListViewに通知（保存はしない）
                onMemoUpdated(memo)
                
                print("   メモ内容更新完了（保存処理はスキップ）")
                print("✅ MemoEditorView.onTextChange 完了")
            },
            selectedRange: $selectedRange,
            onInsertSyntax: appSettings.isMarkdownEnabled ? insertMarkdownSyntax : nil,
            onInsertHeading: appSettings.isMarkdownEnabled ? insertHeadingSyntax : nil,
            onInsertTable: appSettings.isMarkdownEnabled ? insertMarkdownTable : nil,
            onInsertImage: appSettings.isMarkdownEnabled ? showImagePicker : nil
        )
        .padding()
        .background(Color(.systemBackground))
    }
    
    private var markdownPreviewView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    MarkdownText(memo.content, onToggleChecklist: toggleChecklistItem, onLinkTap: { anchor in
                        // 内部リンクの場合のスクロール処理
                        if anchor.hasPrefix("#") {
                            let headingId = String(anchor.dropFirst())
                            withAnimation(.easeInOut(duration: 0.8)) {
                                proxy.scrollTo(headingId, anchor: .top)
                            }
                        }
                    }, enableChapterNumbering: appSettings.isChapterNumberingEnabled)
                        .padding()
                }
            }
        }
        .background(Color(.systemBackground))
    }
    
    private var statusBarView: some View {
        HStack {
            Text("文字数: \(characterCount)")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text("行数: \(lineCount)")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.leading, 12)
            
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
    }
    
    /// 全てクリア確認ダイアログを表示
    private func showClearConfirmation() {
        showingClearConfirmation = true
    }
    
    /// テキストをクリア
    private func clearText() {
        memo.content = ""
        // クリア時も保存はしない（最終的に完了ボタンで保存）
        print("🗑️ テキストクリア - 保存処理はスキップ")
    }
    
    
    
    private func saveMemo() {
        let timestamp = DateFormatter.debugFormatter.string(from: Date())
        print("💾 MemoEditorView.saveMemo() 呼び出し [\(timestamp)]")
        print("   メモ ID: \(memo.id.uuidString.prefix(8))")
        print("   メモ内容長: \(memo.content.count) 文字")
        print("   フォルダ: \(memo.folderId?.uuidString.prefix(8) ?? "nil")")
        print("   MemoStore初期化状態: \(memoStore.isInitialized)")
        
        do {
            // ストアが初期化完了していない場合は保存をスキップ
            guard memoStore.isInitialized else {
                print("❌ MemoEditorView - ストア初期化未完了のため保存をスキップ")
                return
            }
            
            // メモの内容検証
            if memo.content.count > 1_000_000 {  // 1MB制限
                print("⚠️ メモサイズが大きすぎます: \(memo.content.count) 文字")
                throw MemoEditorError.contentTooLarge(size: memo.content.count)
            }
            
            // 変更がある場合のみ更新日を更新
            if hasChanges {
                print("   変更検出: memo.updateContent() 呼び出し前")
                memo.updateContent(memo.content)
                print("   memo.updateContent() 完了")
            } else {
                print("   変更なし: memo.updateContent() をスキップ")
            }
            
            print("   memoStore.updateMemo() 呼び出し")
            memoStore.updateMemo(memo)
            
            print("✅ MemoEditorView.saveMemo() 完了 [\(DateFormatter.debugFormatter.string(from: Date()))]")
            
        } catch {
            print("❌ ERROR: MemoEditorView.saveMemo()中にエラーが発生 [\(DateFormatter.debugFormatter.string(from: Date()))]")
            print("   エラー詳細: \(error)")
            print("   メモ ID: \(memo.id.uuidString.prefix(8))")
            print("   エラータイプ: \(type(of: error))")
            
            // エラーを記録するが、UIの動作は継続
            if let memoError = error as? MemoEditorError {
                print("   MemoEditorError: \(memoError.localizedDescription)")
            }
        }
    }
    
    
    /// 現在の編集内容を取得
    func getCurrentMemo() -> Memo {
        return memo
    }
    
    
    @State private var saveTimer: Timer?
    
    private func saveMemoDebounced() {
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
            saveMemo()
        }
    }
    
    private func toggleChecklistItem(at lineIndex: Int) {
        let lines = memo.content.components(separatedBy: CharacterSet.newlines)
        guard lineIndex < lines.count else { return }
        
        var modifiedLines = lines
        let line = lines[lineIndex]
        
        if line.hasPrefix("- [x] ") {
            // チェック済み → 未チェックに変更
            modifiedLines[lineIndex] = line.replacingOccurrences(of: "- [x] ", with: "- [ ] ")
        } else if line.hasPrefix("- [ ] ") {
            // 未チェック → チェック済みに変更
            modifiedLines[lineIndex] = line.replacingOccurrences(of: "- [ ] ", with: "- [x] ")
        }
        
        memo.content = modifiedLines.joined(separator: "\n")
        print("☑️ チェックリスト項目トグル - 保存処理はスキップ")
    }
    
    /// 見出し書式を現在の行の先頭に挿入する
    private func insertHeadingSyntax(_ headingLevel: String) {
        let currentRange = selectedRange ?? NSRange(location: memo.content.count, length: 0)
        let currentPosition = currentRange.location
        
        // 現在のカーソル位置から行の開始位置を探す
        let nsString = memo.content as NSString
        var lineStart = 0
        
        if currentPosition > 0 {
            // 現在位置から前方向に検索して行の開始を見つける
            for i in stride(from: currentPosition - 1, through: 0, by: -1) {
                let char = nsString.character(at: i)
                if char == 10 { // 改行文字（\n）
                    lineStart = i + 1
                    break
                }
            }
        }
        
        // 行の開始位置から既存の見出し記号（#）を確認し、削除する
        var insertPosition = lineStart
        var existingHeadingLength = 0
        
        // 行の開始から見出し記号をスキャン
        while insertPosition < nsString.length {
            let char = nsString.character(at: insertPosition)
            if char == 35 { // '#' 文字
                existingHeadingLength += 1
                insertPosition += 1
            } else if char == 32 { // スペース文字
                if existingHeadingLength > 0 {
                    existingHeadingLength += 1
                    insertPosition += 1
                    break
                } else {
                    break
                }
            } else {
                break
            }
        }
        
        // 既存の見出し記号を削除し、新しい見出し記号を挿入
        let deleteRange = NSRange(location: lineStart, length: existingHeadingLength)
        let newHeadingText = headingLevel + " "
        
        memo.content = nsString.replacingCharacters(in: deleteRange, with: newHeadingText)
        
        // カーソル位置を行末に移動
        let newCursorPosition = lineStart + newHeadingText.count + (currentPosition - insertPosition)
        selectedRange = NSRange(location: max(0, newCursorPosition), length: 0)
        
        print("✏️ 見出し書式挿入（行先頭）- 保存処理はスキップ")
    }
    
    private func insertMarkdownSyntax(_ syntax: String, cursorOffset: Int = 0) {
        let currentRange = selectedRange ?? NSRange(location: memo.content.count, length: 0)
        let insertPosition = currentRange.location
        
        // 改行が必要な書式のみ前に改行を追加（見出しは除外）
        let needsNewlineBefore = syntax.hasPrefix("- ") || 
                                syntax.hasPrefix("* ") || syntax.hasPrefix("> ") || 
                                syntax.hasPrefix("```") || syntax.hasPrefix("---") ||
                                syntax.hasPrefix("1. ") || syntax.contains("- [ ] ") || syntax.contains("- [x] ")
        
        var insertText = syntax
        if needsNewlineBefore && insertPosition > 0 {
            let beforeChar = String(memo.content[memo.content.index(memo.content.startIndex, offsetBy: insertPosition - 1)])
            if beforeChar != "\n" {
                insertText = "\n" + insertText
            }
        }
        
        // カーソル位置に挿入
        let nsString = memo.content as NSString
        memo.content = nsString.replacingCharacters(in: NSRange(location: insertPosition, length: 0), with: insertText)
        
        // カーソル位置を更新
        let newCursorPosition = insertPosition + insertText.count - cursorOffset
        selectedRange = NSRange(location: max(0, newCursorPosition), length: 0)
        
        print("✏️ マークダウン記法挿入 - 保存処理はスキップ")
    }
    
    private func insertMarkdownTable() {
        let tableTemplate = """
| ヘッダー1 | ヘッダー2 | ヘッダー3 |
|-----------|-----------|-----------|
| セル1     | セル2     | セル3     |
| セル4     | セル5     | セル6     |
"""
        
        let currentRange = selectedRange ?? NSRange(location: memo.content.count, length: 0)
        let insertPosition = currentRange.location
        
        var insertText = tableTemplate
        if insertPosition > 0 {
            let beforeChar = String(memo.content[memo.content.index(memo.content.startIndex, offsetBy: insertPosition - 1)])
            if beforeChar != "\n" {
                insertText = "\n" + insertText
            }
        }
        insertText += "\n"
        
        // カーソル位置に挿入
        let nsString = memo.content as NSString
        memo.content = nsString.replacingCharacters(in: NSRange(location: insertPosition, length: 0), with: insertText)
        
        // カーソル位置を更新
        selectedRange = NSRange(location: insertPosition + insertText.count, length: 0)
        
        print("📊 マークダウンテーブル挿入 - 保存処理はスキップ")
    }
    
    /// 画像選択ダイアログを表示
    private func showImagePicker() {
        showingImageSourceSelection = true
    }
    
    /// 写真アプリから画像を選択
    private func selectFromPhotos() {
        showingImagePicker = true
    }
    
    /// ファイルアプリから画像を選択
    private func selectFromFiles() {
        print("📁 ファイル選択を開始")
        showingFileImporter = true
    }
    
    /// 選択された写真を処理
    private func handleSelectedPhoto() {
        guard let selectedPhotoItem = selectedPhotoItem else { return }
        
        Task {
            do {
                if let data = try await selectedPhotoItem.loadTransferable(type: Data.self) {
                    await handleImageData(data, filename: "photo_\(Int(Date().timeIntervalSince1970)).jpg")
                }
            } catch {
                print("❌ 写真の読み込みに失敗: \(error)")
            }
        }
    }
    
    /// ファイルインポートの結果を処理
    private func handleFileImportResult(_ result: Result<[URL], Error>) {
        print("📁 ファイルインポート結果を処理中")
        switch result {
        case .success(let urls):
            print("✅ ファイル選択成功: \(urls.count)個のファイル")
            guard let url = urls.first else { 
                print("❌ 選択されたファイルがありません")
                return 
            }
            
            print("📁 選択されたファイル: \(url.lastPathComponent)")
            print("📁 ファイルパス: \(url.path)")
            
            Task {
                do {
                    // セキュリティスコープ付きリソースへのアクセスを開始
                    guard url.startAccessingSecurityScopedResource() else {
                        print("❌ セキュリティスコープ付きリソースへのアクセスに失敗")
                        return
                    }
                    
                    defer {
                        // アクセス終了
                        url.stopAccessingSecurityScopedResource()
                    }
                    
                    let data = try Data(contentsOf: url)
                    let filename = url.lastPathComponent
                    print("📁 ファイルデータ読み込み成功: \(data.count) bytes")
                    await handleImageData(data, filename: filename)
                } catch {
                    print("❌ ファイルの読み込みに失敗: \(error)")
                }
            }
            
        case .failure(let error):
            print("❌ ファイル選択に失敗: \(error)")
        }
    }
    
    /// 画像データを処理してマークダウンに挿入
    @MainActor
    private func handleImageData(_ data: Data, filename: String) async {
        print("🖼️ 画像データ処理開始: \(filename), サイズ: \(data.count) bytes")
        do {
            // ローカルストレージに保存
            let localURL = try await saveImageToLocalStorage(data, filename: filename)
            print("💾 画像保存成功: \(localURL.path)")
            
            // マークダウン形式で挿入
            let imageMarkdown = "![image](\(localURL.lastPathComponent))"
            insertMarkdownSyntax(imageMarkdown, cursorOffset: 0)
            
            print("✅ 画像をマークダウンに挿入: \(imageMarkdown)")
            
        } catch {
            print("❌ 画像の処理に失敗: \(error)")
        }
    }
    
    /// 画像をローカルストレージに保存
    private func saveImageToLocalStorage(_ data: Data, filename: String) async throws -> URL {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let imagesDirectory = documentsDirectory.appendingPathComponent("images")
        
        // ディレクトリを作成
        try FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true, attributes: nil)
        
        // 元のファイル名を使用し、重複時は連番を付与
        let uniqueFilename = generateUniqueFilename(in: imagesDirectory, originalFilename: filename)
        let fileURL = imagesDirectory.appendingPathComponent(uniqueFilename)
        
        // ファイルに保存
        try data.write(to: fileURL)
        
        return fileURL
    }
    
    /// 重複しないファイル名を生成
    private func generateUniqueFilename(in directory: URL, originalFilename: String) -> String {
        let fileManager = FileManager.default
        
        // ファイル名と拡張子を分離
        let fileURL = URL(fileURLWithPath: originalFilename)
        let nameWithoutExtension = fileURL.deletingPathExtension().lastPathComponent
        let fileExtension = fileURL.pathExtension
        
        var counter = 0
        var testFilename = originalFilename
        
        // ファイルが存在する限り連番を増やす
        while fileManager.fileExists(atPath: directory.appendingPathComponent(testFilename).path) {
            counter += 1
            if fileExtension.isEmpty {
                testFilename = "\(nameWithoutExtension)_\(counter)"
            } else {
                testFilename = "\(nameWithoutExtension)_\(counter).\(fileExtension)"
            }
        }
        
        return testFilename
    }
    
    private func exportToFile() {
        showingFileExporter = true
    }
    
    /// UIActivityViewControllerを直接表示
    private func showShareOptions() {
        // txtファイル用のアクティビティアイテムソースを作成
        let textFileSource = TextFileActivityItemSource(memo: memo)
        
        // カスタムアクティビティを作成
        let markdownExportActivity = MarkdownExportActivity(memo: memo)
        let pdfExportActivity = PDFExportActivity(memo: memo)
        let printActivity = PrintActivity(memo: memo)
        
        // アクティビティアイテムを準備
        let activityItems: [Any] = [textFileSource]
        let applicationActivities = [markdownExportActivity, pdfExportActivity, printActivity]
        
        let activityViewController = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: applicationActivities
        )
        
        // 不要なアクティビティを除外
        activityViewController.excludedActivityTypes = [.saveToCameraRoll, .addToReadingList]
        
        // iPadでの表示設定
        if let popover = activityViewController.popoverPresentationController {
            // 共有ボタンの位置を基準にする
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first {
                popover.sourceView = window
                popover.sourceRect = CGRect(x: window.bounds.midX, y: window.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
        }
        
        // 現在のビューコントローラーから表示
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootViewController = window.rootViewController {
            var presentingController = rootViewController
            while let presented = presentingController.presentedViewController {
                presentingController = presented
            }
            presentingController.present(activityViewController, animated: true)
        }
    }
    
    // MARK: - PDF and Sharing Functions
    
    /// PDFとして共有
    private func shareAsPDF() {
        MarkdownRenderer.generatePDF(from: memo, enableChapterNumbering: appSettings.isChapterNumberingEnabled) { [self] data in
            DispatchQueue.main.async {
                if let pdfData = data {
                    self.pdfData = pdfData
                    self.showingShareSheet = true
                } else {
                    print("PDFの生成に失敗しました")
                }
            }
        }
    }
    
    /// PDFファイルとしてエクスポート
    private func exportToPDF() {
        MarkdownRenderer.generatePDF(from: memo, enableChapterNumbering: appSettings.isChapterNumberingEnabled) { [self] data in
            DispatchQueue.main.async {
                if let pdfData = data {
                    self.pdfData = pdfData
                    self.showingPDFExporter = true
                } else {
                    print("PDFの生成に失敗しました")
                }
            }
        }
    }
    
    
    
    private var searchBarView: some View {
        VStack(spacing: 8) {
            HStack {
                VStack(spacing: 4) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        
                        TextField("検索", text: $searchText)
                            .textFieldStyle(PlainTextFieldStyle())
                            .onChange(of: searchText) {
                                performSearch()
                            }
                        
                        if !searchText.isEmpty {
                            Button(action: {
                                searchText = ""
                                searchResults = []
                                currentSearchIndex = 0
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                    
                    if isReplaceMode {
                        HStack {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .foregroundColor(.secondary)
                            
                            TextField("置換", text: $replaceText)
                                .textFieldStyle(PlainTextFieldStyle())
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                    }
                }
                
                VStack(spacing: 4) {
                    Button(action: { isReplaceMode.toggle() }) {
                        Image(systemName: isReplaceMode ? "arrow.up.arrow.down" : "arrow.triangle.2.circlepath")
                            .foregroundColor(.blue)
                    }
                    
                    HStack(spacing: 4) {
                        Button(action: previousSearchResult) {
                            Image(systemName: "chevron.up")
                                .font(.caption)
                        }
                        .disabled(searchResults.isEmpty)
                        
                        if !searchResults.isEmpty {
                            Text("\(currentSearchIndex + 1)/\(searchResults.count)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        } else {
                            Text("0/0")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        
                        Button(action: nextSearchResult) {
                            Image(systemName: "chevron.down")
                                .font(.caption)
                        }
                        .disabled(searchResults.isEmpty)
                    }
                }
                
                Button("完了") {
                    toggleSearch()
                }
                .foregroundColor(.blue)
            }
            
            if isReplaceMode {
                HStack(spacing: 12) {
                    Button("置換") {
                        replaceCurrentMatch()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(6)
                    .disabled(replaceText.isEmpty || searchResults.isEmpty)
                    
                    Button("全て置換") {
                        replaceAllMatches()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(6)
                    .disabled(replaceText.isEmpty || searchResults.isEmpty)
                    
                    Spacer()
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }
    
    private func toggleSearch() {
        withAnimation(.easeInOut(duration: 0.3)) {
            isSearching.toggle()
            if !isSearching {
                searchText = ""
                replaceText = ""
                searchResults = []
                currentSearchIndex = 0
                isReplaceMode = false
            }
        }
    }
    
    private func performSearch() {
        guard !searchText.isEmpty else {
            searchResults = []
            currentSearchIndex = 0
            return
        }
        
        let content = memo.content as NSString
        var ranges: [NSRange] = []
        var searchRange = NSRange(location: 0, length: content.length)
        
        while searchRange.location < content.length {
            let range = content.range(of: searchText, options: [.caseInsensitive], range: searchRange)
            if range.location == NSNotFound {
                break
            }
            ranges.append(range)
            searchRange = NSRange(location: range.location + range.length, length: content.length - (range.location + range.length))
        }
        
        searchResults = ranges
        currentSearchIndex = 0
    }
    
    private func nextSearchResult() {
        guard !searchResults.isEmpty else { return }
        currentSearchIndex = (currentSearchIndex + 1) % searchResults.count
    }
    
    private func previousSearchResult() {
        guard !searchResults.isEmpty else { return }
        currentSearchIndex = currentSearchIndex > 0 ? currentSearchIndex - 1 : searchResults.count - 1
    }
    
    private func replaceCurrentMatch() {
        guard !searchResults.isEmpty,
              currentSearchIndex < searchResults.count,
              !replaceText.isEmpty else { return }
        
        let range = searchResults[currentSearchIndex]
        let nsString = memo.content as NSString
        memo.content = nsString.replacingCharacters(in: range, with: replaceText)
        
        // 置換後に検索結果を更新
        let lengthDifference = replaceText.count - searchText.count
        
        // 現在のマッチを削除
        searchResults.remove(at: currentSearchIndex)
        
        // 後続の検索結果の位置を調整
        for i in currentSearchIndex..<searchResults.count {
            let adjustedLocation = searchResults[i].location + lengthDifference
            searchResults[i] = NSRange(location: adjustedLocation, length: searchResults[i].length)
        }
        
        // インデックスを調整
        if currentSearchIndex >= searchResults.count && !searchResults.isEmpty {
            currentSearchIndex = searchResults.count - 1
        }
        
        print("🔍 単一置換処理完了 - 保存処理はスキップ")
    }
    
    private func replaceAllMatches() {
        guard !searchResults.isEmpty, !replaceText.isEmpty else { return }
        
        let sortedRanges = searchResults.sorted { $0.location > $1.location }
        var content = memo.content
        
        for range in sortedRanges {
            let nsString = content as NSString
            content = nsString.replacingCharacters(in: range, with: replaceText)
        }
        
        memo.content = content
        searchResults = []
        currentSearchIndex = 0
        
        // 新しい検索を実行（置換後の結果を反映）
        performSearch()
        print("🔍 全置換処理完了 - 保存処理はスキップ")
    }
    
    // MARK: - Cancel and Save Handling
    /// キャンセルボタン押下時の処理
    private func handleCancel() {
        // キャンセルフラグを設定
        isExplicitlyDiscarded = true
        
        if hasChanges {
            print("⏪ 変更が検出されました - 元の状態に復元して終了")
            // 元の状態に復元
            memo = originalMemo
            // memoStoreにも元の状態を復元
            if !isNewMemo {
                memoStore.updateMemo(originalMemo)
            }
            // 編集状態の更新通知
            onMemoUpdated(originalMemo)
        } else {
            print("✅ 変更なし - そのまま終了")
        }
        onDismiss()
    }
}

struct MarkdownElement: Identifiable {
    let id = UUID()
    let view: AnyView
}

struct MarkdownText: View {
    let text: String
    let onToggleChecklist: ((Int) -> Void)?
    let onLinkTap: ((String) -> Void)?
    let enableChapterNumbering: Bool
    
    init(_ text: String, onToggleChecklist: ((Int) -> Void)? = nil, onLinkTap: ((String) -> Void)? = nil, enableChapterNumbering: Bool = true) {
        self.text = text
        self.onToggleChecklist = onToggleChecklist
        self.onLinkTap = onLinkTap
        self.enableChapterNumbering = enableChapterNumbering
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(parseMarkdown()) { element in
                element.view
            }
        }
    }
    
    /// PDF生成用のマークダウン解析（NSAttributedStringの配列を返す）
    func parseMarkdownForPDF(enableChapterNumbering: Bool = true) -> [NSAttributedString] {
        var elements: [NSAttributedString] = []
        let lines = text.components(separatedBy: .newlines)
        var inCodeBlock = false
        var codeBlockContent: [String] = []
        var inTable = false
        var tableRows: [String] = []
        
        // リスト状態管理
        var orderedListCounters: [Int: Int] = [:] // インデントレベル別の番号カウンター
        var lastWasListItem = false
        
        for (index, line) in lines.enumerated() {
            let isLastLine = index == lines.count - 1
            
            if line.hasPrefix("```") {
                if inCodeBlock {
                    // コードブロック終了 - CSSスタイルに合わせた装飾付きで追加
                    let codeText = codeBlockContent.joined(separator: "\n")
                    if !codeText.isEmpty {
                        let styledCodeBlock = createStyledCodeBlock(content: codeText)
                        elements.append(styledCodeBlock)
                    }
                    codeBlockContent = []
                    inCodeBlock = false
                } else {
                    inCodeBlock = true
                }
            } else if inCodeBlock {
                codeBlockContent.append(line)
            } else if line.hasPrefix("|") && line.hasSuffix("|") {
                // テーブル行の処理
                if !inTable {
                    inTable = true
                    tableRows = []
                }
                
                tableRows.append(line)
                
                // 次の行がテーブルでない、または最後の行の場合はテーブル終了
                let nextIndex = index + 1
                let nextLineIsTable = !isLastLine && lines[nextIndex].hasPrefix("|") && lines[nextIndex].hasSuffix("|")
                
                if isLastLine || !nextLineIsTable {
                    // テーブルを生成してPDF用AttributedStringに変換
                    let tableAttributedString = parseTableForPDF(tableRows)
                    elements.append(tableAttributedString)
                    inTable = false
                    tableRows = []
                }
            } else {
                // リスト処理チェック
                let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                let _ = getIndentLevel(line)
                let isUnorderedListItem = trimmedLine.hasPrefix("- ") || trimmedLine.hasPrefix("* ")
                let isOrderedListItem = trimmedLine.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil
                let isChecklistItem = trimmedLine.hasPrefix("- [x] ") || trimmedLine.hasPrefix("- [X] ") || trimmedLine.hasPrefix("- [ ] ")
                let isListItem = isUnorderedListItem || isOrderedListItem || isChecklistItem
                
                if isListItem {
                    // リスト項目の処理
                    let indentLevel = getIndentLevel(line)
                    
                    if isOrderedListItem {
                        // 番号付きリストの処理
                        let components = line.components(separatedBy: ". ")
                        if components.count >= 2 {
                            let inputNumber = components[0].trimmingCharacters(in: .whitespaces)
                            let content = components.dropFirst().joined(separator: ". ")
                            
                            // レベル別番号付きリストの自動インクリメント処理
                            let displayNumber: Int
                            if lastWasListItem {
                                // 連続するリスト項目
                                let currentNumber = orderedListCounters[indentLevel] ?? 1
                                displayNumber = currentNumber
                                orderedListCounters[indentLevel] = currentNumber + 1
                            } else {
                                // 新しいリストの開始
                                if let parsedNumber = Int(inputNumber) {
                                    displayNumber = parsedNumber
                                    orderedListCounters[indentLevel] = parsedNumber + 1
                                } else {
                                    displayNumber = 1
                                    orderedListCounters[indentLevel] = 2
                                }
                                
                                // 下位レベルのカウンターをリセット
                                for level in (indentLevel + 1)...10 {
                                    orderedListCounters.removeValue(forKey: level)
                                }
                            }
                            
                            // 階層番号フォーマットを適用
                            let formattedNumber: String
                            switch indentLevel {
                            case 0:
                                formattedNumber = "\(displayNumber)"
                            case 1:
                                // ①②③形式
                                let circledNumbers = ["①", "②", "③", "④", "⑤", "⑥", "⑦", "⑧", "⑨", "⑩",
                                                     "⑪", "⑫", "⑬", "⑭", "⑮", "⑯", "⑰", "⑱", "⑲", "⑳",
                                                     "㉑", "㉒", "㉓", "㉔", "㉕", "㉖", "㉗", "㉘", "㉙", "㉚",
                                                     "㉛", "㉜", "㉝", "㉞", "㉟", "㊱", "㊲", "㊳", "㊴", "㊵",
                                                     "㊶", "㊷", "㊸", "㊹", "㊺", "㊻", "㊼", "㊽", "㊾", "㊿"]
                                if displayNumber >= 1 && displayNumber <= circledNumbers.count {
                                    formattedNumber = circledNumbers[displayNumber - 1]
                                } else {
                                    formattedNumber = "\(displayNumber)"
                                }
                            case 2:
                                // ローマ数字
                                if displayNumber < 1 || displayNumber > 50 {
                                    formattedNumber = "\(displayNumber)"
                                } else {
                                    let values = [40, 10, 9, 5, 4, 1]
                                    let symbols = ["xl", "x", "ix", "v", "iv", "i"]
                                    var result = ""
                                    var num = displayNumber
                                    for (i, value) in values.enumerated() {
                                        let count = num / value
                                        if count > 0 {
                                            result += String(repeating: symbols[i], count: count)
                                            num %= value
                                        }
                                    }
                                    formattedNumber = result
                                }
                            case 3:
                                // 小文字アルファベット
                                if displayNumber < 1 || displayNumber > 26 {
                                    formattedNumber = "\(displayNumber)"
                                } else {
                                    let alphabets = ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z"]
                                    formattedNumber = alphabets[displayNumber - 1]
                                }
                            default:
                                formattedNumber = "\(displayNumber)"
                            }
                            
                            // PDF用のAttributedStringを作成（番号のみを渡す、ピリオドはcreateStyledListItem内で処理）
                            let attributedString = createStyledListItem(content: content, isOrdered: true, line: line, number: formattedNumber)
                            elements.append(attributedString)
                            
                            lastWasListItem = true
                        }
                    } else if isChecklistItem {
                        // チェックリスト項目の処理
                        let attributedString = createChecklistItem(from: trimmedLine, line: line)
                        elements.append(attributedString)
                        lastWasListItem = true
                    } else {
                        // 順序なしリスト
                        let content = extractListContent(from: line, isOrdered: false)
                        let attributedString = createStyledListItem(content: content, isOrdered: false, line: line)
                        elements.append(attributedString)
                        lastWasListItem = true
                    }
                } else {
                    // リスト以外の通常処理
                    if lastWasListItem {
                        // リストが終了したのでカウンターをリセット
                        orderedListCounters.removeAll()
                        lastWasListItem = false
                    }
                    
                    let attributedString = parseLineForPDF(line, lines: lines, lineIndex: index, enableChapterNumbering: enableChapterNumbering)
                    if attributedString.length > 0 {
                        elements.append(attributedString)
                    }
                }
            }
        }
        
        return elements
    }
    
    /// リストコンテンツを抽出
    private func extractListContent(from line: String, isOrdered: Bool) -> String {
        if isOrdered {
            // 番号付きリスト: "1. content" -> "content"
            if let regex = try? NSRegularExpression(pattern: #"^\d+\.\s(.+)$"#) {
                let range = NSRange(line.startIndex..., in: line)
                if let match = regex.firstMatch(in: line, range: range) {
                    let contentRange = Range(match.range(at: 1), in: line)!
                    return String(line[contentRange])
                }
            }
        } else {
            // 順序なしリスト: "- content" or "* content" -> "content"
            if line.hasPrefix("- ") {
                return String(line.dropFirst(2))
            } else if line.hasPrefix("* ") {
                return String(line.dropFirst(2))
            }
        }
        return line
    }
    
    /// チェックリストアイテムを作成
    private func createChecklistItem(from trimmedLine: String, line: String) -> NSAttributedString {
        let indentLevel = getIndentLevel(line)
        let baseIndent: CGFloat = 20
        let totalIndent = CGFloat(indentLevel) * baseIndent
        
        let font = UIFont.systemFont(ofSize: 12)
        var checkbox = ""
        var content = ""
        
        if trimmedLine.hasPrefix("- [x] ") || trimmedLine.hasPrefix("- [X] ") {
            checkbox = "☑︎ "
            content = String(trimmedLine.dropFirst(6))
        } else if trimmedLine.hasPrefix("- [ ] ") {
            checkbox = "◻︎ "
            content = String(trimmedLine.dropFirst(6))
        }
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.firstLineHeadIndent = totalIndent
        paragraphStyle.headIndent = totalIndent + 12
        paragraphStyle.lineSpacing = 0
        paragraphStyle.paragraphSpacing = 1
        paragraphStyle.paragraphSpacingBefore = 0
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.black,
            .paragraphStyle: paragraphStyle
        ]
        
        let result = NSMutableAttributedString(string: checkbox + content, attributes: attributes)
        processInlineFormatting(result)
        processLinks(result)
        
        let finalResult = NSMutableAttributedString()
        finalResult.append(NSAttributedString(string: "\n"))
        finalResult.append(result)
        
        return finalResult
    }
    
    /// 単一行をPDF用のNSAttributedStringに変換
    private func parseLineForPDF(_ line: String, lines: [String], lineIndex: Int, enableChapterNumbering: Bool = true) -> NSAttributedString {
        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmedLine.isEmpty {
            return NSAttributedString(string: "\n")
        }
        
        var attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12),
            .foregroundColor: UIColor.black
        ]
        
        var text = trimmedLine
        
        // 見出し処理（CSSスタイルに合わせた装飾を含む）
        let counters = MarkdownText.calculateHeadingCountersForPDF(lines: lines, upToIndex: lineIndex)
        
        if text.hasPrefix("# ") {
            let content = String(text.dropFirst(2))
            return createStyledHeading(content: content, level: 1, counters: counters, enableChapterNumbering: enableChapterNumbering)
        } else if text.hasPrefix("## ") {
            let content = String(text.dropFirst(3))
            return createStyledHeading(content: content, level: 2, counters: counters, enableChapterNumbering: enableChapterNumbering)
        } else if text.hasPrefix("### ") {
            let content = String(text.dropFirst(4))
            return createStyledHeading(content: content, level: 3, counters: counters, enableChapterNumbering: enableChapterNumbering)
        } else if text.hasPrefix("#### ") {
            let content = String(text.dropFirst(5))
            return createStyledHeading(content: content, level: 4, counters: counters, enableChapterNumbering: enableChapterNumbering)
        } else if text.hasPrefix("##### ") {
            let content = String(text.dropFirst(6))
            return createStyledHeading(content: content, level: 5, counters: counters, enableChapterNumbering: enableChapterNumbering)
        } else if text.hasPrefix("###### ") {
            let content = String(text.dropFirst(7))
            return createStyledHeading(content: content, level: 6, counters: counters, enableChapterNumbering: enableChapterNumbering)
        }
        // 引用ブロック処理
        else if text.hasPrefix("> ") {
            let content = String(text.dropFirst(2))
            return createStyledBlockquote(content: content)
        }
        // 水平線処理
        else if text == "---" || text == "***" || text == "___" {
            return createStyledHorizontalRule()
        }
        // 画像処理
        else if text.contains("![") && text.contains("](") {
            return createImageAttachment(from: text)
        }
        // 引用処理
        else if text.hasPrefix("> ") {
            attributes[.foregroundColor] = UIColor.systemGray2
            attributes[.font] = UIFont.italicSystemFont(ofSize: 12)
            text = "│ " + String(text.dropFirst(2))
        }
        
        // インライン装飾を処理
        let result = NSMutableAttributedString(string: text, attributes: attributes)
        processInlineFormatting(result)
        processLinks(result)
        
        return result
    }
    
    /// インライン装飾（太字、斜体、取り消し線、コード）を処理
    private func processInlineFormatting(_ attributedString: NSMutableAttributedString) {
        // リンク処理を最初に行う（他の処理と干渉しないように）
        processLinks(attributedString)
        
        // 取り消し線処理 ~~text~~
        processStrikethroughText(attributedString)
        
        // 太字処理 **text**
        processBoldText(attributedString)
        
        // 斜体処理 *text*
        processItalicText(attributedString)
        
        // インラインコード処理 `code`
        processInlineCode(attributedString)
    }
    
    private func processStrikethroughText(_ attributedString: NSMutableAttributedString) {
        let pattern = #"~~([^~]+)~~"#
        do {
            let regex = try NSRegularExpression(pattern: pattern)
            let matches = regex.matches(in: attributedString.string, options: [], range: NSRange(location: 0, length: attributedString.length))
            
            // 逆順で処理してインデックスのずれを防ぐ
            for match in matches.reversed() {
                let contentRange = match.range(at: 1)
                if contentRange.location != NSNotFound {
                    // ~~を削除してから取り消し線を適用
                    attributedString.replaceCharacters(in: NSRange(location: match.range.location + match.range.length - 2, length: 2), with: "")
                    attributedString.replaceCharacters(in: NSRange(location: match.range.location, length: 2), with: "")
                    
                    // 新しい範囲で取り消し線を適用
                    let newRange = NSRange(location: match.range.location, length: contentRange.length)
                    attributedString.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: newRange)
                    attributedString.addAttribute(.strikethroughColor, value: UIColor.systemGray2, range: newRange)
                    attributedString.addAttribute(.foregroundColor, value: UIColor.systemGray2, range: newRange)
                }
            }
        } catch {
            print("取り消し線処理エラー: \(error)")
        }
    }
    
    private func processBoldText(_ attributedString: NSMutableAttributedString) {
        let pattern = #"\*\*([^\*]+)\*\*"#
        do {
            let regex = try NSRegularExpression(pattern: pattern)
            let matches = regex.matches(in: attributedString.string, range: NSRange(location: 0, length: attributedString.length))
            
            for match in matches.reversed() {
                let contentRange = match.range(at: 1)
                if contentRange.location != NSNotFound {
                    // 現在のフォントサイズを取得
                    let currentFont = attributedString.attribute(.font, at: contentRange.location, effectiveRange: nil) as? UIFont ?? UIFont.systemFont(ofSize: 12)
                    let boldFont = UIFont.boldSystemFont(ofSize: currentFont.pointSize)
                    
                    // **を削除してから太字を適用
                    attributedString.replaceCharacters(in: NSRange(location: match.range.location + match.range.length - 2, length: 2), with: "")
                    attributedString.replaceCharacters(in: NSRange(location: match.range.location, length: 2), with: "")
                    
                    // 新しい範囲で太字を適用
                    let newRange = NSRange(location: match.range.location, length: contentRange.length)
                    attributedString.addAttribute(.font, value: boldFont, range: newRange)
                }
            }
        } catch {
            print("太字処理エラー: \(error)")
        }
    }
    
    private func processItalicText(_ attributedString: NSMutableAttributedString) {
        // アスタリスク形式の斜体処理 *text*
        let asteriskPattern = #"\*([^\*]+)\*"#
        do {
            let regex = try NSRegularExpression(pattern: asteriskPattern)
            let matches = regex.matches(in: attributedString.string, range: NSRange(location: 0, length: attributedString.length))
            
            for match in matches.reversed() {
                let contentRange = match.range(at: 1)
                if contentRange.location != NSNotFound {
                    // 現在のフォントサイズを取得
                    let currentFont = attributedString.attribute(.font, at: contentRange.location, effectiveRange: nil) as? UIFont ?? UIFont.systemFont(ofSize: 12)
                    let italicFont = UIFont.italicSystemFont(ofSize: currentFont.pointSize)
                    
                    // *を削除してから斜体を適用
                    attributedString.replaceCharacters(in: NSRange(location: match.range.location + match.range.length - 1, length: 1), with: "")
                    attributedString.replaceCharacters(in: NSRange(location: match.range.location, length: 1), with: "")
                    
                    // 新しい範囲で斜体を適用
                    let newRange = NSRange(location: match.range.location, length: contentRange.length)
                    attributedString.addAttribute(.font, value: italicFont, range: newRange)
                }
            }
        } catch {
            print("斜体処理エラー（アスタリスク）: \(error)")
        }
        
        // アンダースコア形式の斜体処理 _text_
        let underscorePattern = #"_([^_]+)_"#
        do {
            let regex = try NSRegularExpression(pattern: underscorePattern)
            let matches = regex.matches(in: attributedString.string, range: NSRange(location: 0, length: attributedString.length))
            
            for match in matches.reversed() {
                let contentRange = match.range(at: 1)
                if contentRange.location != NSNotFound {
                    // 現在のフォントサイズを取得
                    let currentFont = attributedString.attribute(.font, at: contentRange.location, effectiveRange: nil) as? UIFont ?? UIFont.systemFont(ofSize: 12)
                    let italicFont = UIFont.italicSystemFont(ofSize: currentFont.pointSize)
                    
                    // _を削除してから斜体を適用
                    attributedString.replaceCharacters(in: NSRange(location: match.range.location + match.range.length - 1, length: 1), with: "")
                    attributedString.replaceCharacters(in: NSRange(location: match.range.location, length: 1), with: "")
                    
                    // 新しい範囲で斜体を適用
                    let newRange = NSRange(location: match.range.location, length: contentRange.length)
                    attributedString.addAttribute(.font, value: italicFont, range: newRange)
                }
            }
        } catch {
            print("斜体処理エラー（アンダースコア）: \(error)")
        }
    }
    
    private func processInlineCode(_ attributedString: NSMutableAttributedString) {
        let pattern = #"`([^`]+)`"#
        do {
            let regex = try NSRegularExpression(pattern: pattern)
            let matches = regex.matches(in: attributedString.string, range: NSRange(location: 0, length: attributedString.length))
            
            for match in matches.reversed() {
                let contentRange = match.range(at: 1)
                if contentRange.location != NSNotFound {
                    // `を削除してからスタイルを適用
                    attributedString.replaceCharacters(in: NSRange(location: match.range.location + match.range.length - 1, length: 1), with: "")
                    attributedString.replaceCharacters(in: NSRange(location: match.range.location, length: 1), with: "")
                    
                    // 新しい範囲でコードスタイルを適用（コードブロックと同じ背景色）
                    let newRange = NSRange(location: match.range.location, length: contentRange.length)
                    attributedString.addAttribute(.font, value: UIFont.monospacedSystemFont(ofSize: 12, weight: .regular), range: newRange)
                    attributedString.addAttribute(.backgroundColor, value: UIColor(red: 0.90, green: 0.90, blue: 0.90, alpha: 1.0), range: newRange)
                }
            }
        } catch {
            print("インラインコード処理エラー: \(error)")
        }
    }
    
    /// リンク処理（外部リンクと内部リンクの両方に対応）
    private func processLinks(_ attributedString: NSMutableAttributedString) {
        let pattern = #"\[([^\]]+)\]\(([^)]+)\)"#
        do {
            let regex = try NSRegularExpression(pattern: pattern)
            let matches = regex.matches(in: attributedString.string, range: NSRange(location: 0, length: attributedString.length))
            
            for match in matches.reversed() {
                let linkTextRange = match.range(at: 1)
                let linkURLRange = match.range(at: 2)
                
                if linkTextRange.location != NSNotFound && linkURLRange.location != NSNotFound {
                    let linkText = (attributedString.string as NSString).substring(with: linkTextRange)
                    let linkURL = (attributedString.string as NSString).substring(with: linkURLRange)
                    
                    // リンクの種類を判定
                    let isExternalLink = linkURL.hasPrefix("http://") || linkURL.hasPrefix("https://")
                    let isInternalLink = linkURL.hasPrefix("#")
                    
                    // リンクのスタイル設定
                    let linkAttributes: [NSAttributedString.Key: Any] = [
                        .font: UIFont.systemFont(ofSize: 12),
                        .foregroundColor: isInternalLink ? UIColor.systemPurple : UIColor.systemBlue,
                        .underlineStyle: NSUnderlineStyle.single.rawValue
                    ]
                    
                    // 表示形式を決定
                    var displayText: String
                    if isExternalLink {
                        // 外部リンクは従来通りURL表示
                        displayText = "\(linkText) (\(linkURL))"
                    } else if isInternalLink {
                        // 内部リンクはテキストのみ表示し、リンク先は小さく表示
                        displayText = "\(linkText) → \(linkURL)"
                    } else {
                        // その他のリンクは従来通り
                        displayText = "\(linkText) (\(linkURL))"
                    }
                    
                    let linkAttributedString = NSAttributedString(string: displayText, attributes: linkAttributes)
                    attributedString.replaceCharacters(in: match.range, with: linkAttributedString)
                }
            }
        } catch {
            print("リンク処理エラー: \(error)")
        }
    }
    
    /// PDF用のテーブル処理（実際の罫線を使用したExcel風スタイル）
    private func parseTableForPDF(_ rows: [String]) -> NSAttributedString {
        guard !rows.isEmpty else {
            return NSAttributedString(string: "")
        }
        
        print("📊 テーブル解析開始 - 行数: \(rows.count)")
        for (index, row) in rows.enumerated() {
            print("📊 行 \(index): \(row)")
        }
        
        // 表データを解析
        var tableData: [[String]] = []
        
        for row in rows {
            let cells = row.components(separatedBy: "|")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            
            tableData.append(Array(cells))
        }
        
        // セパレーター行を削除（通常2行目）
        if tableData.count > 1 {
            let secondRow = tableData[1]
            // セパレーター行の判定（-と:のみで構成されている）
            let isSeparator = secondRow.allSatisfy { cell in
                cell.trimmingCharacters(in: .whitespaces).allSatisfy { char in
                    char == "-" || char == ":" || char.isWhitespace
                }
            }
            if isSeparator {
                tableData.remove(at: 1)
            }
        }
        
        print("📊 解析後のテーブルデータ:")
        for (rowIndex, rowData) in tableData.enumerated() {
            print("📊   行 \(rowIndex): \(rowData)")
        }
        
        // 最大列数を決定
        let maxColumns = tableData.map { $0.count }.max() ?? 0
        guard maxColumns > 0 else { return NSAttributedString(string: "\n") }
        
        // 各列の最大幅を計算（複数行を考慮）
        let columnWidths = calculateColumnWidths(tableData: tableData, maxColumns: maxColumns)
        
        // Core Graphicsを使用してテーブル画像を生成
        let tableImage = generateTableImage(tableData: tableData, columnWidths: columnWidths, maxColumns: maxColumns)
        
        // 画像をNSAttributedStringに変換
        let result = NSMutableAttributedString()
        result.append(NSAttributedString(string: "\n"))
        
        if let image = tableImage {
            let textAttachment = NSTextAttachment()
            textAttachment.image = image
            // 画像サイズを調整
            let imageSize = image.size
            let scaleFactor: CGFloat = min(500.0 / imageSize.width, 300.0 / imageSize.height)
            textAttachment.bounds = CGRect(x: 0, y: 0, width: imageSize.width * scaleFactor, height: imageSize.height * scaleFactor)
            result.append(NSAttributedString(attachment: textAttachment))
        }
        
        result.append(NSAttributedString(string: "\n\n"))
        
        print("📊 テーブル解析完了")
        return result
    }
    
    private func calculateColumnWidths(tableData: [[String]], maxColumns: Int) -> [Int] {
        var columnWidths = Array(repeating: 10, count: maxColumns) // 最小幅10
        
        for rowData in tableData {
            for (colIndex, cell) in rowData.enumerated() {
                if colIndex < maxColumns {
                    // 改行を考慮して最大行の長さを計算
                    let lines = cell.components(separatedBy: .newlines)
                    let maxLineLength = lines.map { $0.count }.max() ?? 0
                    columnWidths[colIndex] = max(columnWidths[colIndex], min(maxLineLength + 2, 30)) // 最大幅30
                }
            }
        }
        
        return columnWidths
    }
    
    /// Core Graphicsを使用してExcel風の表画像を生成
    private func generateTableImage(tableData: [[String]], columnWidths: [Int], maxColumns: Int) -> UIImage? {
        // セルのサイズとマージンを設定
        let cellPadding: CGFloat = 3
        let baseRowHeight: CGFloat = 14
        let fontSize: CGFloat = 7
        let headerFontSize: CGFloat = 7
        // let lineHeight: CGFloat = 16  // 使用されていないため削除
        
        // 各行の高さを計算（NSAttributedStringの自動折り返しを考慮）
        var rowHeights: [CGFloat] = []
        for (rowIndex, rowData) in tableData.enumerated() {
            var maxHeight: CGFloat = baseRowHeight
            
            for (colIndex, cellContent) in rowData.enumerated() {
                if colIndex < maxColumns && !cellContent.isEmpty {
                    let columnWidth = CGFloat(columnWidths[colIndex]) * 7 + cellPadding * 2 - cellPadding * 2
                    let font = rowIndex == 0 ? 
                        UIFont.boldSystemFont(ofSize: headerFontSize) : 
                        UIFont.systemFont(ofSize: fontSize)
                    
                    let paragraphStyle = NSMutableParagraphStyle()
                    paragraphStyle.alignment = .left
                    paragraphStyle.lineBreakMode = .byWordWrapping
                    
                    let textAttributes: [NSAttributedString.Key: Any] = [
                        .font: font,
                        .paragraphStyle: paragraphStyle
                    ]
                    
                    let attributedString = NSAttributedString(string: cellContent, attributes: textAttributes)
                    let boundingRect = attributedString.boundingRect(
                        with: CGSize(width: columnWidth, height: CGFloat.greatestFiniteMagnitude),
                        options: [.usesLineFragmentOrigin, .usesFontLeading],
                        context: nil
                    )
                    
                    let cellHeight = ceil(boundingRect.height) + cellPadding
                    maxHeight = max(maxHeight, cellHeight)
                }
            }
            
            rowHeights.append(maxHeight)
        }
        
        // 各列の実際の幅を計算（ピクセル単位）
        let actualColumnWidths = columnWidths.map { CGFloat($0) * 7 + cellPadding * 2 }
        let totalWidth = actualColumnWidths.reduce(0, +) + 1 // 境界線の分
        let totalHeight = rowHeights.reduce(0, +) + 1
        
        // 画像コンテキストを作成
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: totalWidth, height: totalHeight))
        
        return renderer.image { context in
            let cgContext = context.cgContext
            
            // 背景色を白に設定
            cgContext.setFillColor(UIColor.white.cgColor)
            cgContext.fill(CGRect(x: 0, y: 0, width: totalWidth, height: totalHeight))
            
            // 罫線の色を設定（薄いグレー）
            let borderColor = UIColor(red: 0.87, green: 0.87, blue: 0.87, alpha: 1.0) // #ddd
            cgContext.setStrokeColor(borderColor.cgColor)
            cgContext.setLineWidth(0.5)
            
            // 縦線を描画
            var currentX: CGFloat = 0
            for columnWidth in actualColumnWidths {
                cgContext.move(to: CGPoint(x: currentX, y: 0))
                cgContext.addLine(to: CGPoint(x: currentX, y: totalHeight))
                cgContext.strokePath()
                currentX += columnWidth
            }
            // 最後の縦線
            cgContext.move(to: CGPoint(x: totalWidth, y: 0))
            cgContext.addLine(to: CGPoint(x: totalWidth, y: totalHeight))
            cgContext.strokePath()
            
            // 横線を描画
            var currentY: CGFloat = 0
            for i in 0...tableData.count {
                cgContext.move(to: CGPoint(x: 0, y: currentY))
                cgContext.addLine(to: CGPoint(x: totalWidth, y: currentY))
                cgContext.strokePath()
                if i < rowHeights.count {
                    currentY += rowHeights[i]
                }
            }
            
            // セルの背景色を描画
            currentY = 0
            for (rowIndex, _) in tableData.enumerated() {
                let isHeader = rowIndex == 0
                let rowHeight = rowHeights[rowIndex]
                
                var currentX: CGFloat = 0
                for colIndex in 0..<maxColumns {
                    let cellRect = CGRect(x: currentX + 1, 
                                        y: currentY + 1, 
                                        width: actualColumnWidths[colIndex] - 1, 
                                        height: rowHeight - 1)
                    
                    if isHeader {
                        // ヘッダーの背景色（薄いグレー）
                        cgContext.setFillColor(UIColor(red: 0.96, green: 0.96, blue: 0.96, alpha: 1.0).cgColor)
                    } else {
                        // データ行の背景色（交互）
                        let backgroundColor = rowIndex % 2 == 0 ? 
                            UIColor.white : 
                            UIColor(red: 0.98, green: 0.98, blue: 0.98, alpha: 1.0)
                        cgContext.setFillColor(backgroundColor.cgColor)
                    }
                    
                    cgContext.fill(cellRect)
                    currentX += actualColumnWidths[colIndex]
                }
                currentY += rowHeight
            }
            
            // テキストを描画
            currentY = 0
            for (rowIndex, rowData) in tableData.enumerated() {
                let isHeader = rowIndex == 0
                let rowHeight = rowHeights[rowIndex]
                
                // フォントとテキスト属性を設定
                let font = isHeader ? 
                    UIFont.boldSystemFont(ofSize: headerFontSize) : 
                    UIFont.systemFont(ofSize: fontSize)
                
                let textColor = isHeader ? UIColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1.0) : UIColor.black
                let textAlignment: NSTextAlignment = .left  // すべて左揃えに統一
                
                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.alignment = textAlignment
                paragraphStyle.lineBreakMode = .byWordWrapping  // 単語境界で折り返し
                
                let textAttributes: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: textColor,
                    .paragraphStyle: paragraphStyle
                ]
                
                var currentX: CGFloat = 0
                for colIndex in 0..<maxColumns {
                    let cellContent = colIndex < rowData.count ? rowData[colIndex] : ""
                    let cellRect = CGRect(x: currentX + cellPadding, 
                                        y: currentY + cellPadding / 2, 
                                        width: actualColumnWidths[colIndex] - cellPadding * 2, 
                                        height: rowHeight - cellPadding)
                    
                    // NSAttributedStringの自動折り返しを使用（上揃え・左揃え）
                    let attributedString = NSAttributedString(string: cellContent, attributes: textAttributes)
                    
                    // セル内でのテキスト描画（上揃え・左揃えで自動折り返し）
                    let drawingRect = CGRect(x: cellRect.minX, 
                                           y: cellRect.minY,  // 上揃えのため上端から開始
                                           width: cellRect.width, 
                                           height: cellRect.height)
                    
                    attributedString.draw(with: drawingRect, 
                                        options: [.usesLineFragmentOrigin, .usesFontLeading], 
                                        context: nil)
                    
                    currentX += actualColumnWidths[colIndex]
                }
                currentY += rowHeight
            }
        }
    }
    
    /// CSSスタイルに基づいた見出しを生成（下線・左線・カウンター付き）
    private func createStyledHeading(content: String, level: Int, counters: (h2: Int, h3: Int, h4: Int, h5: Int, h6: Int), enableChapterNumbering: Bool = true) -> NSAttributedString {
        // フォントサイズとスタイル設定
        let baseFontSize: CGFloat = 16
        let fontSizes: [CGFloat] = [
            2.2 * baseFontSize,  // H1: 35.2pt
            1.8 * baseFontSize,  // H2: 28.8pt
            1.5 * baseFontSize,  // H3: 24pt
            1.25 * baseFontSize, // H4: 20pt
            1.1 * baseFontSize,  // H5: 17.6pt
            1.1 * baseFontSize   // H6: 17.6pt
        ]
        
        let fontSize = fontSizes[level - 1]
        let font = UIFont.boldSystemFont(ofSize: fontSize)
        
        // テキスト内容にカウンターを追加（設定により制御）
        var displayText = ""
        if enableChapterNumbering {
            switch level {
            case 1:
                displayText = content  // H1はカウンターなし、中央揃え
            case 2:
                displayText = "\(counters.h2). \(content)"
            case 3:
                displayText = "\(counters.h2). \(counters.h3). \(content)"
            case 4:
                displayText = "\(counters.h2). \(counters.h3). \(counters.h4). \(content)"
            case 5:
                displayText = "\(counters.h2). \(counters.h3). \(counters.h4). \(counters.h5). \(content)"
            case 6:
                displayText = "\(counters.h2). \(counters.h3). \(counters.h4). \(counters.h5). \(counters.h6). \(content)"
            default:
                displayText = content
            }
        } else {
            // 章番号を表示しない場合
            displayText = content
        }
        
        // Core Graphicsを使用して装飾付き見出し画像を生成
        let headingImage = generateStyledHeadingImage(text: displayText, level: level, font: font)
        
        // 画像をNSAttributedStringに変換
        let result = NSMutableAttributedString()
        
        if let image = headingImage {
            let textAttachment = NSTextAttachment()
            textAttachment.image = image
            // 画像サイズを調整
            let imageSize = image.size
            let scaleFactor: CGFloat = min(500.0 / imageSize.width, 1.0)
            textAttachment.bounds = CGRect(x: 0, y: 0, width: imageSize.width * scaleFactor, height: imageSize.height * scaleFactor)
            result.append(NSAttributedString(attachment: textAttachment))
        }
        
        return result
    }
    
    /// CSSスタイルに基づいた見出し画像を生成
    private func generateStyledHeadingImage(text: String, level: Int, font: UIFont) -> UIImage? {
        // パディングとマージン設定
        let padding: CGFloat = 10
        let leftBorderWidth: CGFloat = level >= 3 ? (level == 3 ? 8 : (level == 4 ? 4 : 3)) : 0
        
        // テキストサイズを計算
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.black
        ]
        
        let imageWidth: CGFloat = 535  // PDFの印刷可能領域の幅に固定
        let availableTextWidth = imageWidth - leftBorderWidth - (padding * 2)
        
        // 折り返しを考慮したテキストサイズを計算
        let textBoundingRect = text.boundingRect(
            with: CGSize(width: availableTextWidth, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: textAttributes,
            context: nil
        )
        
        let textSize = textBoundingRect.size
        let imageHeight = textSize.height + padding * 2
        
        // 画像コンテキストを作成
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: imageWidth, height: imageHeight))
        
        return renderer.image { context in
            let cgContext = context.cgContext
            
            // 背景色を白に設定
            cgContext.setFillColor(UIColor.white.cgColor)
            cgContext.fill(CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))
            
            // 左側の境界線を描画（H3, H4, H5, H6）
            if leftBorderWidth > 0 {
                cgContext.setFillColor(UIColor.black.cgColor)
                cgContext.fill(CGRect(x: 0, y: 0, width: leftBorderWidth, height: imageHeight))
            }
            
            // 下線を描画
            let bottomLineHeight: CGFloat
            switch level {
            case 1:
                bottomLineHeight = 2  // H1: 2px solid
            case 2:
                bottomLineHeight = 4  // H2: 4px solid
            case 3:
                bottomLineHeight = 2  // H3: 2px solid
            default:
                bottomLineHeight = 0  // H4, H5, H6: 下線なし
            }
            
            if bottomLineHeight > 0 {
                cgContext.setFillColor(UIColor.black.cgColor)
                // 下線は左端から右端まで全幅に描画
                cgContext.fill(CGRect(x: 0, 
                                     y: imageHeight - bottomLineHeight, 
                                     width: imageWidth, 
                                     height: bottomLineHeight))
            }
            
            // テキストを描画
            let textRect = CGRect(x: leftBorderWidth + padding, 
                                y: padding, 
                                width: availableTextWidth, 
                                height: textSize.height)
            
            // H1は中央揃え、その他は左揃え
            var finalTextRect = textRect
            if level == 1 {
                finalTextRect.origin.x = leftBorderWidth + padding
                finalTextRect.size.width = availableTextWidth
            }
            
            // 中央揃えや左揃えを考慮したAttributedStringを作成
            let paragraphStyle = NSMutableParagraphStyle()
            if level == 1 {
                paragraphStyle.alignment = .center
            } else {
                paragraphStyle.alignment = .left
            }
            paragraphStyle.lineBreakMode = .byWordWrapping
            
            var finalTextAttributes = textAttributes
            finalTextAttributes[.paragraphStyle] = paragraphStyle
            
            let attributedString = NSAttributedString(string: text, attributes: finalTextAttributes)
            attributedString.draw(in: finalTextRect)
        }
    }
    
    /// CSSスタイルに基づいたコードブロックを生成
    private func createStyledCodeBlock(content: String) -> NSAttributedString {
        let codeImage = generateStyledCodeBlockImage(content: content)
        
        let result = NSMutableAttributedString()
        result.append(NSAttributedString(string: "\n"))
        
        if let image = codeImage {
            let textAttachment = NSTextAttachment()
            textAttachment.image = image
            // 画像サイズを調整
            let imageSize = image.size
            let scaleFactor: CGFloat = min(500.0 / imageSize.width, 1.0)
            textAttachment.bounds = CGRect(x: 0, y: 0, width: imageSize.width * scaleFactor, height: imageSize.height * scaleFactor)
            result.append(NSAttributedString(attachment: textAttachment))
        }
        
        result.append(NSAttributedString(string: "\n"))
        return result
    }
    
    /// CSSスタイルに基づいた引用ブロックを生成
    private func createStyledBlockquote(content: String) -> NSAttributedString {
        let blockquoteImage = generateStyledBlockquoteImage(content: content)
        
        let result = NSMutableAttributedString()
        result.append(NSAttributedString(string: "\n"))
        
        if let image = blockquoteImage {
            let textAttachment = NSTextAttachment()
            textAttachment.image = image
            // 画像サイズを調整
            let imageSize = image.size
            let scaleFactor: CGFloat = min(500.0 / imageSize.width, 1.0)
            textAttachment.bounds = CGRect(x: 0, y: 0, width: imageSize.width * scaleFactor, height: imageSize.height * scaleFactor)
            result.append(NSAttributedString(attachment: textAttachment))
        }
        
        result.append(NSAttributedString(string: "\n"))
        return result
    }
    
    /// CSSスタイルに基づいたコードブロック画像を生成
    private func generateStyledCodeBlockImage(content: String) -> UIImage? {
        // CSS: background-color: #f2f2f2; padding: 1em; border-radius: 4px;
        let padding: CGFloat = 16  // 1em
        let font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let backgroundColor = UIColor(red: 0.95, green: 0.95, blue: 0.95, alpha: 1.0) // #f2f2f2
        
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.black
        ]
        
        let textSize = content.size(withAttributes: textAttributes)
        let imageWidth = max(textSize.width + padding * 2, 300)
        let imageHeight = textSize.height + padding * 2
        
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: imageWidth, height: imageHeight))
        
        return renderer.image { context in
            let cgContext = context.cgContext
            
            // 背景色を設定（丸角）
            let rect = CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight)
            let path = UIBezierPath(roundedRect: rect, cornerRadius: 4)
            cgContext.addPath(path.cgPath)
            cgContext.setFillColor(backgroundColor.cgColor)
            cgContext.fillPath()
            
            // テキストを描画
            let textRect = CGRect(x: padding, y: padding, width: textSize.width, height: textSize.height)
            let attributedString = NSAttributedString(string: content, attributes: textAttributes)
            attributedString.draw(in: textRect)
        }
    }
    
    /// CSSスタイルに基づいた引用ブロック画像を生成
    private func generateStyledBlockquoteImage(content: String) -> UIImage? {
        // CSS: background-color: #f8f8f8; border-left: 4px solid #ccc; padding: 0.5em 1em; color: #555;
        let padding: CGFloat = 8   // 0.5em vertical
        let horizontalPadding: CGFloat = 16  // 1em horizontal
        let leftBorderWidth: CGFloat = 4
        let font = UIFont.systemFont(ofSize: 12)
        let backgroundColor = UIColor(red: 0.97, green: 0.97, blue: 0.97, alpha: 1.0) // #f8f8f8
        let borderColor = UIColor(red: 0.8, green: 0.8, blue: 0.8, alpha: 1.0) // #ccc
        let textColor = UIColor(red: 0.33, green: 0.33, blue: 0.33, alpha: 1.0) // #555
        
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]
        
        let textSize = content.size(withAttributes: textAttributes)
        let imageWidth = max(textSize.width + horizontalPadding * 2 + leftBorderWidth, 300)
        let imageHeight = textSize.height + padding * 2
        
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: imageWidth, height: imageHeight))
        
        return renderer.image { context in
            let cgContext = context.cgContext
            
            // 背景色を設定
            cgContext.setFillColor(backgroundColor.cgColor)
            cgContext.fill(CGRect(x: leftBorderWidth, y: 0, width: imageWidth - leftBorderWidth, height: imageHeight))
            
            // 左側の境界線を描画
            cgContext.setFillColor(borderColor.cgColor)
            cgContext.fill(CGRect(x: 0, y: 0, width: leftBorderWidth, height: imageHeight))
            
            // テキストを描画
            let textRect = CGRect(x: leftBorderWidth + horizontalPadding, 
                                y: padding, 
                                width: textSize.width, 
                                height: textSize.height)
            let attributedString = NSAttributedString(string: content, attributes: textAttributes)
            attributedString.draw(in: textRect)
        }
    }
    
    /// スタイル付きリスト項目を生成
    private func createStyledListItem(content: String, isOrdered: Bool, line: String, number: String? = nil) -> NSAttributedString {
        let indentLevel = getIndentLevel(line)
        let baseIndent: CGFloat = 20  // 1レベルあたりのインデント幅
        let totalIndent = CGFloat(indentLevel) * baseIndent
        
        let font = UIFont.systemFont(ofSize: 12)
        
        // 丸囲み数字の場合はピリオドを付けない
        let bullet: String
        if isOrdered {
            let numberStr = number ?? "1"
            // 丸囲み数字の判定（①②③...）
            let isCircledNumber = numberStr.contains("①") || numberStr.contains("②") || numberStr.contains("③") ||
                                numberStr.contains("④") || numberStr.contains("⑤") || numberStr.contains("⑥") ||
                                numberStr.contains("⑦") || numberStr.contains("⑧") || numberStr.contains("⑨") ||
                                numberStr.contains("⑩") || numberStr.contains("⑪") || numberStr.contains("⑫") ||
                                numberStr.contains("⑬") || numberStr.contains("⑭") || numberStr.contains("⑮") ||
                                numberStr.contains("⑯") || numberStr.contains("⑰") || numberStr.contains("⑱") ||
                                numberStr.contains("⑲") || numberStr.contains("⑳") || numberStr.contains("㉑") ||
                                numberStr.contains("㉒") || numberStr.contains("㉓") || numberStr.contains("㉔") ||
                                numberStr.contains("㉕") || numberStr.contains("㉖") || numberStr.contains("㉗") ||
                                numberStr.contains("㉘") || numberStr.contains("㉙") || numberStr.contains("㉚") ||
                                numberStr.contains("㉛") || numberStr.contains("㉜") || numberStr.contains("㉝") ||
                                numberStr.contains("㉞") || numberStr.contains("㉟") || numberStr.contains("㊱") ||
                                numberStr.contains("㊲") || numberStr.contains("㊳") || numberStr.contains("㊴") ||
                                numberStr.contains("㊵") || numberStr.contains("㊶") || numberStr.contains("㊷") ||
                                numberStr.contains("㊸") || numberStr.contains("㊹") || numberStr.contains("㊺") ||
                                numberStr.contains("㊻") || numberStr.contains("㊼") || numberStr.contains("㊽") ||
                                numberStr.contains("㊾") || numberStr.contains("㊿")
            
            if isCircledNumber {
                bullet = "\(numberStr) "  // 丸囲み数字にはピリオドを付けない
            } else {
                bullet = "\(numberStr). "  // その他の数字にはピリオドを付ける
            }
        } else {
            bullet = "• "
        }
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.firstLineHeadIndent = totalIndent
        paragraphStyle.headIndent = totalIndent + 12  // ぶら下がりインデント
        paragraphStyle.lineSpacing = -6
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.black,
            .paragraphStyle: paragraphStyle
        ]
        
        let result = NSMutableAttributedString(string: bullet + content, attributes: attributes)
        processInlineFormatting(result)
        processLinks(result)
        
        let finalResult = NSMutableAttributedString()
        finalResult.append(NSAttributedString(string: "\n"))
        finalResult.append(result)
        
        return finalResult
    }
    
    /// スタイル付き水平線を生成
    private func createStyledHorizontalRule() -> NSAttributedString {
        let hrImage = generateHorizontalRuleImage()
        
        let result = NSMutableAttributedString()
        result.append(NSAttributedString(string: "\n"))
        
        if let image = hrImage {
            let textAttachment = NSTextAttachment()
            textAttachment.image = image
            // 画像サイズを調整
            let imageSize = image.size
            let scaleFactor: CGFloat = min(500.0 / imageSize.width, 1.0)
            textAttachment.bounds = CGRect(x: 0, y: 0, width: imageSize.width * scaleFactor, height: imageSize.height * scaleFactor)
            result.append(NSAttributedString(attachment: textAttachment))
        }
        
        result.append(NSAttributedString(string: "\n"))
        return result
    }
    
    /// 水平線画像を生成
    private func generateHorizontalRuleImage() -> UIImage? {
        let width: CGFloat = 400
        let height: CGFloat = 3
        let lineColor = UIColor(red: 0.8, green: 0.8, blue: 0.8, alpha: 1.0) // #ccc
        
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        
        return renderer.image { context in
            let cgContext = context.cgContext
            
            // 水平線を描画
            cgContext.setFillColor(lineColor.cgColor)
            cgContext.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }
    
    /// 画像のNSTextAttachmentを作成
    private func createImageAttachment(from line: String) -> NSAttributedString {
        let imagePattern = #"!\[([^\]]*)\]\(([^)]+)\)"#
        do {
            let regex = try NSRegularExpression(pattern: imagePattern)
            let matches = regex.matches(in: line, range: NSRange(line.startIndex..., in: line))
            
            if let match = matches.first {
                let altTextRange = Range(match.range(at: 1), in: line)!
                let urlRange = Range(match.range(at: 2), in: line)!
                let altText = String(line[altTextRange])
                let imageURL = String(line[urlRange])
                
                // 画像を読み込み（ローカルまたはURL）
                var image: UIImage?
                
                if imageURL.hasPrefix("http://") || imageURL.hasPrefix("https://") {
                    // URL画像の場合（非同期処理に変更）
                    if let url = URL(string: imageURL) {
                        // 非同期でURL画像を取得
                        let semaphore = DispatchSemaphore(value: 0)
                        var imageData: Data?
                        
                        URLSession.shared.dataTask(with: url) { data, _, error in
                            if let error = error {
                                print("⚠️ URL画像読み込みエラー: \(error.localizedDescription)")
                            }
                            imageData = data
                            semaphore.signal()
                        }.resume()
                        
                        semaphore.wait()
                        
                        if let data = imageData {
                            image = UIImage(data: data)
                            print("✅ URL画像読み込み成功: \(imageURL)")
                        } else {
                            print("❌ URL画像読み込み失敗: \(imageURL)")
                        }
                    }
                } else {
                    // ローカル画像の場合
                    if let imageData = loadLocalImageData(filename: imageURL) {
                        image = UIImage(data: imageData)
                        print("✅ ローカル画像読み込み成功: \(imageURL)")
                    } else {
                        print("❌ ローカル画像読み込み失敗: \(imageURL)")
                    }
                }
                
                if let image = image {
                    
                    let textAttachment = NSTextAttachment()
                    textAttachment.image = image
                    
                    // PDFに適したサイズに調整
                    let maxWidth: CGFloat = 500  // PDF用の最大幅
                    let maxHeight: CGFloat = 400  // PDF用の最大高さ
                    
                    let originalSize = image.size
                    let aspectRatio = originalSize.width / originalSize.height
                    
                    var finalSize: CGSize
                    if aspectRatio > 1 {
                        // 横長画像
                        let width = min(maxWidth, originalSize.width)
                        finalSize = CGSize(width: width, height: width / aspectRatio)
                    } else {
                        // 縦長または正方形画像
                        let height = min(maxHeight, originalSize.height)
                        finalSize = CGSize(width: height * aspectRatio, height: height)
                    }
                    
                    textAttachment.bounds = CGRect(origin: .zero, size: finalSize)
                    
                    let result = NSMutableAttributedString()
                    result.append(NSAttributedString(string: "\n"))
                    
                    // 画像を中央揃えで追加
                    let imageParagraphStyle = NSMutableParagraphStyle()
                    imageParagraphStyle.alignment = .center
                    let imageAttributedString = NSMutableAttributedString(attachment: textAttachment)
                    imageAttributedString.addAttribute(.paragraphStyle, value: imageParagraphStyle, range: NSRange(location: 0, length: 1))
                    result.append(imageAttributedString)
                    
                    // altTextがある場合はキャプションとして中央揃えで追加
                    if !altText.isEmpty {
                        result.append(NSAttributedString(string: "\n"))
                        let captionAttributes: [NSAttributedString.Key: Any] = [
                            .font: UIFont.systemFont(ofSize: 10),
                            .foregroundColor: UIColor.gray,
                            .paragraphStyle: {
                                let style = NSMutableParagraphStyle()
                                style.alignment = .center
                                return style
                            }()
                        ]
                        result.append(NSAttributedString(string: altText, attributes: captionAttributes))
                    }
                    
                    result.append(NSAttributedString(string: "\n"))
                    return result
                } else {
                    // 画像が見つからない場合のプレースホルダー
                    let placeholderAttributes: [NSAttributedString.Key: Any] = [
                        .font: UIFont.systemFont(ofSize: 12),
                        .foregroundColor: UIColor.gray,
                        .backgroundColor: UIColor.lightGray.withAlphaComponent(0.3)
                    ]
                    let placeholderText = "画像が見つかりません: \(altText.isEmpty ? imageURL : altText)"
                    
                    let result = NSMutableAttributedString()
                    result.append(NSAttributedString(string: "\n"))
                    result.append(NSAttributedString(string: placeholderText, attributes: placeholderAttributes))
                    result.append(NSAttributedString(string: "\n"))
                    return result
                }
            }
        } catch {
            print("❌ 画像パターンの解析に失敗: \(error)")
        }
        
        // パターンマッチしない場合は通常のテキストとして処理
        return NSAttributedString(string: line + "\n")
    }
    
    /// ローカル画像データを読み込み
    private func loadLocalImageData(filename: String) -> Data? {
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        
        // 新しいパス形式（images）を優先して確認
        let newImagesDirectory = documentsDirectory.appendingPathComponent("images")
        let newImageFileURL = newImagesDirectory.appendingPathComponent(filename)
        
        if FileManager.default.fileExists(atPath: newImageFileURL.path) {
            do {
                return try Data(contentsOf: newImageFileURL)
            } catch {
                print("❌ 新形式画像ファイルの読み込みに失敗: \(error)")
            }
        }
        
        // 旧形式（MemoImages）も確認（後方互換性のため）
        let oldImagesDirectory = documentsDirectory.appendingPathComponent("MemoImages")
        let oldImageFileURL = oldImagesDirectory.appendingPathComponent(filename)
        
        do {
            return try Data(contentsOf: oldImageFileURL)
        } catch {
            print("❌ 旧形式画像ファイルの読み込みに失敗: \(error)")
            return nil
        }
    }
    
    /// 行の先頭のインデントレベルを計算
    /// タブ文字または2個以上の半角スペースでインデントレベルを判定
    /// - Parameter line: 解析対象の行
    /// - Returns: インデントレベル（0から開始）
    private func getIndentLevel(_ line: String) -> Int {
        let prefix = line.prefix { $0 == " " || $0 == "\t" }
        var indentLevel = 0
        var i = prefix.startIndex
        
        while i < prefix.endIndex {
            let char = prefix[i]
            if char == "\t" {
                // タブ文字は1レベル
                indentLevel += 1
                i = prefix.index(after: i)
            } else if char == " " {
                // 連続するスペースをカウント
                var consecutiveSpaces = 0
                var j = i
                while j < prefix.endIndex && prefix[j] == " " {
                    consecutiveSpaces += 1
                    j = prefix.index(after: j)
                }
                
                // 2個以上のスペースを1つのインデントレベルとして扱う
                if consecutiveSpaces >= 2 {
                    // スペース数に応じてレベルを計算
                    // 2個→1レベル、4個→2レベル、6個→3レベル...
                    indentLevel += consecutiveSpaces / 2
                }
                
                // 処理した分だけインデックスを進める
                i = j
            } else {
                // スペースでもタブでもない文字が出現したら終了
                break
            }
        }
        
        return indentLevel
    }
    
    private func parseMarkdown() -> [MarkdownElement] {
        let lines = text.components(separatedBy: .newlines)
        var elements: [MarkdownElement] = []
        var inCodeBlock = false
        var codeBlockContent: [String] = []
        var inTable = false
        var tableRows: [String] = []
        var numberedListCounters: [Int: Int] = [:] // レベル別の番号カウンター
        var lastLineWasNumberedList = false
        var lastNumberedListLevel = 0
        
        for (index, line) in lines.enumerated() {
            // 番号付きリスト以外の場合はリセット（後で番号付きリストの場合は上書き）
            let isCurrentLineNumberedList = line.contains(". ") && isNumberedListItem(line)
            if !isCurrentLineNumberedList {
                lastLineWasNumberedList = false
            }
            
            if line.hasPrefix("```") {
                if inCodeBlock {
                    // マーメイド図の検出
                    if let firstLine = codeBlockContent.first,
                       firstLine.lowercased().trimmingCharacters(in: .whitespaces).hasSuffix("mermaid") {
                        // 最初の行（```mermaid）を除いたコードを取得
                        let mermaidCode = codeBlockContent.dropFirst().joined(separator: "\n")
                        elements.append(MarkdownElement(view: AnyView(
                            MermaidView(code: mermaidCode)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        )))
                    } else {
                        // 通常のコードブロック表示
                        let codeText = codeBlockContent.dropFirst().joined(separator: "\n")
                        elements.append(MarkdownElement(view: AnyView(
                            Text(codeText)
                                .font(.system(.body, design: .monospaced))
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(.systemGray4))
                                .cornerRadius(8)
                                .padding(.vertical, 4)
                        )))
                    }
                    codeBlockContent = []
                    inCodeBlock = false
                } else {
                    inCodeBlock = true
                    // コードブロック開始行の言語指定を保存
                    codeBlockContent.append(line)
                }
            } else if inCodeBlock {
                codeBlockContent.append(line)
            } else if line.hasPrefix("# ") {
                let content = String(line.dropFirst(2))
                let headingId = createHeadingId(from: content)
                elements.append(MarkdownElement(view: AnyView(
                    VStack(spacing: 4) {
                        formatInlineMarkdownAsView(content)
                            .font(.system(size: 35.2, weight: .semibold)) // 2.2em * 16px
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity)
                        Rectangle()
                            .fill(Color.primary)
                            .frame(height: 2)
                            .frame(maxWidth: .infinity)
                    }
                    .padding(.top, 32) // 2em
                    .padding(.bottom, 12.8) // 0.8em
                    .id(headingId)
                )))
            } else if line.hasPrefix("## ") {
                let content = String(line.dropFirst(3))
                let headingId = createHeadingId(from: content)
                let counters = calculateHeadingCounters(upToLine: index)
                let h2Counter = counters.h2
                elements.append(MarkdownElement(view: AnyView(
                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            if enableChapterNumbering {
                                Text("\(h2Counter). ")
                                    .font(.system(size: 28.8, weight: .semibold)) // 1.8em * 16px
                                    .foregroundColor(.primary)
                            }
                            formatInlineMarkdownAsView(content)
                                .font(.system(size: 28.8, weight: .semibold))
                                .foregroundColor(.primary)
                            Spacer()
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 5)
                        Rectangle()
                            .fill(Color.primary)
                            .frame(height: 4)
                    }
                    .padding(.top, 32) // 2em
                    .padding(.bottom, 12.8) // 0.8em
                    .id(headingId)
                )))
            } else if line.hasPrefix("### ") {
                let content = String(line.dropFirst(4))
                let headingId = createHeadingId(from: content)
                let counters = calculateHeadingCounters(upToLine: index)
                let (h2Counter, h3Counter) = (counters.h2, counters.h3)
                elements.append(MarkdownElement(view: AnyView(
                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            Rectangle()
                                .fill(Color.primary)
                                .frame(width: 8)
                            VStack(spacing: 0) {
                                HStack(spacing: 0) {
                                    if enableChapterNumbering {
                                        Text("\(h2Counter). \(h3Counter). ")
                                            .font(.system(size: 24, weight: .semibold)) // 1.5em * 16px
                                            .foregroundColor(.primary)
                                    }
                                    formatInlineMarkdownAsView(content)
                                        .font(.system(size: 24, weight: .semibold))
                                        .foregroundColor(.primary)
                                    Spacer()
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                Rectangle()
                                    .fill(Color.primary)
                                    .frame(height: 2)
                            }
                        }
                    }
                    .padding(.top, 32) // 2em
                    .padding(.bottom, 12.8) // 0.8em
                    .id(headingId)
                )))
            } else if line.hasPrefix("#### ") {
                let content = String(line.dropFirst(5))
                let headingId = createHeadingId(from: content)
                let counters = calculateHeadingCounters(upToLine: index)
                let (h2Counter, h3Counter, h4Counter) = (counters.h2, counters.h3, counters.h4)
                elements.append(MarkdownElement(view: AnyView(
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(Color.primary)
                            .frame(width: 4)
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(spacing: 0) {
                                if enableChapterNumbering {
                                    Text("\(h2Counter). \(h3Counter). \(h4Counter). ")
                                        .font(.system(size: 20, weight: .semibold)) // 1.25em * 16px
                                        .foregroundColor(.primary)
                                }
                                formatInlineMarkdownAsView(content)
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundColor(.primary)
                                Spacer()
                            }
                            .padding(.horizontal, 15)
                            .padding(.vertical, 5)
                        }
                    }
                    .padding(.top, 32) // 2em
                    .padding(.bottom, 12.8) // 0.8em
                    .id(headingId)
                )))
            } else if line.hasPrefix("##### ") {
                let content = String(line.dropFirst(6))
                let headingId = createHeadingId(from: content)
                let counters = calculateHeadingCounters(upToLine: index)
                let (h2Counter, h3Counter, h4Counter, h5Counter) = (counters.h2, counters.h3, counters.h4, counters.h5)
                elements.append(MarkdownElement(view: AnyView(
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(Color.primary)
                            .frame(width: 3)
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(spacing: 0) {
                                Text("\(h2Counter). \(h3Counter). \(h4Counter). \(h5Counter). ")
                                    .font(.system(size: 17.6, weight: .semibold)) // 1.1em * 16px
                                    .foregroundColor(.primary)
                                formatInlineMarkdownAsView(content)
                                    .font(.system(size: 17.6, weight: .semibold))
                                    .foregroundColor(.primary)
                                Spacer()
                            }
                            .padding(.horizontal, 15)
                            .padding(.vertical, 5)
                        }
                    }
                    .padding(.top, 32) // 2em
                    .padding(.bottom, 12.8) // 0.8em
                    .id(headingId)
                )))
            } else if line.hasPrefix("###### ") {
                let content = String(line.dropFirst(7))
                let headingId = createHeadingId(from: content)
                let counters = calculateHeadingCounters(upToLine: index)
                let (h2Counter, h3Counter, h4Counter, h5Counter, h6Counter) = (counters.h2, counters.h3, counters.h4, counters.h5, counters.h6)
                elements.append(MarkdownElement(view: AnyView(
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(Color.primary)
                            .frame(width: 3)
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(spacing: 0) {
                                Text("\(h2Counter). \(h3Counter). \(h4Counter). \(h5Counter). \(h6Counter). ")
                                    .font(.system(size: 17.6, weight: .semibold)) // 1.1em * 16px
                                    .foregroundColor(.primary)
                                formatInlineMarkdownAsView(content)
                                    .font(.system(size: 17.6, weight: .semibold))
                                    .foregroundColor(.primary)
                                Spacer()
                            }
                            .padding(.horizontal, 15)
                            .padding(.vertical, 5)
                        }
                    }
                    .padding(.top, 32) // 2em
                    .padding(.bottom, 12.8) // 0.8em
                    .id(headingId)
                )))
            } else if let listInfo = parseListItem(line) {
                // 統一されたリスト処理
                let lineIndex = index
                elements.append(MarkdownElement(view: AnyView(
                    createListItemView(listInfo: listInfo, lineIndex: lineIndex)
                )))
            } else if line.contains(". ") && isNumberedListItem(line) {
                // 番号付きリスト（1. 2. 3. など）
                let components = line.components(separatedBy: ". ")
                if components.count >= 2 {
                    // インデントレベルを計算
                    let indentLevel = getIndentLevel(line)
                    let inputNumber = components[0].trimmingCharacters(in: .whitespaces)
                    let content = components.dropFirst().joined(separator: ". ")
                    
                    // レベル別番号付きリストの自動インクリメント処理
                    let displayNumber: Int
                    if lastLineWasNumberedList && indentLevel == lastNumberedListLevel {
                        // 同じレベルの連続する番号付きリスト
                        let currentNumber = numberedListCounters[indentLevel] ?? 1
                        displayNumber = currentNumber
                        numberedListCounters[indentLevel] = currentNumber + 1
                    } else {
                        // 新しいレベルまたは新しい番号付きリストの開始
                        if let parsedNumber = Int(inputNumber) {
                            displayNumber = parsedNumber
                            numberedListCounters[indentLevel] = parsedNumber + 1
                        } else {
                            displayNumber = 1
                            numberedListCounters[indentLevel] = 2
                        }
                        
                        // 下位レベルのカウンターをリセット
                        for level in (indentLevel + 1)...10 {
                            numberedListCounters.removeValue(forKey: level)
                        }
                    }
                    
                    lastNumberedListLevel = indentLevel
                    
                    // インデントレベルに応じて左マージンを調整（UI表示上は最大10レベルまで）
                    let displayLevel = min(indentLevel, 10)
                    let baseLeadingPadding: CGFloat = 16
                    let indentPadding: CGFloat = CGFloat(displayLevel) * 24 // レベルごとに24pt追加
                    
                    // インデントレベルに応じた階層番号フォーマットを使用
                    let formattedNumber: String
                    switch indentLevel {
                    case 0:
                        formattedNumber = "\(displayNumber)"
                    case 1:
                        // ①②③形式
                        let circledNumbers = ["①", "②", "③", "④", "⑤", "⑥", "⑦", "⑧", "⑨", "⑩",
                                             "⑪", "⑫", "⑬", "⑭", "⑮", "⑯", "⑰", "⑱", "⑲", "⑳",
                                             "㉑", "㉒", "㉓", "㉔", "㉕", "㉖", "㉗", "㉘", "㉙", "㉚",
                                             "㉛", "㉜", "㉝", "㉞", "㉟", "㊱", "㊲", "㊳", "㊴", "㊵",
                                             "㊶", "㊷", "㊸", "㊹", "㊺", "㊻", "㊼", "㊽", "㊾", "㊿"]
                        if displayNumber >= 1 && displayNumber <= circledNumbers.count {
                            formattedNumber = circledNumbers[displayNumber - 1]
                        } else {
                            formattedNumber = "\(displayNumber)"
                        }
                    case 2:
                        // ローマ数字
                        if displayNumber < 1 || displayNumber > 50 {
                            formattedNumber = "\(displayNumber)"
                        } else {
                            let values = [40, 10, 9, 5, 4, 1]
                            let symbols = ["xl", "x", "ix", "v", "iv", "i"]
                            var result = ""
                            var num = displayNumber
                            for (i, value) in values.enumerated() {
                                let count = num / value
                                if count > 0 {
                                    result += String(repeating: symbols[i], count: count)
                                    num %= value
                                }
                            }
                            formattedNumber = result
                        }
                    case 3:
                        // 小文字アルファベット
                        if displayNumber < 1 || displayNumber > 26 {
                            formattedNumber = "\(displayNumber)"
                        } else {
                            let alphabets = ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z"]
                            formattedNumber = alphabets[displayNumber - 1]
                        }
                    default:
                        formattedNumber = "\(displayNumber)"
                    }
                    
                    // ①②③形式の場合は.を付けない
                    let displayText = indentLevel == 1 ? formattedNumber : "\(formattedNumber)."
                    
                    elements.append(MarkdownElement(view: AnyView(
                        HStack(alignment: .top, spacing: 8) {
                            Text(displayText)
                                .font(.headline)
                                .foregroundColor(.primary)
                                .padding(.top, 1)
                                .frame(minWidth: 20, alignment: .leading)
                            formatInlineMarkdownAsView(content)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer()
                        }
                        .padding(.leading, baseLeadingPadding + indentPadding)
                        .padding(.vertical, 2)
                    )))
                    
                    lastLineWasNumberedList = true
                }
            } else if line.hasPrefix("> ") {
                let content = String(line.dropFirst(2))
                elements.append(MarkdownElement(view: AnyView(
                    HStack(spacing: 12) {
                        Rectangle()
                            .fill(Color.blue)
                            .frame(width: 4)
                        VStack {
                            formatInlineMarkdownAsView(content)
                                .italic()
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.vertical, 4)
                    .background(Color(.systemGray6).opacity(0.5))
                    .cornerRadius(6)
                )))
            } else if line.contains("---") && line.trimmingCharacters(in: .whitespaces) == "---" {
                elements.append(MarkdownElement(view: AnyView(
                    Rectangle()
                        .fill(Color.gray.opacity(0.5))
                        .frame(height: 1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                )))
            } else if line.contains("![") && line.contains("](") {
                // 画像処理
                let imagePattern = #"!\[([^\]]*)\]\(([^)]+)\)"#
                do {
                    let regex = try NSRegularExpression(pattern: imagePattern)
                    let matches = regex.matches(in: line, range: NSRange(line.startIndex..., in: line))
                    
                    if let match = matches.first {
                        let altTextRange = Range(match.range(at: 1), in: line)!
                        let urlRange = Range(match.range(at: 2), in: line)!
                        let altText = String(line[altTextRange])
                        let imageURL = String(line[urlRange])
                        
                        // 画像URLを判定して適切に処理
                        let imageUrl: URL?
                        if imageURL.hasPrefix("http://") || imageURL.hasPrefix("https://") {
                            // 外部URL画像
                            imageUrl = URL(string: imageURL)
                        } else {
                            // ローカル画像ファイルパスを構築
                            let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                            // 新しいパス（images）と旧パス（MemoImages）の両方を確認
                            let newImagesDirectory = documentsDirectory.appendingPathComponent("images")
                            let newImageFileURL = newImagesDirectory.appendingPathComponent(imageURL)
                            let oldImagesDirectory = documentsDirectory.appendingPathComponent("MemoImages")
                            let oldImageFileURL = oldImagesDirectory.appendingPathComponent(imageURL)
                            
                            // 新しいパスが存在するかチェック
                            if FileManager.default.fileExists(atPath: newImageFileURL.path) {
                                imageUrl = newImageFileURL
                            } else {
                                // 旧パスを使用（後方互換性）
                                imageUrl = oldImageFileURL
                            }
                        }
                        
                        elements.append(MarkdownElement(view: AnyView(
                            VStack(alignment: .leading, spacing: 8) {
                                Group {
                                    if let url = imageUrl {
                                        AsyncImage(url: url) { image in
                                            image
                                                .resizable()
                                                .aspectRatio(contentMode: .fit)
                                                .cornerRadius(8)
                                        } placeholder: {
                                            Rectangle()
                                                .fill(Color.gray.opacity(0.3))
                                                .frame(height: 200)
                                                .cornerRadius(8)
                                                .overlay(
                                                    VStack {
                                                        Image(systemName: "photo")
                                                            .font(.largeTitle)
                                                            .foregroundColor(.gray)
                                                        Text("画像を読み込み中...")
                                                            .font(.caption)
                                                            .foregroundColor(.gray)
                                                    }
                                                )
                                        }
                                    } else {
                                        Rectangle()
                                            .fill(Color.red.opacity(0.3))
                                            .frame(height: 100)
                                            .cornerRadius(8)
                                            .overlay(
                                                VStack {
                                                    Image(systemName: "exclamationmark.triangle")
                                                        .font(.largeTitle)
                                                        .foregroundColor(.red)
                                                    Text("画像を読み込めません")
                                                        .font(.caption)
                                                        .foregroundColor(.red)
                                                }
                                            )
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .frame(maxHeight: 400)
                                
                                if !altText.isEmpty {
                                    Text(altText)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .center)
                                }
                            }
                            .padding(.vertical, 8)
                        )))
                    }
                } catch {
                    print("❌ 画像パターンの解析に失敗: \(error)")
                }
            } else if line.hasPrefix("|") && line.hasSuffix("|") {
                // テーブル行の処理
                let isHeaderSeparator = line.replacingOccurrences(of: "|", with: "")
                    .replacingOccurrences(of: "-", with: "")
                    .replacingOccurrences(of: " ", with: "").isEmpty
                
                if !inTable {
                    inTable = true
                    tableRows = []
                }
                
                if !isHeaderSeparator {
                    tableRows.append(line)
                }
                
                // 次の行がテーブル行でない場合、テーブルを終了
                let nextIndex = index + 1
                let isLastLine = nextIndex >= lines.count
                let nextLineIsTable = !isLastLine && lines[nextIndex].hasPrefix("|") && lines[nextIndex].hasSuffix("|")
                
                if isLastLine || !nextLineIsTable {
                    // テーブル終了、まとめて処理
                    elements.append(MarkdownElement(view: parseTable(tableRows)))
                    inTable = false
                    tableRows = []
                }
            } else if !line.isEmpty {
                elements.append(MarkdownElement(view: AnyView(
                    formatInlineMarkdownAsView(line)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 1)
                )))
            } else {
                elements.append(MarkdownElement(view: AnyView(
                    Text(" ")
                        .font(.caption2)
                        .frame(height: 8)
                )))
            }
        }
        
        return elements
    }
    
    private func createHeadingId(from text: String) -> String {
        return text
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "[", with: "")
            .replacingOccurrences(of: "]", with: "")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .replacingOccurrences(of: "&", with: "")
            .replacingOccurrences(of: "?", with: "")
            .replacingOccurrences(of: "!", with: "")
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: ";", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "#", with: "")
            .replacingOccurrences(of: "@", with: "")
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: "%", with: "")
            .replacingOccurrences(of: "^", with: "")
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "+", with: "")
            .replacingOccurrences(of: "=", with: "")
            .replacingOccurrences(of: "|", with: "")
            .replacingOccurrences(of: "\\", with: "")
            .replacingOccurrences(of: "/", with: "")
            .replacingOccurrences(of: "<", with: "")
            .replacingOccurrences(of: ">", with: "")
            .replacingOccurrences(of: "{", with: "")
            .replacingOccurrences(of: "}", with: "")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "～", with: "")
            .replacingOccurrences(of: "、", with: "")
            .replacingOccurrences(of: "。", with: "")
            .replacingOccurrences(of: "（", with: "")
            .replacingOccurrences(of: "）", with: "")
            .replacingOccurrences(of: "【", with: "")
            .replacingOccurrences(of: "】", with: "")
            .replacingOccurrences(of: "「", with: "")
            .replacingOccurrences(of: "」", with: "")
            .replacingOccurrences(of: "『", with: "")
            .replacingOccurrences(of: "』", with: "")
    }
    
    // ヘッダーカウンター計算関数
    private func calculateHeadingCounters(upToLine currentIndex: Int) -> (h2: Int, h3: Int, h4: Int, h5: Int, h6: Int) {
        let lines = text.components(separatedBy: .newlines)
        var h2Counter = 0, h3Counter = 0, h4Counter = 0, h5Counter = 0, h6Counter = 0
        
        for i in 0...currentIndex {
            guard i < lines.count else { break }
            let line = lines[i]
            
            if line.hasPrefix("# ") {
                // H1でh2以下をリセット
                h2Counter = 0
                h3Counter = 0
                h4Counter = 0
                h5Counter = 0
                h6Counter = 0
            } else if line.hasPrefix("## ") {
                h2Counter += 1
                h3Counter = 0
                h4Counter = 0
                h5Counter = 0
                h6Counter = 0
            } else if line.hasPrefix("### ") {
                h3Counter += 1
                h4Counter = 0
                h5Counter = 0
                h6Counter = 0
            } else if line.hasPrefix("#### ") {
                h4Counter += 1
                h5Counter = 0
                h6Counter = 0
            } else if line.hasPrefix("##### ") {
                h5Counter += 1
                h6Counter = 0
            } else if line.hasPrefix("###### ") {
                h6Counter += 1
            }
        }
        
        return (h2Counter, h3Counter, h4Counter, h5Counter, h6Counter)
    }
    
    /// PDF生成用のヘッダーカウンター計算関数（静的メソッド）
    private static func calculateHeadingCountersForPDF(lines: [String], upToIndex currentIndex: Int) -> (h2: Int, h3: Int, h4: Int, h5: Int, h6: Int) {
        var h2Counter = 0, h3Counter = 0, h4Counter = 0, h5Counter = 0, h6Counter = 0
        
        for i in 0...currentIndex {
            guard i < lines.count else { break }
            let line = lines[i]
            
            if line.hasPrefix("# ") {
                // H1でh2以下をリセット
                h2Counter = 0
                h3Counter = 0
                h4Counter = 0
                h5Counter = 0
                h6Counter = 0
            } else if line.hasPrefix("## ") {
                h2Counter += 1
                h3Counter = 0
                h4Counter = 0
                h5Counter = 0
                h6Counter = 0
            } else if line.hasPrefix("### ") {
                h3Counter += 1
                h4Counter = 0
                h5Counter = 0
                h6Counter = 0
            } else if line.hasPrefix("#### ") {
                h4Counter += 1
                h5Counter = 0
                h6Counter = 0
            } else if line.hasPrefix("##### ") {
                h5Counter += 1
                h6Counter = 0
            } else if line.hasPrefix("###### ") {
                h6Counter += 1
            }
        }
        
        return (h2Counter, h3Counter, h4Counter, h5Counter, h6Counter)
    }
    
    private func formatInlineMarkdownAsText(_ text: String) -> Text {
        return formatInlineMarkdown(text).0
    }
    
    private func formatInlineMarkdownAsView(_ text: String) -> AnyView {
        let (textView, hasLinks) = formatInlineMarkdown(text)
        if hasLinks {
            return AnyView(formatInlineMarkdownWithLinks(text))
        } else {
            // インラインコードがある場合は専用のView処理を行う
            if text.contains("`") {
                return AnyView(formatInlineMarkdownWithCode(text))
            } else {
                return AnyView(textView)
            }
        }
    }
    
    private func formatInlineMarkdownWithCode(_ text: String) -> some View {
        let codePattern = #"`([^`]+)`"#
        guard let regex = try? NSRegularExpression(pattern: codePattern) else {
            return AnyView(formatInlineMarkdownAsText(text))
        }
        
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: text.count))
        
        if matches.isEmpty {
            return AnyView(formatInlineMarkdownAsText(text))
        }
        
        let segments = parseCodeSegments(text: text, matches: matches)
        
        return AnyView(
            HStack(spacing: 0) {
                ForEach(segments.indices, id: \.self) { index in
                    let segment = segments[index]
                    if segment.isCode {
                        Text(segment.codeContent)
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.primary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color(.systemGray4))
                            .cornerRadius(4)
                    } else {
                        formatInlineMarkdownAsText(segment.text)
                    }
                }
            }
        )
    }
    
    private struct CodeSegment {
        let text: String
        let codeContent: String
        let isCode: Bool
    }
    
    private func parseCodeSegments(text: String, matches: [NSTextCheckingResult]) -> [CodeSegment] {
        var segments: [CodeSegment] = []
        var lastEnd = 0
        
        for match in matches {
            if match.range.location > lastEnd {
                let beforeText = String(text[text.index(text.startIndex, offsetBy: lastEnd)..<text.index(text.startIndex, offsetBy: match.range.location)])
                segments.append(CodeSegment(text: beforeText, codeContent: "", isCode: false))
            }
            
            if let codeRange = Range(match.range(at: 1), in: text) {
                let codeContent = String(text[codeRange])
                segments.append(CodeSegment(text: "", codeContent: codeContent, isCode: true))
            }
            
            lastEnd = match.range.location + match.range.length
        }
        
        if lastEnd < text.count {
            let afterText = String(text[text.index(text.startIndex, offsetBy: lastEnd)...])
            segments.append(CodeSegment(text: afterText, codeContent: "", isCode: false))
        }
        
        return segments
    }
    
    private func formatInlineMarkdown(_ text: String) -> (Text, Bool) {
        var result = Text("")
        let processedText = text
        var hasLinks = false
        
        let patterns: [(pattern: String, style: (String) -> Text)] = [
            (#"~~([^~]+)~~"#, { content in Text(content).strikethrough().foregroundColor(.secondary) }),
            (#"\*\*([^\*]+)\*\*"#, { content in Text(content).bold() }),
            (#"\*([^\*]+)\*"#, { content in Text(content).italic() }),
            (#"`([^`]+)`"#, { content in 
                Text(content)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.primary)
            }),
            (#"\[([^\]]+)\]\(([^)]+)\)"#, { content in 
                hasLinks = true
                return Text(content)
                    .foregroundColor(.blue)
                    .underline()
            })
        ]
        
        var segments: [(text: String, isFormatted: Bool, style: ((String) -> Text)?)] = [(processedText, false, nil)]
        
        for (pattern, styleFunc) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            
            var newSegments: [(text: String, isFormatted: Bool, style: ((String) -> Text)?)] = []
            
            for segment in segments {
                if segment.isFormatted {
                    newSegments.append(segment)
                    continue
                }
                
                let matches = regex.matches(in: segment.text, range: NSRange(location: 0, length: segment.text.count))
                
                if matches.isEmpty {
                    newSegments.append(segment)
                    continue
                }
                
                var lastEnd = 0
                for match in matches {
                    if match.range.location > lastEnd {
                        let beforeText = String(segment.text[segment.text.index(segment.text.startIndex, offsetBy: lastEnd)..<segment.text.index(segment.text.startIndex, offsetBy: match.range.location)])
                        newSegments.append((beforeText, false, nil))
                    }
                    
                    if let range = Range(match.range, in: segment.text) {
                        let fullMatch = String(segment.text[range])
                        var content = fullMatch
                        
                        if pattern.contains("~~") {
                            content = content.replacingOccurrences(of: "~~", with: "")
                        } else if pattern.contains("**") {
                            content = content.replacingOccurrences(of: "**", with: "")
                        } else if pattern.contains("*") && !pattern.contains("**") {
                            content = content.replacingOccurrences(of: "*", with: "")
                        } else if pattern.contains("`") {
                            content = content.replacingOccurrences(of: "`", with: "")
                        } else if pattern.contains("\\[") {
                            if match.numberOfRanges > 1, let linkRange = Range(match.range(at: 1), in: segment.text) {
                                content = String(segment.text[linkRange])
                            }
                        }
                        
                        newSegments.append((content, true, styleFunc))
                    }
                    
                    lastEnd = match.range.location + match.range.length
                }
                
                if lastEnd < segment.text.count {
                    let afterText = String(segment.text[segment.text.index(segment.text.startIndex, offsetBy: lastEnd)...])
                    newSegments.append((afterText, false, nil))
                }
            }
            
            segments = newSegments
        }
        
        for segment in segments {
            if segment.isFormatted, let style = segment.style {
                result = result + style(segment.text)
            } else {
                result = result + Text(segment.text)
            }
        }
        
        return (result, hasLinks)
    }
    
    private func formatInlineMarkdownWithLinks(_ text: String) -> some View {
        let linkPattern = #"\[([^\]]+)\]\(([^)]+)\)"#
        guard let regex = try? NSRegularExpression(pattern: linkPattern) else {
            return AnyView(formatInlineMarkdownAsText(text))
        }
        
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: text.count))
        
        if matches.isEmpty {
            return AnyView(formatInlineMarkdownAsText(text))
        }
        
        let segments = parseTextSegments(text: text, matches: matches)
        
        return AnyView(
            HStack(spacing: 0) {
                ForEach(segments.indices, id: \.self) { index in
                    let segment = segments[index]
                    if segment.isLink {
                        Button(action: {
                            handleLinkTap(segment.url)
                        }) {
                            Text(segment.linkText)
                                .foregroundColor(.blue)
                                .underline()
                        }
                        .buttonStyle(PlainButtonStyle())
                    } else {
                        formatInlineMarkdownAsText(segment.text)
                    }
                }
            }
        )
    }
    
    private struct TextSegment {
        let text: String
        let linkText: String
        let url: String
        let isLink: Bool
    }
    
    private func parseTextSegments(text: String, matches: [NSTextCheckingResult]) -> [TextSegment] {
        var segments: [TextSegment] = []
        var lastEnd = 0
        
        for match in matches {
            if match.range.location > lastEnd {
                let beforeText = String(text[text.index(text.startIndex, offsetBy: lastEnd)..<text.index(text.startIndex, offsetBy: match.range.location)])
                segments.append(TextSegment(text: beforeText, linkText: "", url: "", isLink: false))
            }
            
            if let linkTextRange = Range(match.range(at: 1), in: text),
               let urlRange = Range(match.range(at: 2), in: text) {
                let linkText = String(text[linkTextRange])
                let url = String(text[urlRange])
                segments.append(TextSegment(text: "", linkText: linkText, url: url, isLink: true))
            }
            
            lastEnd = match.range.location + match.range.length
        }
        
        if lastEnd < text.count {
            let afterText = String(text[text.index(text.startIndex, offsetBy: lastEnd)...])
            segments.append(TextSegment(text: afterText, linkText: "", url: "", isLink: false))
        }
        
        return segments
    }
    
    private func handleLinkTap(_ urlString: String) {
        // 内部リンクの場合（#で始まる）は onLinkTap を呼び出す
        if urlString.hasPrefix("#") {
            onLinkTap?(urlString)
        } else {
            // 外部リンクの場合は従来通り URL を開く
            openURL(urlString)
        }
    }
    
    private func openURL(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        
        if UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
    }
    
    private func isNumberedListItem(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let pattern = #"^\d+\. .+"#
        return trimmed.range(of: pattern, options: .regularExpression) != nil
    }
    
    private struct ListInfo {
        let marker: String
        let content: String
        let level: Int
        let isChecklist: Bool
        let isChecked: Bool
    }
    
    private func parseListItem(_ line: String) -> ListInfo? {
        // 統一されたインデントレベル計算を使用
        let level = getIndentLevel(line) // 任意の深さまで対応
        
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        
        // チェックリスト項目の検証
        let checklistPatterns = ["- [x] ", "- [ ] ", "+ [x] ", "+ [ ] ", "* [x] ", "* [ ] "]
        for pattern in checklistPatterns {
            if trimmed.hasPrefix(pattern) {
                let marker = String(pattern.prefix(1))
                let content = String(trimmed.dropFirst(pattern.count))
                let isChecked = pattern.contains("[x]")
                return ListInfo(marker: marker, content: content, level: level, isChecklist: true, isChecked: isChecked)
            }
        }
        
        // 通常のリスト項目の検証
        let listMarkers = ["-", "+", "*"]
        for marker in listMarkers {
            if trimmed.hasPrefix(marker + " ") {
                let content = String(trimmed.dropFirst(marker.count + 1))
                return ListInfo(marker: marker, content: content, level: level, isChecklist: false, isChecked: false)
            }
        }
        
        return nil
    }
    
    private func createListItemView(listInfo: ListInfo, lineIndex: Int) -> some View {
        // UI表示上は最大10レベルまでに制限
        let displayLevel = min(listInfo.level, 10)
        let leadingPadding = CGFloat(displayLevel * 20 + 16)
        
        return HStack(alignment: .top, spacing: 8) {
            if listInfo.isChecklist {
                Button(action: {
                    onToggleChecklist?(lineIndex)
                }) {
                    if listInfo.isChecked {
                        // チェック済み - Apple純正リマインダー風の緑の丸
                        ZStack {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 20, height: 20)
                            Image(systemName: "checkmark")
                                .foregroundColor(.white)
                                .font(.system(size: 12, weight: .bold))
                        }
                    } else {
                        // 未チェック - 境界線だけの丸
                        Circle()
                            .stroke(Color.secondary, lineWidth: 1.5)
                            .frame(width: 20, height: 20)
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .frame(width: 20, height: 20) // 明確なタップ領域
            } else {
                Text("•")
                    .font(.headline)
                    .foregroundColor(.primary)
                    .padding(.top, 1)
                    .frame(minWidth: 12, alignment: .center)
            }
            
            formatInlineMarkdownAsView(listInfo.content)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundColor(listInfo.isChecklist && listInfo.isChecked ? .secondary : .primary)
                .strikethrough(listInfo.isChecklist && listInfo.isChecked)
            
            Spacer()
        }
        .padding(.leading, leadingPadding)
        .padding(.vertical, 2)
    }
    
    private func parseTable(_ rows: [String]) -> AnyView {
        guard !rows.isEmpty else {
            return AnyView(EmptyView())
        }
        
        return AnyView(VStack(spacing: 0) {
            ForEach(0..<rows.count, id: \.self) { rowIndex in
                let cells = rows[rowIndex].components(separatedBy: "|")
                    .dropFirst()
                    .dropLast()
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                
                HStack(spacing: 0) {
                    ForEach(0..<cells.count, id: \.self) { cellIndex in
                        VStack {
                            formatInlineMarkdownAsView(cells[cellIndex])
                                .font(rowIndex == 0 ? .system(.body, weight: .semibold) : .system(.body))
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(rowIndex == 0 ? Color(.systemGray5) : Color(.systemBackground))
                        .overlay(
                            Rectangle()
                                .stroke(Color.gray.opacity(0.4), lineWidth: 0.5)
                        )
                    }
                }
                .frame(maxWidth: .infinity)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.gray.opacity(0.4), lineWidth: 1)
        )
        .padding(.vertical, 4)
        )
    }
}

#Preview {
    MemoEditorView(memo: Memo(content: "# サンプルメモ\n\nこれは**太字**と*斜体*と`インラインコード`のテストです。\n\n## リストの例\n\n- 第1レベル項目1\n    - 第2レベル項目1\n    - 第2レベル項目2\n- 第1レベル項目2\n\n* アスタリスクリスト\n    * 階層2のアスタリスク\n\n## 番号付きリスト\n\n1. 最初の項目\n1. 二番目の項目（1.と書いても2.に）\n1. 三番目の項目（1.と書いても3.に）\n\n別の番号付きリスト：\n\n5. 5から開始\n1. 6になる\n1. 7になる\n\n## チェックリスト\n\n- [x] 完了した項目\n- [ ] 未完了の項目\n- [x] 別の完了項目\n- [ ] まだやることがある項目\n\n## コードの例\n\n- `npm install` でパッケージをインストール\n- `git commit -m \"更新\"` でコミット\n- 変数は `let name = \"Swift\"` で定義\n\n```\nconsole.log(\"Hello World\");\nconst message = \"こんにちは\";\n```\n\n普通のテキストに`混在`したコードも使えます。"), memoStore: MemoStore()) {}
}

import UniformTypeIdentifiers

struct MarkdownDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    
    var content: String
    
    init(content: String = "") {
        self.content = content
    }
    
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let string = String(data: data, encoding: .utf8)
        else {
            throw CocoaError(.fileReadCorruptFile)
        }
        content = string
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = content.data(using: .utf8)!
        return .init(regularFileWithContents: data)
    }
}

// フォルダー選択ピッカー
struct FolderPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var folderStore: FolderStore
    @EnvironmentObject private var memoStore: MemoStore
    let selectedFolder: Folder?
    let folders: [Folder]
    let onSelection: (Folder?) -> Void
    
    var body: some View {
        NavigationView {
            List {
                Section("フォルダーを選択") {
                    // フォルダーなし（メインフォルダー）
                    HStack {
                        Image(systemName: "doc.text")
                            .foregroundColor(.secondary)
                        Text("フォルダーなし")
                            .foregroundColor(.primary)
                        Spacer()
                        if selectedFolder == nil {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onSelection(nil)
                        dismiss()
                    }
                    
                    // フォルダー一覧
                    ForEach(folders) { folder in
                        HStack {
                            Image(systemName: "folder.fill")
                                .foregroundColor(.blue)
                            Text(folder.name)
                                .foregroundColor(.primary)
                            Spacer()
                            if selectedFolder?.id == folder.id {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onSelection(folder)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("フォルダーを選択")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - MermaidView
struct MermaidView: View {
    let code: String
    @State private var renderedImage: UIImage?
    @State private var isLoading = true
    @State private var errorMessage: String?
    
    var body: some View {
        VStack {
            if isLoading {
                ProgressView("マーメイド図を生成中...")
                    .frame(height: 100)
            } else if let image = renderedImage {
                ScrollView([.horizontal, .vertical], showsIndicators: true) {
                    Image(uiImage: image)
                        .background(Color.white)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                        .frame(width: image.size.width, height: image.size.height) // 実際のサイズでスクロール
                }
                .frame(maxWidth: .infinity, maxHeight: 500) // フレーム制限
            } else if let error = errorMessage {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                        .font(.title2)
                    Text("マーメイド図の生成に失敗しました")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    // フォールバック：元のコードを表示
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(code)
                            .font(.system(.caption, design: .monospaced))
                            .padding(8)
                            .background(Color(.systemGray6))
                            .cornerRadius(4)
                    }
                }
                .padding()
                .background(Color(.systemGray6).opacity(0.5))
                .cornerRadius(8)
            }
        }
        .onAppear {
            generateMermaidImage()
        }
    }
    
    private func generateMermaidImage() {
        isLoading = true
        errorMessage = nil
        
        DispatchQueue.global(qos: .userInitiated).async {
            let result = renderMermaidToImage(code: code)
            
            DispatchQueue.main.async {
                isLoading = false
                switch result {
                case .success(let image):
                    renderedImage = image
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    private func renderMermaidToImage(code: String) -> Result<UIImage, Error> {
        // マーメイド図の種類を判定
        let diagramType = detectDiagramType(from: code)
        
        // 簡易的なSVG生成（実際のマーメイド構文解析の代替）
        let svgContent = generateSimplifiedSVG(for: diagramType, code: code)
        
        // SVGからUIImageに変換
        return convertSVGToImage(svgContent: svgContent)
    }
    
    private func detectDiagramType(from code: String) -> MermaidDiagramType {
        let cleanCode = code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        if cleanCode.hasPrefix("sequencediagram") {
            return .sequence
        } else if cleanCode.hasPrefix("classDiagram") || cleanCode.hasPrefix("classdiagram") {
            return .classDiagram
        } else if cleanCode.hasPrefix("gantt") {
            return .gantt
        } else if cleanCode.hasPrefix("flowchart") || cleanCode.hasPrefix("graph") {
            return .flowchart
        } else if cleanCode.hasPrefix("pie") {
            return .pie
        } else {
            return .flowchart // デフォルト
        }
    }
    
    private func generateSimplifiedSVG(for type: MermaidDiagramType, code: String) -> String {
        switch type {
        case .sequence:
            return generateSequenceDiagramSVG(code: code)
        case .classDiagram:
            return generateClassDiagramSVG(code: code)
        case .gantt:
            return generateGanttChartSVG(code: code)
        case .flowchart:
            return generateFlowchartSVG(code: code)
        case .pie:
            return generatePieChartSVG(code: code)
        }
    }
    
    private func generateSequenceDiagramSVG(code: String) -> String {
        return """
        <svg width="400" height="200" xmlns="http://www.w3.org/2000/svg">
        <rect width="100%" height="100%" fill="#f8f9fa" stroke="none"/>
        
        <text x="200" y="80" text-anchor="middle" font-family="Arial" font-size="16" font-weight="500" fill="#666">シーケンス図</text>
        <text x="200" y="110" text-anchor="middle" font-family="Arial" font-size="14" fill="#999">現在非対応です</text>
        
        </svg>
        """
    }
    
    private func generateClassDiagramSVG(code: String) -> String {
        let lines = code.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.lowercased().hasPrefix("classdiagram") }
        
        var classes: [ClassInfo] = []
        var relationships: [ClassRelationship] = []
        
        // 複数行にわたるクラス定義の解析
        var currentClass: (name: String, members: [String])? = nil
        var inClassDefinition = false
        
        for line in lines {
            // クラス定義の開始
            if line.hasPrefix("class ") && line.contains("{") {
                let className = extractClassName(from: line)
                currentClass = (name: className, members: [])
                inClassDefinition = true
                
                // 同じ行にメンバーがある場合
                if let memberStart = line.firstIndex(of: "{") {
                    let memberPart = String(line[line.index(after: memberStart)...])
                    if memberPart.contains("}") {
                        // 単一行でクラス定義が完了
                        let members = extractMembersFromLine(memberPart)
                        let newAttributes = extractAttributes(from: members)
                        let newMethods = extractMethods(from: members)
                        
                        // 既存クラスと重複しない場合のみ追加
                        if !classes.contains(where: { $0.name == className }) {
                            classes.append(ClassInfo(name: className, attributes: newAttributes, methods: newMethods))
                        } else {
                            // 既存クラスをマージ
                            if let existingIndex = classes.firstIndex(where: { $0.name == className }) {
                                let existingClass = classes[existingIndex]
                                classes[existingIndex] = ClassInfo(
                                    name: existingClass.name,
                                    attributes: Array(Set(existingClass.attributes + newAttributes)),
                                    methods: Array(Set(existingClass.methods + newMethods))
                                )
                            }
                        }
                        currentClass = nil
                        inClassDefinition = false
                    } else {
                        // 複数行のクラス定義開始
                        let members = extractMembersFromLine(memberPart)
                        currentClass?.members.append(contentsOf: members)
                    }
                }
            }
            // クラス定義の継続
            else if inClassDefinition && currentClass != nil {
                if line.contains("}") {
                    // クラス定義の終了
                    let memberPart = String(line.prefix(while: { $0 != "}" }))
                    let members = extractMembersFromLine(memberPart)
                    currentClass?.members.append(contentsOf: members)
                    
                    if let classData = currentClass {
                        // 既存クラスと重複しない場合のみ追加
                        if !classes.contains(where: { $0.name == classData.name }) {
                            classes.append(ClassInfo(
                                name: classData.name,
                                attributes: extractAttributes(from: classData.members),
                                methods: extractMethods(from: classData.members)
                            ))
                        } else {
                            // 既存クラスをマージ
                            if let existingIndex = classes.firstIndex(where: { $0.name == classData.name }) {
                                let existingClass = classes[existingIndex]
                                let newAttributes = extractAttributes(from: classData.members)
                                let newMethods = extractMethods(from: classData.members)
                                classes[existingIndex] = ClassInfo(
                                    name: existingClass.name,
                                    attributes: Array(Set(existingClass.attributes + newAttributes)),
                                    methods: Array(Set(existingClass.methods + newMethods))
                                )
                            }
                        }
                    }
                    currentClass = nil
                    inClassDefinition = false
                } else {
                    // クラス定義の中身
                    let members = extractMembersFromLine(line)
                    currentClass?.members.append(contentsOf: members)
                }
            }
            // 単純なクラス宣言（{}なし）
            else if line.hasPrefix("class ") && !line.contains("{") {
                let className = extractClassName(from: line)
                if !classes.contains(where: { $0.name == className }) {
                    classes.append(ClassInfo(name: className, attributes: [], methods: []))
                }
            }
            // リレーションシップの解析（右向きと左向きの両方）
            else if line.contains("-->") || line.contains("--|>") || line.contains("..|>") || line.contains("--*") || line.contains("--o") ||
                    line.contains("<--") || line.contains("<|--") || line.contains("<|..") || line.contains("*--") || line.contains("o--") {
                if let relationship = parseClassRelationship(line) {
                    relationships.append(relationship)
                    
                    // リレーションシップに含まれるクラス名も追加（まだ存在しない場合のみ）
                    for className in [relationship.from, relationship.to] {
                        if !classes.contains(where: { $0.name == className }) {
                            classes.append(ClassInfo(name: className, attributes: [], methods: []))
                        }
                    }
                }
            }
        }
        
        // マーメイド記法の標準的な書式にも対応（クラス名: メンバー形式）
        for line in lines {
            if line.contains(":") && !line.contains("-->") && !line.contains("--|>") && !line.contains("..|>") && !line.contains("--*") && !line.contains("--o") &&
               !line.contains("<--") && !line.contains("<|--") && !line.contains("<|..") && !line.contains("*--") && !line.contains("o--") {
                // "ClassName : +attribute" や "ClassName : +method()" 形式の解析
                let parts = line.components(separatedBy: ":").map { $0.trimmingCharacters(in: .whitespaces) }
                if parts.count >= 2 {
                    let className = parts[0]
                    let member = parts[1]
                    
                    // 既存のクラスを探すか新規作成
                    if let existingIndex = classes.firstIndex(where: { $0.name == className }) {
                        let existingClass = classes[existingIndex]
                        if member.contains("()") {
                            // メソッド（重複チェック）
                            if !existingClass.methods.contains(member) {
                                let newMethods = existingClass.methods + [member]
                                classes[existingIndex] = ClassInfo(name: existingClass.name, attributes: existingClass.attributes, methods: newMethods)
                            }
                        } else {
                            // 属性（重複チェック）
                            if !existingClass.attributes.contains(member) {
                                let newAttributes = existingClass.attributes + [member]
                                classes[existingIndex] = ClassInfo(name: existingClass.name, attributes: newAttributes, methods: existingClass.methods)
                            }
                        }
                    } else {
                        // 新規クラス作成
                        if member.contains("()") {
                            classes.append(ClassInfo(name: className, attributes: [], methods: [member]))
                        } else {
                            classes.append(ClassInfo(name: className, attributes: [member], methods: []))
                        }
                    }
                }
            }
        }
        
        // クラスが見つからない場合のフォールバック
        if classes.isEmpty {
            classes = [
                ClassInfo(name: "Animal", attributes: ["+name: String", "+age: int"], methods: ["+makeSound(): void"]),
                ClassInfo(name: "Dog", attributes: ["+breed: String"], methods: ["+bark(): void"])
            ]
            relationships = [ClassRelationship(from: "Animal", to: "Dog", type: "inheritance")]
        }
        
        // レイアウト計算
        let classWidth: CGFloat = 200
        let classHeight: CGFloat = 120
        let horizontalSpacing: CGFloat = 250
        let verticalSpacing: CGFloat = 150
        
        let cols = min(3, max(1, Int(sqrt(Double(classes.count)))))
        let rows = (classes.count + cols - 1) / cols
        
        // クラスボックスの実際のサイズを考慮して描画範囲を計算
        let maxClassWidth = classes.map { calculateClassBoxSize($0).width }.max() ?? classWidth
        let maxClassHeight = classes.map { calculateClassBoxSize($0).height }.max() ?? classHeight
        
        let width = max(400, cols * Int(max(horizontalSpacing, maxClassWidth + 100)))
        let height = max(400, rows * Int(max(verticalSpacing, maxClassHeight + 100)))
        
        var svg = """
        <svg width="\(width)" height="\(height)" xmlns="http://www.w3.org/2000/svg">
        <defs>
        <!-- 通常の矢印（関連用） -->
        <marker id="arrowhead" markerWidth="10" markerHeight="7" refX="9" refY="3.5" orient="auto" markerUnits="strokeWidth">
        <polygon points="0 0, 10 3.5, 0 7" fill="#333" stroke="#333" stroke-width="1" />
        </marker>
        
        <!-- 三角形の矢印（継承用） -->
        <marker id="inheritance-arrow" markerWidth="12" markerHeight="10" refX="11" refY="5" orient="auto" markerUnits="strokeWidth">
        <polygon points="0 0, 12 5, 0 10" fill="white" stroke="#333" stroke-width="2" />
        </marker>
        
        <!-- 点線の三角形矢印（実装用） -->
        <marker id="implementation-arrow" markerWidth="12" markerHeight="10" refX="11" refY="5" orient="auto" markerUnits="strokeWidth">
        <polygon points="0 0, 12 5, 0 10" fill="white" stroke="#333" stroke-width="2" stroke-dasharray="3,3" />
        </marker>
        
        <!-- ダイヤモンド（コンポジション用） -->
        <marker id="composition-diamond" markerWidth="14" markerHeight="10" refX="13" refY="5" orient="auto" markerUnits="strokeWidth">
        <polygon points="0 5, 7 0, 14 5, 7 10" fill="#333" stroke="#333" stroke-width="1" />
        </marker>
        
        <!-- 白いダイヤモンド（アグリゲーション用） -->
        <marker id="aggregation-diamond" markerWidth="14" markerHeight="10" refX="13" refY="5" orient="auto" markerUnits="strokeWidth">
        <polygon points="0 5, 7 0, 14 5, 7 10" fill="white" stroke="#333" stroke-width="2" />
        </marker>
        </defs>
        <rect width="100%" height="100%" fill="white"/>
        """
        
        // クラスボックスの描画
        for (index, classInfo) in classes.enumerated() {
            let col = index % cols
            let row = index / cols
            let x = 50 + col * Int(horizontalSpacing)
            let y = 50 + row * Int(verticalSpacing)
            
            svg += generateClassBox(classInfo: classInfo, x: x, y: y, width: Int(classWidth), height: Int(classHeight))
        }
        
        // リレーションシップの描画
        for relationship in relationships {
            if let fromIndex = classes.firstIndex(where: { $0.name == relationship.from }),
               let toIndex = classes.firstIndex(where: { $0.name == relationship.to }) {
                
                let fromCol = fromIndex % cols
                let fromRow = fromIndex / cols
                let fromX = 50 + fromCol * Int(horizontalSpacing)
                let fromY = 50 + fromRow * Int(verticalSpacing)
                
                let toCol = toIndex % cols
                let toRow = toIndex / cols
                let toX = 50 + toCol * Int(horizontalSpacing)
                let toY = 50 + toRow * Int(verticalSpacing)
                
                // クラスボックスの境界に合わせて線の開始・終了点を計算
                let (startX, startY, endX, endY) = calculateConnectionPoints(
                    fromX: fromX, fromY: fromY, fromWidth: Int(classWidth), fromHeight: Int(classHeight),
                    toX: toX, toY: toY, toWidth: Int(classWidth), toHeight: Int(classHeight)
                )
                
                svg += generateRelationshipLine(relationship: relationship, fromX: startX, fromY: startY, toX: endX, toY: endY)
            }
        }
        
        svg += "</svg>"
        return svg
    }
    
    private func extractClassName(from line: String) -> String {
        // "class ClassName" または "class ClassName {" からクラス名を抽出
        let classKeywordRemoved = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
        if let braceIndex = classKeywordRemoved.firstIndex(of: "{") {
            return String(classKeywordRemoved[..<braceIndex]).trimmingCharacters(in: .whitespaces)
        }
        return classKeywordRemoved
    }
    
    private func extractMembersFromLine(_ line: String) -> [String] {
        // 行からメンバー（属性やメソッド）を抽出
        let cleanLine = line.replacingOccurrences(of: "}", with: "")
        return cleanLine.components(separatedBy: CharacterSet(charactersIn: ";\n"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
    
    private func extractAttributes(from members: [String]) -> [String] {
        return members.filter { member in
            // 属性の判定：()を含まず、:を含む
            !member.contains("()") && (member.contains(":") || member.hasPrefix("+") || member.hasPrefix("-") || member.hasPrefix("#"))
        }.map { member in
            // 属性の整形
            if member.contains(":") {
                return member
            } else {
                // ":type" がない場合はデフォルトタイプを追加
                return "\(member): String"
            }
        }
    }
    
    private func extractMethods(from members: [String]) -> [String] {
        return members.filter { member in
            // メソッドの判定：()を含む
            member.contains("()")
        }.map { member in
            // メソッドの整形
            if member.contains(":") {
                return member
            } else {
                // 戻り値の型がない場合はvoidを追加
                return "\(member): void"
            }
        }
    }
    
    private func parseClassRelationship(_ line: String) -> ClassRelationship? {
        // 右向きの矢印パターン
        let rightArrowPatterns = [
            ("-->", "association"),
            ("--|>", "inheritance"),
            ("..|>", "implementation"),
            ("--*", "composition"),
            ("--o", "aggregation")
        ]
        
        // 左向きの矢印パターン
        let leftArrowPatterns = [
            ("<--", "association"),
            ("<|--", "inheritance"),
            ("<|..", "implementation"),
            ("*--", "composition"),
            ("o--", "aggregation")
        ]
        
        // 右向きの矢印をチェック
        for (pattern, type) in rightArrowPatterns {
            if line.contains(pattern) {
                let parts = line.components(separatedBy: pattern)
                if parts.count >= 2 {
                    let from = parts[0].trimmingCharacters(in: .whitespaces)
                    let to = parts[1].trimmingCharacters(in: .whitespaces)
                    return ClassRelationship(from: from, to: to, type: type)
                }
            }
        }
        
        // 左向きの矢印をチェック
        for (pattern, type) in leftArrowPatterns {
            if line.contains(pattern) {
                let parts = line.components(separatedBy: pattern)
                if parts.count >= 2 {
                    // 左向きなので from と to を逆にする
                    let from = parts[1].trimmingCharacters(in: .whitespaces)
                    let to = parts[0].trimmingCharacters(in: .whitespaces)
                    return ClassRelationship(from: from, to: to, type: type)
                }
            }
        }
        
        return nil
    }
    
    private func generateClassBox(classInfo: ClassInfo, x: Int, y: Int, width: Int, height: Int) -> String {
        let headerHeight = 30
        let attributeHeight = max(30, classInfo.attributes.count * 15 + 10)
        let methodHeight = max(30, classInfo.methods.count * 15 + 10)
        let totalHeight = headerHeight + attributeHeight + methodHeight
        
        var svg = """
        <!-- Class: \(classInfo.name) -->
        <rect x="\(x)" y="\(y)" width="\(width)" height="\(totalHeight)" fill="#f1f8e9" stroke="#689f38" stroke-width="2" rx="5"/>
        
        <!-- Class name -->
        <rect x="\(x)" y="\(y)" width="\(width)" height="\(headerHeight)" fill="#c8e6c9" stroke="#689f38" stroke-width="1" rx="5"/>
        <text x="\(x + width/2)" y="\(y + headerHeight/2 + 5)" text-anchor="middle" font-family="Arial, sans-serif" font-size="14" font-weight="bold" fill="#1b5e20">\(classInfo.name)</text>
        
        <!-- Separator line -->
        <line x1="\(x)" y1="\(y + headerHeight)" x2="\(x + width)" y2="\(y + headerHeight)" stroke="#689f38" stroke-width="1"/>
        
        """
        
        // 属性の描画
        for (index, attribute) in classInfo.attributes.enumerated() {
            let attrY = y + headerHeight + 15 + index * 15
            svg += """
            <text x="\(x + 10)" y="\(attrY)" font-family="Arial, sans-serif" font-size="11" fill="#333">\(attribute)</text>
            """
        }
        
        // 属性とメソッドの区切り線
        let separatorY = y + headerHeight + attributeHeight
        svg += """
        <line x1="\(x)" y1="\(separatorY)" x2="\(x + width)" y2="\(separatorY)" stroke="#689f38" stroke-width="1"/>
        """
        
        // メソッドの描画
        for (index, method) in classInfo.methods.enumerated() {
            let methodY = separatorY + 15 + index * 15
            svg += """
            <text x="\(x + 10)" y="\(methodY)" font-family="Arial, sans-serif" font-size="11" fill="#333">\(method)</text>
            """
        }
        
        return svg
    }
    
    private func calculateConnectionPoints(fromX: Int, fromY: Int, fromWidth: Int, fromHeight: Int,
                                         toX: Int, toY: Int, toWidth: Int, toHeight: Int) -> (Int, Int, Int, Int) {
        // 各クラスボックスの中央点
        let fromCenterX = fromX + fromWidth / 2
        let fromCenterY = fromY + fromHeight / 2
        let toCenterX = toX + toWidth / 2
        let toCenterY = toY + toHeight / 2
        
        // 方向ベクトル
        let dx = toCenterX - fromCenterX
        let dy = toCenterY - fromCenterY
        
        // 開始点（fromボックスの境界）
        var startX = fromCenterX
        var startY = fromCenterY
        
        if abs(dx) > abs(dy) {
            // 水平方向が主
            if dx > 0 {
                // 右向き
                startX = fromX + fromWidth
                startY = fromCenterY
            } else {
                // 左向き
                startX = fromX
                startY = fromCenterY
            }
        } else {
            // 垂直方向が主
            if dy > 0 {
                // 下向き
                startX = fromCenterX
                startY = fromY + fromHeight
            } else {
                // 上向き
                startX = fromCenterX
                startY = fromY
            }
        }
        
        // 終了点（toボックスの境界）
        var endX = toCenterX
        var endY = toCenterY
        
        if abs(dx) > abs(dy) {
            // 水平方向が主
            if dx > 0 {
                // 左から右へ
                endX = toX
                endY = toCenterY
            } else {
                // 右から左へ
                endX = toX + toWidth
                endY = toCenterY
            }
        } else {
            // 垂直方向が主
            if dy > 0 {
                // 上から下へ
                endX = toCenterX
                endY = toY
            } else {
                // 下から上へ
                endX = toCenterX
                endY = toY + toHeight
            }
        }
        
        return (startX, startY, endX, endY)
    }
    
    private func generateRelationshipLine(relationship: ClassRelationship, fromX: Int, fromY: Int, toX: Int, toY: Int) -> String {
        let strokeDasharray: String
        let strokeWidth: String
        
        switch relationship.type {
        case "inheritance":
            strokeDasharray = ""
            strokeWidth = "2"
        case "implementation":
            strokeDasharray = "5,3"
            strokeWidth = "2"
        case "composition":
            strokeDasharray = ""
            strokeWidth = "2"
        case "aggregation":
            strokeDasharray = ""
            strokeWidth = "2"
        default: // association
            strokeDasharray = ""
            strokeWidth = "1.5"
        }
        
        // 矢印の方向を計算
        let dx = toX - fromX
        let dy = toY - fromY
        let length = sqrt(Double(dx * dx + dy * dy))
        
        // 矢印のサイズ
        let arrowLength = 12.0
        let arrowWidth = 8.0
        
        // 矢印の先端を線の終点から少し手前に
        let adjustedLength = length - arrowLength
        let adjustedToX = fromX + Int(Double(dx) * adjustedLength / length)
        let adjustedToY = fromY + Int(Double(dy) * adjustedLength / length)
        
        // 矢印の方向ベクトル（正規化）
        let unitX = Double(dx) / length
        let unitY = Double(dy) / length
        
        // 矢印の垂直ベクトル
        let perpX = -unitY
        let perpY = unitX
        
        // 矢印の3つの点を計算
        let arrowTipX = toX
        let arrowTipY = toY
        let arrowBase1X = arrowTipX - Int(unitX * arrowLength + perpX * arrowWidth / 2)
        let arrowBase1Y = arrowTipY - Int(unitY * arrowLength + perpY * arrowWidth / 2)
        let arrowBase2X = arrowTipX - Int(unitX * arrowLength - perpX * arrowWidth / 2)
        let arrowBase2Y = arrowTipY - Int(unitY * arrowLength - perpY * arrowWidth / 2)
        
        var arrowSvg = ""
        
        // 関係線の種類に応じた矢印の描画
        switch relationship.type {
        case "inheritance":
            // 白い三角形の矢印
            arrowSvg = """
            <polygon points="\(arrowTipX),\(arrowTipY) \(arrowBase1X),\(arrowBase1Y) \(arrowBase2X),\(arrowBase2Y)" fill="white" stroke="#333" stroke-width="2"/>
            """
        case "implementation":
            // 白い三角形の矢印（点線用）
            arrowSvg = """
            <polygon points="\(arrowTipX),\(arrowTipY) \(arrowBase1X),\(arrowBase1Y) \(arrowBase2X),\(arrowBase2Y)" fill="white" stroke="#333" stroke-width="2"/>
            """
        case "composition":
            // 黒いダイヤモンド
            let diamondSize = 8.0
            let diamondTipX = toX
            let diamondTipY = toY
            let diamondBack1X = diamondTipX - Int(unitX * diamondSize)
            let diamondBack1Y = diamondTipY - Int(unitY * diamondSize)
            let diamondSide1X = diamondBack1X - Int(perpX * diamondSize / 2)
            let diamondSide1Y = diamondBack1Y - Int(perpY * diamondSize / 2)
            let diamondSide2X = diamondBack1X + Int(perpX * diamondSize / 2)
            let diamondSide2Y = diamondBack1Y + Int(perpY * diamondSize / 2)
            let diamondBackX = diamondTipX - Int(unitX * diamondSize * 2)
            let diamondBackY = diamondTipY - Int(unitY * diamondSize * 2)
            
            arrowSvg = """
            <polygon points="\(diamondTipX),\(diamondTipY) \(diamondSide1X),\(diamondSide1Y) \(diamondBackX),\(diamondBackY) \(diamondSide2X),\(diamondSide2Y)" fill="#333" stroke="#333" stroke-width="1"/>
            """
        case "aggregation":
            // 白いダイヤモンド
            let diamondSize = 8.0
            let diamondTipX = toX
            let diamondTipY = toY
            let diamondBack1X = diamondTipX - Int(unitX * diamondSize)
            let diamondBack1Y = diamondTipY - Int(unitY * diamondSize)
            let diamondSide1X = diamondBack1X - Int(perpX * diamondSize / 2)
            let diamondSide1Y = diamondBack1Y - Int(perpY * diamondSize / 2)
            let diamondSide2X = diamondBack1X + Int(perpX * diamondSize / 2)
            let diamondSide2Y = diamondBack1Y + Int(perpY * diamondSize / 2)
            let diamondBackX = diamondTipX - Int(unitX * diamondSize * 2)
            let diamondBackY = diamondTipY - Int(unitY * diamondSize * 2)
            
            arrowSvg = """
            <polygon points="\(diamondTipX),\(diamondTipY) \(diamondSide1X),\(diamondSide1Y) \(diamondBackX),\(diamondBackY) \(diamondSide2X),\(diamondSide2Y)" fill="white" stroke="#333" stroke-width="2"/>
            """
        default: // association
            // 通常の矢印
            arrowSvg = """
            <polygon points="\(arrowTipX),\(arrowTipY) \(arrowBase1X),\(arrowBase1Y) \(arrowBase2X),\(arrowBase2Y)" fill="#333" stroke="#333" stroke-width="1"/>
            """
        }
        
        return """
        <!-- Relationship: \(relationship.from) \(relationship.type) \(relationship.to) -->
        <line x1="\(fromX)" y1="\(fromY)" x2="\(adjustedToX)" y2="\(adjustedToY)" stroke="#333" stroke-width="\(strokeWidth)" stroke-dasharray="\(strokeDasharray)" fill="none"/>
        \(arrowSvg)
        """
    }
    
    private func generateGanttChartSVG(code: String) -> String {
        return """
        <svg width="400" height="200" xmlns="http://www.w3.org/2000/svg">
        <rect x="50" y="40" width="300" height="20" fill="#4caf50" rx="3"/>
        <rect x="80" y="70" width="200" height="20" fill="#2196f3" rx="3"/>
        <rect x="60" y="100" width="250" height="20" fill="#ff9800" rx="3"/>
        <text x="20" y="55" font-family="Arial" font-size="12" fill="#333">タスク1</text>
        <text x="20" y="85" font-family="Arial" font-size="12" fill="#333">タスク2</text>
        <text x="20" y="115" font-family="Arial" font-size="12" fill="#333">タスク3</text>
        <text x="200" y="25" text-anchor="middle" font-family="Arial" font-size="14" font-weight="bold" fill="#333">ガントチャート</text>
        </svg>
        """
    }
    
    // フローチャート用の構造体定義
    struct FlowNode {
        let id: String
        let label: String
        let type: NodeType
        var x: CGFloat = 0
        var y: CGFloat = 0
        
        enum NodeType {
            case process        // [text] 四角形
            case startEnd       // (text) 楕円
            case decision       // {text} ひし形
            case subroutine     // [[text]] サブルーチン
            case database       // [(text)] データベース
            case circle         // ((text)) 円/接続点
        }
    }
    
    struct FlowConnection {
        let from: String
        let to: String
        let label: String
        let style: ConnectionStyle
        
        enum ConnectionStyle {
            case solid      // -->
            case thick      // ==>
            case dotted     // -.->
            case circle     // --o
            case cross      // --x
        }
    }
    
    enum FlowDirection {
        case topDown    // TD/TB
        case bottomTop  // BT
        case leftRight  // LR
        case rightLeft  // RL
    }
    
    private func generateFlowchartSVG(code: String) -> String {
        let lines = code.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        var nodes: [FlowNode] = []
        var connections: [FlowConnection] = []
        var direction: FlowDirection = .topDown
        
        // 最初の行から方向を解析
        if let firstLine = lines.first?.lowercased() {
            if firstLine.contains("flowchart") || firstLine.contains("graph") {
                if firstLine.contains("td") || firstLine.contains("tb") {
                    direction = .topDown
                } else if firstLine.contains("bt") {
                    direction = .bottomTop
                } else if firstLine.contains("lr") {
                    direction = .leftRight
                } else if firstLine.contains("rl") {
                    direction = .rightLeft
                }
            }
        }
        
        let filteredLines = lines.filter { 
            !$0.isEmpty && 
            !$0.lowercased().hasPrefix("flowchart") && 
            !$0.lowercased().hasPrefix("graph") 
        }
        
        // マーメイド記法の解析
        for line in filteredLines {
            // ノード定義とコネクションの解析
            if line.contains("-->") || line.contains("==>") || line.contains("-.->") || line.contains("--o") || line.contains("--x") {
                parseFlowchartConnection(line: line, nodes: &nodes, connections: &connections)
            }
        }
        
        // フォールバック（ノードが見つからない場合）
        if nodes.isEmpty {
            nodes = [
                FlowNode(id: "A", label: "開始", type: .startEnd),
                FlowNode(id: "B", label: "条件", type: .decision),
                FlowNode(id: "C", label: "処理A", type: .process),
                FlowNode(id: "D", label: "処理B", type: .process)
            ]
            connections = [
                FlowConnection(from: "A", to: "B", label: "", style: .solid),
                FlowConnection(from: "B", to: "C", label: "Yes", style: .solid),
                FlowConnection(from: "B", to: "D", label: "No", style: .solid)
            ]
        }
        
        // レイアウト計算
        calculateFlowchartLayout(nodes: &nodes, connections: connections, direction: direction)
        
        // 描画範囲を動的に計算（横に広がったレイアウトに対応）
        let bounds = calculateBounds(for: nodes)
        let width = Int(max(800, bounds.maxX - bounds.minX + 300)) // 最小幅と余白を増加
        let height = Int(max(400, bounds.maxY - bounds.minY + 200)) // 余白を増加
        
        var svg = """
        <svg width="\(width)" height="\(height)" xmlns="http://www.w3.org/2000/svg">
        <rect width="100%" height="100%" fill="white"/>
        """
        
        // ノードの描画
        for node in nodes {
            svg += drawFlowchartNode(node: node)
        }
        
        // コネクションの描画
        for connection in connections {
            if let fromNode = nodes.first(where: { $0.id == connection.from }),
               let toNode = nodes.first(where: { $0.id == connection.to }) {
                svg += drawFlowchartConnection(from: fromNode, to: toNode, connection: connection)
            }
        }
        
        svg += "</svg>"
        return svg
    }
    
    private func parseFlowchartConnection(line: String, nodes: inout [FlowNode], connections: inout [FlowConnection]) {
        // -- Yes --> 形式のラベル付きコネクションの処理
        if let dashMatch = line.range(of: #"--\s*(\w+)\s*-->"#, options: .regularExpression) {
            let beforeDash = String(line[..<dashMatch.lowerBound]).trimmingCharacters(in: .whitespaces)
            let afterArrow = String(line[dashMatch.upperBound...]).trimmingCharacters(in: .whitespaces)
            
            // ラベルを抽出
            let labelPattern = #"--\s*(\w+)\s*-->"#
            let regex = try! NSRegularExpression(pattern: labelPattern)
            let nsRange = NSRange(dashMatch, in: line)
            if let match = regex.firstMatch(in: line, range: nsRange),
               let labelRange = Range(match.range(at: 1), in: line) {
                let label = String(line[labelRange])
                
                let fromNode = extractFlowchartNode(from: beforeDash)
                let toNode = extractFlowchartNode(from: afterArrow)
                
                // 重複チェックして追加（既存ノードとマージ）
                if !nodes.contains(where: { $0.id == fromNode.id }) {
                    nodes.append(fromNode)
                } else if let existingIndex = nodes.firstIndex(where: { $0.id == fromNode.id }) {
                    // 既存ノードのラベルが空の場合、新しいラベルで更新
                    if nodes[existingIndex].label.isEmpty || nodes[existingIndex].label == fromNode.id {
                        nodes[existingIndex] = FlowNode(id: fromNode.id, label: fromNode.label, type: fromNode.type)
                    }
                }
                
                if !nodes.contains(where: { $0.id == toNode.id }) {
                    nodes.append(toNode)
                } else if let existingIndex = nodes.firstIndex(where: { $0.id == toNode.id }) {
                    // 既存ノードのラベルが空の場合、新しいラベルで更新
                    if nodes[existingIndex].label.isEmpty || nodes[existingIndex].label == toNode.id {
                        nodes[existingIndex] = FlowNode(id: toNode.id, label: toNode.label, type: toNode.type)
                    }
                }
                
                connections.append(FlowConnection(from: fromNode.id, to: toNode.id, label: label, style: .solid))
                return
            }
        }
        
        // 各種矢印パターンに対応
        let arrowPatterns = [
            ("==>", FlowConnection.ConnectionStyle.thick),
            ("-.->", FlowConnection.ConnectionStyle.dotted),
            ("-->", FlowConnection.ConnectionStyle.solid),
            ("--o", FlowConnection.ConnectionStyle.circle),
            ("--x", FlowConnection.ConnectionStyle.cross)
        ]
        
        for (arrowSymbol, style) in arrowPatterns {
            if line.contains(arrowSymbol) {
                let arrowParts = line.components(separatedBy: arrowSymbol)
                if arrowParts.count >= 2 {
                    let fromPart = arrowParts[0].trimmingCharacters(in: .whitespaces)
                    var toPart = arrowParts[1].trimmingCharacters(in: .whitespaces)
                    var connectionLabel = ""
                    
                    // ラベル付きコネクションの処理 |Yes|
                    if let labelStart = toPart.firstIndex(of: "|"),
                       let labelEnd = toPart.lastIndex(of: "|"),
                       labelStart != labelEnd {
                        let labelRange = toPart.index(after: labelStart)..<labelEnd
                        connectionLabel = String(toPart[labelRange])
                        toPart = String(toPart[toPart.index(after: labelEnd)...]).trimmingCharacters(in: .whitespaces)
                    }
                    
                    // ノードの抽出と作成
                    let fromNode = extractFlowchartNode(from: fromPart)
                    let toNode = extractFlowchartNode(from: toPart)
                    
                    // 重複チェックして追加（既存ノードとマージ）
                    if !nodes.contains(where: { $0.id == fromNode.id }) {
                        nodes.append(fromNode)
                    } else if let existingIndex = nodes.firstIndex(where: { $0.id == fromNode.id }) {
                        // 既存ノードのラベルが空の場合、新しいラベルで更新
                        if nodes[existingIndex].label.isEmpty || nodes[existingIndex].label == fromNode.id {
                            nodes[existingIndex] = FlowNode(id: fromNode.id, label: fromNode.label, type: fromNode.type)
                        }
                    }
                    
                    if !nodes.contains(where: { $0.id == toNode.id }) {
                        nodes.append(toNode)
                    } else if let existingIndex = nodes.firstIndex(where: { $0.id == toNode.id }) {
                        // 既存ノードのラベルが空の場合、新しいラベルで更新
                        if nodes[existingIndex].label.isEmpty || nodes[existingIndex].label == toNode.id {
                            nodes[existingIndex] = FlowNode(id: toNode.id, label: toNode.label, type: toNode.type)
                        }
                    }
                    
                    connections.append(FlowConnection(from: fromNode.id, to: toNode.id, label: connectionLabel, style: style))
                    return
                }
            }
        }
    }
    
    private func extractFlowchartNode(from text: String) -> FlowNode {
        let trimmed = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ";", with: "")
        
        // 各種ノード形式の解析
        if trimmed.contains("[[") && trimmed.contains("]]") {
            // サブルーチンノード A[[テキスト]]
            let parts = trimmed.components(separatedBy: "[[")
            let id = parts[0].trimmingCharacters(in: .whitespaces)
            let labelPart = parts.dropFirst().joined(separator: "[[")
            let label = labelPart.replacingOccurrences(of: "]]", with: "")
            return FlowNode(id: id, label: label, type: .subroutine)
        } else if trimmed.contains("[(") && trimmed.contains(")]") {
            // データベースノード A[(テキスト)]
            let parts = trimmed.components(separatedBy: "[(")
            let id = parts[0].trimmingCharacters(in: .whitespaces)
            let labelPart = parts.dropFirst().joined(separator: "[(")
            let label = labelPart.replacingOccurrences(of: ")]", with: "")
            return FlowNode(id: id, label: label, type: .database)
        } else if trimmed.contains("[") && trimmed.contains("]") {
            // 矩形ノード A[テキスト]
            let parts = trimmed.components(separatedBy: "[")
            let id = parts[0].trimmingCharacters(in: .whitespaces)
            let labelPart = parts.dropFirst().joined(separator: "[")
            let label = labelPart.replacingOccurrences(of: "]", with: "")
            return FlowNode(id: id, label: label, type: .process)
        } else if trimmed.contains("(") && trimmed.contains(")") && !trimmed.contains("((") {
            // 楕円ノード A(テキスト)
            let parts = trimmed.components(separatedBy: "(")
            let id = parts[0].trimmingCharacters(in: .whitespaces)
            let labelPart = parts.dropFirst().joined(separator: "(")
            let label = labelPart.replacingOccurrences(of: ")", with: "")
            return FlowNode(id: id, label: label, type: .startEnd)
        } else if trimmed.contains("{") && trimmed.contains("}") {
            // 判定ノード B{テキスト}
            let parts = trimmed.components(separatedBy: "{")
            let id = parts[0].trimmingCharacters(in: .whitespaces)
            let labelPart = parts.dropFirst().joined(separator: "{")
            let label = labelPart.replacingOccurrences(of: "}", with: "")
            return FlowNode(id: id, label: label, type: .decision)
        } else if trimmed.contains("((") && trimmed.contains("))") {
            // 円ノード C((テキスト))
            let parts = trimmed.components(separatedBy: "((")
            let id = parts[0].trimmingCharacters(in: .whitespaces)
            let labelPart = parts.dropFirst().joined(separator: "((")
            let label = labelPart.replacingOccurrences(of: "))", with: "")
            return FlowNode(id: id, label: label, type: .circle)
        } else {
            // プレーンなID
            return FlowNode(id: trimmed, label: trimmed, type: .process)
        }
    }
    
    private func calculateFlowchartLayout(nodes: inout [FlowNode], connections: [FlowConnection], direction: FlowDirection) {
        guard !nodes.isEmpty else { return }
        
        // より広いスペーシングでレイアウト
        let baseSpacing: CGFloat = 150
        let branchSpacing: CGFloat = 250
        let startX: CGFloat = 300
        let startY: CGFloat = 80
        
        // 階層構造を構築
        var levels: [[String]] = []
        var visited = Set<String>()
        var nodeToLevel: [String: Int] = [:]
        
        // 開始ノードを見つける（通常は最初のノード）
        let startNodeId = nodes[0].id
        
        // 幅優先探索でレベルを構築
        buildLevels(startNodeId: startNodeId, connections: connections, levels: &levels, visited: &visited, nodeToLevel: &nodeToLevel)
        
        // 各レベルのノードを配置
        for (levelIndex, levelNodes) in levels.enumerated() {
            let y = startY + CGFloat(levelIndex) * baseSpacing
            
            // 分岐ノードの特別処理
            if levelIndex > 0 {
                let parentLevel = levels[levelIndex - 1]
                var branchGroups: [String: [String]] = [:]
                
                // 各ノードの親を特定して分岐グループを作成
                for nodeId in levelNodes {
                    for parentId in parentLevel {
                        if connections.contains(where: { $0.from == parentId && $0.to == nodeId }) {
                            if branchGroups[parentId] == nil {
                                branchGroups[parentId] = []
                            }
                            branchGroups[parentId]?.append(nodeId)
                        }
                    }
                }
                
                // 分岐グループごとに横並び配置
                var currentX = startX
                let _: CGFloat = 300
                
                for (parentId, childIds) in branchGroups.sorted(by: { $0.key < $1.key }) {
                    if let parentIndex = nodes.firstIndex(where: { $0.id == parentId }) {
                        let parentX = nodes[parentIndex].x
                        
                        if childIds.count > 1 {
                            // 複数の子ノード（分岐）の場合、親を中心に横並び配置
                            let totalWidth = CGFloat(childIds.count - 1) * branchSpacing
                            let groupStartX = parentX - totalWidth / 2
                            
                            for (index, childId) in childIds.enumerated() {
                                if let nodeIndex = nodes.firstIndex(where: { $0.id == childId }) {
                                    nodes[nodeIndex].x = groupStartX + CGFloat(index) * branchSpacing
                                    nodes[nodeIndex].y = y
                                }
                            }
                        } else if childIds.count == 1 {
                            // 単一の子ノードの場合、親の下に配置
                            if let childIndex = nodes.firstIndex(where: { $0.id == childIds[0] }) {
                                nodes[childIndex].x = parentX
                                nodes[childIndex].y = y
                            }
                        }
                    }
                }
                
                // 合流ノード（複数の親を持つノード）の処理
                for nodeId in levelNodes {
                    if !branchGroups.values.flatMap({ $0 }).contains(nodeId) {
                        // 複数の親を持つ合流ノードの場合、親の中央に配置
                        let parentIds = connections.filter { $0.to == nodeId }.map { $0.from }
                        if parentIds.count > 1 {
                            let parentXs = parentIds.compactMap { parentId in
                                nodes.first { $0.id == parentId }?.x
                            }
                            if !parentXs.isEmpty {
                                let avgX = parentXs.reduce(0, +) / CGFloat(parentXs.count)
                                if let nodeIndex = nodes.firstIndex(where: { $0.id == nodeId }) {
                                    nodes[nodeIndex].x = avgX
                                    nodes[nodeIndex].y = y
                                }
                            }
                        } else {
                            // 通常の孤立ノード
                            if let nodeIndex = nodes.firstIndex(where: { $0.id == nodeId }) {
                                nodes[nodeIndex].x = currentX
                                nodes[nodeIndex].y = y
                                currentX += branchSpacing
                            }
                        }
                    }
                }
            } else {
                // 最初のレベル（開始ノード）
                for (index, nodeId) in levelNodes.enumerated() {
                    if let nodeIndex = nodes.firstIndex(where: { $0.id == nodeId }) {
                        nodes[nodeIndex].x = startX + CGFloat(index) * branchSpacing
                        nodes[nodeIndex].y = y
                    }
                }
            }
        }
    }
    
    private func buildLevels(startNodeId: String, connections: [FlowConnection], levels: inout [[String]], visited: inout Set<String>, nodeToLevel: inout [String: Int]) {
        var queue: [(String, Int)] = [(startNodeId, 0)]
        visited.insert(startNodeId)
        
        // ノードの入次数を計算（複数の親を持つノードを特定）
        var inDegree: [String: Int] = [:]
        var outgoingConnections: [String: [String]] = [:]
        
        for connection in connections {
            inDegree[connection.to, default: 0] += 1
            outgoingConnections[connection.from, default: []].append(connection.to)
        }
        
        while !queue.isEmpty {
            let (currentNodeId, level) = queue.removeFirst()
            
            // 既に配置されているノードの場合、より深いレベルに移動
            if let existingLevel = nodeToLevel[currentNodeId] {
                if level > existingLevel {
                    // 古いレベルから削除
                    if let index = levels[existingLevel].firstIndex(of: currentNodeId) {
                        levels[existingLevel].remove(at: index)
                    }
                    
                    // 新しいレベルに配置
                    while levels.count <= level {
                        levels.append([])
                    }
                    levels[level].append(currentNodeId)
                    nodeToLevel[currentNodeId] = level
                }
                continue
            }
            
            // レベル配列を拡張
            while levels.count <= level {
                levels.append([])
            }
            
            levels[level].append(currentNodeId)
            nodeToLevel[currentNodeId] = level
            
            // 子ノードを追加
            for childId in outgoingConnections[currentNodeId] ?? [] {
                let childLevel = level + 1
                
                // 合流ノード（複数の親を持つ）の場合、全ての親が処理されるまで待つ
                if inDegree[childId, default: 0] > 1 {
                    let processedParents = connections.filter { $0.to == childId }.reduce(0) { count, conn in
                        return nodeToLevel[conn.from] != nil ? count + 1 : count
                    }
                    
                    // 全ての親が処理された場合のみ追加
                    if processedParents == inDegree[childId] && !visited.contains(childId) {
                        queue.append((childId, childLevel))
                        visited.insert(childId)
                    }
                } else if !visited.contains(childId) {
                    queue.append((childId, childLevel))
                    visited.insert(childId)
                }
            }
        }
    }
    
    private func findChildNodes(for parentId: String, connections: [FlowConnection]) -> [String] {
        // connections配列を参照して子ノードを見つける
        var childNodes: [String] = []
        for connection in connections {
            if connection.from == parentId {
                childNodes.append(connection.to)
            }
        }
        return childNodes
    }
    
    private func calculateBounds(for nodes: [FlowNode]) -> (minX: CGFloat, minY: CGFloat, maxX: CGFloat, maxY: CGFloat) {
        guard !nodes.isEmpty else {
            return (minX: 0, minY: 0, maxX: 400, maxY: 300)
        }
        
        // ノードタイプに応じたサイズを考慮
        func getNodeSize(for node: FlowNode) -> (width: CGFloat, height: CGFloat) {
            switch node.type {
            case .decision:
                return (width: 80, height: 80) // ダイヤモンド
            case .circle:
                return (width: 80, height: 80) // 円
            case .startEnd:
                return (width: 140, height: 60) // 楕円
            case .subroutine:
                return (width: 140, height: 60) // サブルーチン
            case .database:
                return (width: 140, height: 70) // データベース
            case .process:
                return (width: 140, height: 60) // 矩形
            }
        }
        
        var minX = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude
        
        for node in nodes {
            let size = getNodeSize(for: node)
            let left = node.x - size.width/2
            let right = node.x + size.width/2
            let top = node.y - size.height/2
            let bottom = node.y + size.height/2
            
            minX = min(minX, left)
            maxX = max(maxX, right)
            minY = min(minY, top)
            maxY = max(maxY, bottom)
        }
        
        return (minX: minX, minY: minY, maxX: maxX, maxY: maxY)
    }
    
    private func calculateClassBoxSize(_ classInfo: ClassInfo) -> (width: CGFloat, height: CGFloat) {
        // クラス名の幅を基準に
        let classNameWidth = max(120, CGFloat(classInfo.name.count * 8 + 20))
        
        // 属性とメソッドの最長幅を計算
        let maxAttributeWidth = classInfo.attributes.map { CGFloat($0.count * 7 + 10) }.max() ?? 0
        let maxMethodWidth = classInfo.methods.map { CGFloat($0.count * 7 + 10) }.max() ?? 0
        
        let width = max(classNameWidth, max(maxAttributeWidth, maxMethodWidth))
        
        // 高さは項目数に基づいて計算
        let baseHeight: CGFloat = 40 // クラス名部分
        let attributeHeight = CGFloat(classInfo.attributes.count * 18)
        let methodHeight = CGFloat(classInfo.methods.count * 18)
        let height = baseHeight + attributeHeight + methodHeight + 20 // 余白
        
        return (width: width, height: height)
    }
    
    private func drawFlowchartNode(node: FlowNode) -> String {
        let nodeWidth: CGFloat = 120
        let nodeHeight: CGFloat = 50
        
        switch node.type {
        case .process:
            // 矩形ノード
            return """
            <rect x="\(node.x - nodeWidth/2)" y="\(node.y - nodeHeight/2)" width="\(nodeWidth)" height="\(nodeHeight)" fill="#e3f2fd" stroke="#1976d2" stroke-width="2" rx="5"/>
            <text x="\(node.x)" y="\(node.y + 5)" text-anchor="middle" font-family="Arial, sans-serif" font-size="12" font-weight="bold" fill="#1976d2">\(node.label)</text>
            """
        case .startEnd:
            // 楕円ノード
            let rx: CGFloat = nodeWidth/2
            let ry: CGFloat = nodeHeight/2
            return """
            <ellipse cx="\(node.x)" cy="\(node.y)" rx="\(rx)" ry="\(ry)" fill="#e8f5e8" stroke="#4caf50" stroke-width="2"/>
            <text x="\(node.x)" y="\(node.y + 5)" text-anchor="middle" font-family="Arial, sans-serif" font-size="12" font-weight="bold" fill="#4caf50">\(node.label)</text>
            """
        case .decision:
            // ダイヤモンド型ノード
            let diamondSize: CGFloat = 60
            return """
            <polygon points="\(node.x),\(node.y - diamondSize/2) \(node.x + diamondSize/2),\(node.y) \(node.x),\(node.y + diamondSize/2) \(node.x - diamondSize/2),\(node.y)" fill="#fff3e0" stroke="#f57c00" stroke-width="2"/>
            <text x="\(node.x)" y="\(node.y + 5)" text-anchor="middle" font-family="Arial, sans-serif" font-size="11" font-weight="bold" fill="#f57c00">\(node.label)</text>
            """
        case .subroutine:
            // サブルーチンノード（二重枠の矩形）
            return """
            <rect x="\(node.x - nodeWidth/2)" y="\(node.y - nodeHeight/2)" width="\(nodeWidth)" height="\(nodeHeight)" fill="#f3e5f5" stroke="#7b1fa2" stroke-width="2" rx="5"/>
            <rect x="\(node.x - nodeWidth/2 + 5)" y="\(node.y - nodeHeight/2 + 5)" width="\(nodeWidth - 10)" height="\(nodeHeight - 10)" fill="none" stroke="#7b1fa2" stroke-width="1" rx="3"/>
            <text x="\(node.x)" y="\(node.y + 5)" text-anchor="middle" font-family="Arial, sans-serif" font-size="11" font-weight="bold" fill="#7b1fa2">\(node.label)</text>
            """
        case .database:
            // データベースノード
            let dbWidth: CGFloat = nodeWidth
            let dbHeight: CGFloat = nodeHeight
            let ellipseRy: CGFloat = 10
            return """
            <ellipse cx="\(node.x)" cy="\(node.y - dbHeight/2 + ellipseRy)" rx="\(dbWidth/2)" ry="\(ellipseRy)" fill="#fff8e1" stroke="#ff8f00"/>
            <rect x="\(node.x - dbWidth/2)" y="\(node.y - dbHeight/2 + ellipseRy)" width="\(dbWidth)" height="\(dbHeight - ellipseRy)" fill="#fff8e1" stroke="#ff8f00" stroke-width="2"/>
            <ellipse cx="\(node.x)" cy="\(node.y + dbHeight/2)" rx="\(dbWidth/2)" ry="\(ellipseRy)" fill="#fff8e1" stroke="#ff8f00"/>
            <text x="\(node.x)" y="\(node.y + 5)" text-anchor="middle" font-family="Arial, sans-serif" font-size="11" font-weight="bold" fill="#ff8f00">\(node.label)</text>
            """
        case .circle:
            // 円ノード
            let radius: CGFloat = 30
            return """
            <circle cx="\(node.x)" cy="\(node.y)" r="\(radius)" fill="#fce4ec" stroke="#c2185b" stroke-width="2"/>
            <text x="\(node.x)" y="\(node.y + 5)" text-anchor="middle" font-family="Arial, sans-serif" font-size="11" font-weight="bold" fill="#c2185b">\(node.label)</text>
            """
        }
    }
    
    private func drawFlowchartConnection(from: FlowNode, to: FlowNode, connection: FlowConnection) -> String {
        let arrowSize: CGFloat = 8
        
        var startX = from.x
        var startY = from.y
        var endX = to.x
        var endY = to.y
        
        // ノードタイプに応じた境界距離を計算（実際の描画サイズに合わせる）
        func getNodeBoundaryDistance(for node: FlowNode, dx: CGFloat, dy: CGFloat) -> CGFloat {
            switch node.type {
            case .decision:
                // ダイヤモンド型: diamondSize = 60, 対角線の半分 + 余裕
                return 35 // 60/2 + 5の余裕
            case .circle:
                // 円型: radius = 30 + 余裕
                return 35 // 30 + 5の余裕
            default:
                // 矩形: nodeWidth=120, nodeHeight=50
                let angle = abs(atan2(abs(dy), abs(dx)))
                if angle < .pi / 4 {
                    return 65 // 120/2 + 5の余裕
                } else {
                    return 30 // 50/2 + 5の余裕
                }
            }
        }
        
        // 接続方向を判断してノードの境界から線を開始/終了
        let dx = endX - startX
        let dy = endY - startY
        let distance = sqrt(dx * dx + dy * dy)
        
        if distance > 0 {
            // 正規化された方向ベクトル
            let unitX = dx / distance
            let unitY = dy / distance
            
            // 開始ノードの境界距離
            let startBoundary = getNodeBoundaryDistance(for: from, dx: dx, dy: dy)
            startX += unitX * startBoundary
            startY += unitY * startBoundary
            
            // 終了ノードの境界距離
            let endBoundary = getNodeBoundaryDistance(for: to, dx: -dx, dy: -dy)
            endX -= unitX * endBoundary
            endY -= unitY * endBoundary
        }
        
        // 線の描画（矢印の基点まで）
        let lineEndX = endX - (distance > 0 ? (endX - startX) / distance * arrowSize : 0)
        let lineEndY = endY - (distance > 0 ? (endY - startY) / distance * arrowSize : 0)
        
        // スタイルに応じた線の属性
        var strokeWidth = "2"
        var strokeDasharray = ""
        
        switch connection.style {
        case .solid:
            strokeWidth = "2"
        case .thick:
            strokeWidth = "4"
        case .dotted:
            strokeWidth = "2"
            strokeDasharray = "stroke-dasharray=\"5,5\""
        case .circle, .cross:
            strokeWidth = "2"
        }
        
        var svg = """
        <line x1="\(startX)" y1="\(startY)" x2="\(lineEndX)" y2="\(lineEndY)" stroke="#333" stroke-width="\(strokeWidth)" \(strokeDasharray)/>
        """
        
        // 矢印の向きを計算
        if distance > 0 {
            let unitX = dx / distance
            let unitY = dy / distance
            
            // 矢印先端の位置（線の終端に正確に配置）
            let arrowTipX = endX
            let arrowTipY = endY
            
            // 矢印の両翼の位置
            let perpX = -unitY * arrowSize / 2
            let perpY = unitX * arrowSize / 2
            
            // 矢印の基点を線の終端から少し後ろに配置
            let arrowBaseX = endX - unitX * arrowSize
            let arrowBaseY = endY - unitY * arrowSize
            
            // スタイルに応じた矢印終端
            switch connection.style {
            case .circle:
                svg += """
                <circle cx="\(arrowTipX)" cy="\(arrowTipY)" r="4" fill="white" stroke="#333" stroke-width="2"/>
                """
            case .cross:
                svg += """
                <g transform="translate(\(arrowTipX), \(arrowTipY))">
                <line x1="-4" y1="-4" x2="4" y2="4" stroke="#333" stroke-width="2"/>
                <line x1="-4" y1="4" x2="4" y2="-4" stroke="#333" stroke-width="2"/>
                </g>
                """
            default:
                svg += """
                <polygon points="\(arrowTipX),\(arrowTipY) \(arrowBaseX + perpX),\(arrowBaseY + perpY) \(arrowBaseX - perpX),\(arrowBaseY - perpY)" fill="#333" stroke="#333" stroke-width="1"/>
                """
            }
        }
        
        // ラベルがある場合は表示
        if !connection.label.isEmpty {
            let labelX = (startX + endX) / 2
            let labelY = (startY + endY) / 2
            svg += """
            <text x="\(labelX)" y="\(labelY - 5)" text-anchor="middle" font-family="Arial, sans-serif" font-size="10" font-weight="bold" fill="#666" stroke="white" stroke-width="3" paint-order="stroke">\(connection.label)</text>
            <text x="\(labelX)" y="\(labelY - 5)" text-anchor="middle" font-family="Arial, sans-serif" font-size="10" font-weight="bold" fill="#666">\(connection.label)</text>
            """
        }
        
        return svg
    }
    
    private func generatePieChartSVG(code: String) -> String {
        return """
        <svg width="200" height="200" xmlns="http://www.w3.org/2000/svg">
        <circle cx="100" cy="100" r="80" fill="#2196f3"/>
        <path d="M 100 100 L 180 100 A 80 80 0 0 1 140 180 Z" fill="#4caf50"/>
        <path d="M 100 100 L 140 180 A 80 80 0 0 1 60 180 Z" fill="#ff9800"/>
        <path d="M 100 100 L 60 180 A 80 80 0 0 1 20 100 Z" fill="#f44336"/>
        <text x="100" y="50" text-anchor="middle" font-family="Arial" font-size="14" font-weight="bold" fill="#333">円グラフ</text>
        </svg>
        """
    }
    
    private func convertSVGToImage(svgContent: String) -> Result<UIImage, Error> {
        // Core Graphicsで直接描画する方式に変更
        return .success(createDiagramImage(svgContent: svgContent))
    }
    
    private func createDiagramImage(svgContent: String) -> UIImage {
        // SVGの内容から図の種類とサイズを推測
        let size = extractSizeFromSVG(svgContent) ?? CGSize(width: 400, height: 300)
        
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let cgContext = context.cgContext
            
            // 背景を白にする
            UIColor.white.setFill()
            cgContext.fill(CGRect(origin: .zero, size: size))
            
            // SVGの簡易的な解析と描画
            renderSVGElements(svgContent: svgContent, context: cgContext, size: size)
        }
    }
    
    private func extractSizeFromSVG(_ svgContent: String) -> CGSize? {
        // SVGのwidth, height属性を抽出
        let widthPattern = #"width="(\d+)""#
        let heightPattern = #"height="(\d+)""#
        
        let widthRegex = try? NSRegularExpression(pattern: widthPattern)
        let heightRegex = try? NSRegularExpression(pattern: heightPattern)
        
        let range = NSRange(location: 0, length: svgContent.count)
        
        var width: CGFloat = 400
        var height: CGFloat = 300
        
        if let widthMatch = widthRegex?.firstMatch(in: svgContent, range: range),
           let widthRange = Range(widthMatch.range(at: 1), in: svgContent),
           let widthValue = Double(String(svgContent[widthRange])) {
            width = CGFloat(widthValue)
        }
        
        if let heightMatch = heightRegex?.firstMatch(in: svgContent, range: range),
           let heightRange = Range(heightMatch.range(at: 1), in: svgContent),
           let heightValue = Double(String(svgContent[heightRange])) {
            height = CGFloat(heightValue)
        }
        
        return CGSize(width: width, height: height)
    }
    
    private func renderSVGElements(svgContent: String, context: CGContext, size: CGSize) {
        // 矩形の描画
        renderRectangles(svgContent: svgContent, context: context)
        
        // 線の描画
        renderLines(svgContent: svgContent, context: context)
        
        // テキストの描画
        renderTexts(svgContent: svgContent, context: context)
        
        // 円の描画
        renderCircles(svgContent: svgContent, context: context)
        
        // パスの描画
        renderPaths(svgContent: svgContent, context: context)
    }
    
    private func renderRectangles(svgContent: String, context: CGContext) {
        let rectPattern = #"<rect\s+([^>]+)>"#
        guard let regex = try? NSRegularExpression(pattern: rectPattern) else { return }
        
        let matches = regex.matches(in: svgContent, range: NSRange(location: 0, length: svgContent.count))
        
        for match in matches {
            if let range = Range(match.range(at: 1), in: svgContent) {
                let attributes = String(svgContent[range])
                let rect = parseRectAttributes(attributes)
                
                context.setFillColor(rect.fillColor.cgColor)
                context.setStrokeColor(rect.strokeColor.cgColor)
                context.setLineWidth(rect.strokeWidth)
                
                let cgRect = CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
                
                if rect.rx > 0 {
                    // 角丸矩形の場合
                    let path = UIBezierPath(roundedRect: cgRect, cornerRadius: rect.rx)
                    context.addPath(path.cgPath)
                    
                    if rect.fillColor != UIColor.clear {
                        context.fillPath()
                        context.addPath(path.cgPath) // 再度パスを追加（fillPathで消費されるため）
                    }
                    if rect.strokeColor != UIColor.clear {
                        context.strokePath()
                    }
                } else {
                    // 通常の矩形の場合
                    if rect.fillColor != UIColor.clear {
                        context.fill(cgRect)
                    }
                    if rect.strokeColor != UIColor.clear {
                        context.stroke(cgRect)
                    }
                }
            }
        }
    }
    
    private func renderLines(svgContent: String, context: CGContext) {
        let linePattern = #"<line\s+([^>]+)>"#
        guard let regex = try? NSRegularExpression(pattern: linePattern) else { return }
        
        let matches = regex.matches(in: svgContent, range: NSRange(location: 0, length: svgContent.count))
        
        for match in matches {
            if let range = Range(match.range(at: 1), in: svgContent) {
                let attributes = String(svgContent[range])
                let line = parseLineAttributes(attributes)
                
                context.setStrokeColor(line.strokeColor.cgColor)
                context.setLineWidth(line.strokeWidth)
                
                if line.isDashed {
                    context.setLineDash(phase: 0, lengths: [5, 5])
                }
                
                context.move(to: CGPoint(x: line.x1, y: line.y1))
                context.addLine(to: CGPoint(x: line.x2, y: line.y2))
                context.strokePath()
                
                context.setLineDash(phase: 0, lengths: [])
            }
        }
    }
    
    private func renderTexts(svgContent: String, context: CGContext) {
        let textPattern = #"<text\s+([^>]+)>([^<]+)</text>"#
        guard let regex = try? NSRegularExpression(pattern: textPattern) else { return }
        
        let matches = regex.matches(in: svgContent, range: NSRange(location: 0, length: svgContent.count))
        
        for match in matches {
            if let attrRange = Range(match.range(at: 1), in: svgContent),
               let textRange = Range(match.range(at: 2), in: svgContent) {
                let attributes = String(svgContent[attrRange])
                let text = String(svgContent[textRange])
                
                let textInfo = parseTextAttributes(attributes, text: text)
                
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: textInfo.font,
                    .foregroundColor: textInfo.color
                ]
                
                let attributedString = NSAttributedString(string: textInfo.text, attributes: attrs)
                let textSize = attributedString.size()
                
                var drawPoint = CGPoint(x: textInfo.x, y: textInfo.y)
                
                // text-anchor の処理（水平方向の位置調整）
                switch textInfo.textAnchor {
                case "middle":
                    drawPoint.x -= textSize.width / 2
                case "end":
                    drawPoint.x -= textSize.width
                default: // "start"
                    break
                }
                
                // 垂直方向の位置調整
                let font = textInfo.font
                let ascender = font.ascender
                let descender = font.descender
                let fontHeight = ascender - descender
                
                // dominant-baselineに基づく垂直位置調整
                switch textInfo.dominantBaseline {
                case "middle", "central":
                    // 中央揃え
                    drawPoint.y -= fontHeight / 2
                case "hanging":
                    // 上端揃え（そのまま）
                    break
                case "text-bottom":
                    // 下端揃え
                    drawPoint.y -= fontHeight
                default: // "auto", "alphabetic", "baseline"
                    // SVGのベースライン基準からCore Graphicsの上端基準に変換
                    drawPoint.y -= ascender
                }
                
                attributedString.draw(at: drawPoint)
            }
        }
    }
    
    private func renderCircles(svgContent: String, context: CGContext) {
        let circlePattern = #"<circle\s+([^>]+)>"#
        guard let regex = try? NSRegularExpression(pattern: circlePattern) else { return }
        
        let matches = regex.matches(in: svgContent, range: NSRange(location: 0, length: svgContent.count))
        
        for match in matches {
            if let range = Range(match.range(at: 1), in: svgContent) {
                let attributes = String(svgContent[range])
                let circle = parseCircleAttributes(attributes)
                
                context.setFillColor(circle.fillColor.cgColor)
                context.setStrokeColor(circle.strokeColor.cgColor)
                context.setLineWidth(circle.strokeWidth)
                
                let rect = CGRect(x: circle.cx - circle.r, y: circle.cy - circle.r, 
                                width: circle.r * 2, height: circle.r * 2)
                context.fillEllipse(in: rect)
                context.strokeEllipse(in: rect)
            }
        }
    }
    
    private func renderPaths(svgContent: String, context: CGContext) {
        let pathPattern = #"<path\s+([^>]+)>"#
        guard let regex = try? NSRegularExpression(pattern: pathPattern) else { return }
        
        let matches = regex.matches(in: svgContent, range: NSRange(location: 0, length: svgContent.count))
        
        for match in matches {
            if let range = Range(match.range(at: 1), in: svgContent) {
                let attributes = String(svgContent[range])
                let path = parsePathAttributes(attributes)
                
                context.setFillColor(path.fillColor.cgColor)
                context.setStrokeColor(path.strokeColor.cgColor)
                context.setLineWidth(path.strokeWidth)
                
                // 簡単なパス描画（完全なSVGパス解析は複雑なので簡略化）
                if let cgPath = createCGPath(from: path.d) {
                    context.addPath(cgPath)
                    context.fillPath()
                }
            }
        }
        
        // ポリゴン（矢印など）の描画
        renderPolygons(svgContent: svgContent, context: context)
    }
    
    private func renderPolygons(svgContent: String, context: CGContext) {
        let polygonPattern = #"<polygon\s+([^>]+)>"#
        guard let regex = try? NSRegularExpression(pattern: polygonPattern) else { return }
        
        let matches = regex.matches(in: svgContent, range: NSRange(location: 0, length: svgContent.count))
        
        for match in matches {
            if let range = Range(match.range(at: 1), in: svgContent) {
                let attributes = String(svgContent[range])
                let polygon = parsePolygonAttributes(attributes)
                
                context.setFillColor(polygon.fillColor.cgColor)
                context.setStrokeColor(polygon.strokeColor.cgColor)
                context.setLineWidth(polygon.strokeWidth)
                
                // ポリゴンの描画
                if let points = parsePolygonPoints(polygon.points) {
                    drawPolygon(points: points, context: context, fill: polygon.fillColor != UIColor.clear, stroke: polygon.strokeColor != UIColor.clear)
                }
            }
        }
    }
    
    private func parsePolygonAttributes(_ attributes: String) -> SVGPolygon {
        var polygon = SVGPolygon()
        
        let patterns = [
            ("points", #"points="([^"]+)""#),
            ("fill", #"fill="([^"]+)""#),
            ("stroke", #"stroke="([^"]+)""#),
            ("stroke-width", #"stroke-width="([^"]+)""#)
        ]
        
        for (key, pattern) in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: attributes, range: NSRange(location: 0, length: attributes.count)),
               let range = Range(match.range(at: 1), in: attributes) {
                let value = String(attributes[range])
                
                switch key {
                case "points": polygon.points = value
                case "fill": polygon.fillColor = parseColor(value)
                case "stroke": polygon.strokeColor = parseColor(value)
                case "stroke-width": polygon.strokeWidth = CGFloat(Double(value) ?? 1)
                default: break
                }
            }
        }
        
        return polygon
    }
    
    private func parsePolygonPoints(_ pointsString: String) -> [CGPoint]? {
        // "x1,y1 x2,y2 x3,y3" 形式の解析
        let pairs = pointsString.components(separatedBy: " ")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        var points: [CGPoint] = []
        
        for pair in pairs {
            let coordinates = pair.components(separatedBy: ",")
            if coordinates.count >= 2,
               let x = Double(coordinates[0].trimmingCharacters(in: .whitespaces)),
               let y = Double(coordinates[1].trimmingCharacters(in: .whitespaces)) {
                points.append(CGPoint(x: x, y: y))
            }
        }
        
        return points.isEmpty ? nil : points
    }
    
    private func drawPolygon(points: [CGPoint], context: CGContext, fill: Bool, stroke: Bool) {
        guard !points.isEmpty else { return }
        
        // ポリゴンのパスを作成
        context.beginPath()
        context.move(to: points[0])
        
        for i in 1..<points.count {
            context.addLine(to: points[i])
        }
        
        context.closePath()
        
        // 描画モードを設定
        if fill && stroke {
            context.drawPath(using: .fillStroke)
        } else if fill {
            context.drawPath(using: .fill)
        } else if stroke {
            context.drawPath(using: .stroke)
        }
    }
    
    private func createPlaceholderImage(with text: String) -> UIImage {
        let size = CGSize(width: 300, height: 200)
        let renderer = UIGraphicsImageRenderer(size: size)
        
        return renderer.image { context in
            // 背景
            UIColor.systemGray6.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            
            // 枠線
            UIColor.systemGray3.setStroke()
            context.stroke(CGRect(origin: .zero, size: size))
            
            // テキスト
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12),
                .foregroundColor: UIColor.label
            ]
            
            let attributedString = NSAttributedString(string: text, attributes: attributes)
            let textSize = attributedString.size()
            let textRect = CGRect(
                x: (size.width - textSize.width) / 2,
                y: (size.height - textSize.height) / 2,
                width: textSize.width,
                height: textSize.height
            )
            
            attributedString.draw(in: textRect)
        }
    }
    
    // MARK: - SVG属性解析用のヘルパーメソッド
    private func parseRectAttributes(_ attributes: String) -> SVGRect {
        var rect = SVGRect()
        
        let patterns = [
            ("x", #"x="([^"]+)""#),
            ("y", #"y="([^"]+)""#),
            ("width", #"width="([^"]+)""#),
            ("height", #"height="([^"]+)""#),
            ("fill", #"fill="([^"]+)""#),
            ("stroke", #"stroke="([^"]+)""#),
            ("stroke-width", #"stroke-width="([^"]+)""#),
            ("rx", #"rx="([^"]+)""#)
        ]
        
        for (key, pattern) in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: attributes, range: NSRange(location: 0, length: attributes.count)),
               let range = Range(match.range(at: 1), in: attributes) {
                let value = String(attributes[range])
                
                switch key {
                case "x": rect.x = CGFloat(Double(value) ?? 0)
                case "y": rect.y = CGFloat(Double(value) ?? 0)
                case "width": rect.width = CGFloat(Double(value) ?? 0)
                case "height": rect.height = CGFloat(Double(value) ?? 0)
                case "fill": rect.fillColor = parseColor(value)
                case "stroke": rect.strokeColor = parseColor(value)
                case "stroke-width": rect.strokeWidth = CGFloat(Double(value) ?? 1)
                case "rx": rect.rx = CGFloat(Double(value) ?? 0)
                default: break
                }
            }
        }
        
        return rect
    }
    
    private func parseLineAttributes(_ attributes: String) -> SVGLine {
        var line = SVGLine()
        
        let patterns = [
            ("x1", #"x1="([^"]+)""#),
            ("y1", #"y1="([^"]+)""#),
            ("x2", #"x2="([^"]+)""#),
            ("y2", #"y2="([^"]+)""#),
            ("stroke", #"stroke="([^"]+)""#),
            ("stroke-width", #"stroke-width="([^"]+)""#),
            ("stroke-dasharray", #"stroke-dasharray="([^"]+)""#)
        ]
        
        for (key, pattern) in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: attributes, range: NSRange(location: 0, length: attributes.count)),
               let range = Range(match.range(at: 1), in: attributes) {
                let value = String(attributes[range])
                
                switch key {
                case "x1": line.x1 = CGFloat(Double(value) ?? 0)
                case "y1": line.y1 = CGFloat(Double(value) ?? 0)
                case "x2": line.x2 = CGFloat(Double(value) ?? 0)
                case "y2": line.y2 = CGFloat(Double(value) ?? 0)
                case "stroke": line.strokeColor = parseColor(value)
                case "stroke-width": line.strokeWidth = CGFloat(Double(value) ?? 1)
                case "stroke-dasharray": line.isDashed = !value.isEmpty
                default: break
                }
            }
        }
        
        return line
    }
    
    private func parseTextAttributes(_ attributes: String, text: String) -> SVGText {
        var textInfo = SVGText()
        textInfo.text = text
        
        let patterns = [
            ("x", #"x="([^"]+)""#),
            ("y", #"y="([^"]+)""#),
            ("font-size", #"font-size="([^"]+)""#),
            ("font-family", #"font-family="([^"]+)""#),
            ("font-weight", #"font-weight="([^"]+)""#),
            ("fill", #"fill="([^"]+)""#),
            ("text-anchor", #"text-anchor="([^"]+)""#),
            ("dominant-baseline", #"dominant-baseline="([^"]+)""#),
            ("alignment-baseline", #"alignment-baseline="([^"]+)""#)
        ]
        
        for (key, pattern) in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: attributes, range: NSRange(location: 0, length: attributes.count)),
               let range = Range(match.range(at: 1), in: attributes) {
                let value = String(attributes[range])
                
                switch key {
                case "x": textInfo.x = CGFloat(Double(value) ?? 0)
                case "y": textInfo.y = CGFloat(Double(value) ?? 0)
                case "font-size": 
                    let fontSize = CGFloat(Double(value) ?? 12)
                    textInfo.font = UIFont.systemFont(ofSize: fontSize)
                case "font-weight":
                    if value == "bold" {
                        textInfo.font = UIFont.boldSystemFont(ofSize: textInfo.font.pointSize)
                    }
                case "fill": textInfo.color = parseColor(value)
                case "text-anchor": textInfo.textAnchor = value
                case "dominant-baseline": textInfo.dominantBaseline = value
                case "alignment-baseline": textInfo.alignmentBaseline = value
                default: break
                }
            }
        }
        
        return textInfo
    }
    
    private func parseCircleAttributes(_ attributes: String) -> SVGCircle {
        var circle = SVGCircle()
        
        let patterns = [
            ("cx", #"cx="([^"]+)""#),
            ("cy", #"cy="([^"]+)""#),
            ("r", #"r="([^"]+)""#),
            ("fill", #"fill="([^"]+)""#),
            ("stroke", #"stroke="([^"]+)""#),
            ("stroke-width", #"stroke-width="([^"]+)""#)
        ]
        
        for (key, pattern) in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: attributes, range: NSRange(location: 0, length: attributes.count)),
               let range = Range(match.range(at: 1), in: attributes) {
                let value = String(attributes[range])
                
                switch key {
                case "cx": circle.cx = CGFloat(Double(value) ?? 0)
                case "cy": circle.cy = CGFloat(Double(value) ?? 0)
                case "r": circle.r = CGFloat(Double(value) ?? 0)
                case "fill": circle.fillColor = parseColor(value)
                case "stroke": circle.strokeColor = parseColor(value)
                case "stroke-width": circle.strokeWidth = CGFloat(Double(value) ?? 1)
                default: break
                }
            }
        }
        
        return circle
    }
    
    private func parsePathAttributes(_ attributes: String) -> SVGPath {
        var path = SVGPath()
        
        let patterns = [
            ("d", #"d="([^"]+)""#),
            ("fill", #"fill="([^"]+)""#),
            ("stroke", #"stroke="([^"]+)""#),
            ("stroke-width", #"stroke-width="([^"]+)""#)
        ]
        
        for (key, pattern) in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: attributes, range: NSRange(location: 0, length: attributes.count)),
               let range = Range(match.range(at: 1), in: attributes) {
                let value = String(attributes[range])
                
                switch key {
                case "d": path.d = value
                case "fill": path.fillColor = parseColor(value)
                case "stroke": path.strokeColor = parseColor(value)
                case "stroke-width": path.strokeWidth = CGFloat(Double(value) ?? 1)
                default: break
                }
            }
        }
        
        return path
    }
    
    private func parseColor(_ colorString: String) -> UIColor {
        let cleanColor = colorString.trimmingCharacters(in: .whitespaces)
        
        // 名前付き色
        switch cleanColor.lowercased() {
        case "#333", "#333333": return UIColor.darkGray
        case "#ccc", "#cccccc": return UIColor.lightGray
        case "#ddd", "#dddddd": return UIColor.systemGray4
        case "#e1f5fe": return UIColor.systemBlue.withAlphaComponent(0.1)
        case "#0277bd": return UIColor.systemBlue
        case "#fff3e0": return UIColor.systemOrange.withAlphaComponent(0.1)
        case "#f57c00": return UIColor.systemOrange
        case "#4caf50": return UIColor.systemGreen
        case "#2196f3": return UIColor.systemBlue
        case "#ff9800": return UIColor.systemOrange
        case "#f44336": return UIColor.systemRed
        case "#e3f2fd": return UIColor.systemBlue.withAlphaComponent(0.1)
        case "#1976d2": return UIColor.systemBlue
        case "#e8f5e8": return UIColor.systemGreen.withAlphaComponent(0.1)
        case "#f1f8e9": return UIColor.systemGreen.withAlphaComponent(0.05)
        case "#c8e6c9": return UIColor.systemGreen.withAlphaComponent(0.2)
        case "#689f38": return UIColor.systemGreen.withAlphaComponent(0.7)
        case "#1b5e20": return UIColor.systemGreen.withAlphaComponent(0.9)
        case "white": return UIColor.white
        case "black": return UIColor.black
        default: return UIColor.black
        }
    }
    
    private func createCGPath(from pathString: String) -> CGPath? {
        // 簡単なパス解析（完全なSVGパス解析は複雑）
        let path = CGMutablePath()
        
        // "M x y L x y Z" のような簡単なパスのみ対応
        let components = pathString.components(separatedBy: " ")
        var i = 0
        
        while i < components.count {
            let command = components[i]
            
            switch command {
            case "M": // MoveTo
                if i + 2 < components.count,
                   let x = Double(components[i + 1]),
                   let y = Double(components[i + 2]) {
                    path.move(to: CGPoint(x: x, y: y))
                    i += 3
                } else {
                    i += 1
                }
            case "L": // LineTo
                if i + 2 < components.count,
                   let x = Double(components[i + 1]),
                   let y = Double(components[i + 2]) {
                    path.addLine(to: CGPoint(x: x, y: y))
                    i += 3
                } else {
                    i += 1
                }
            case "Z": // ClosePath
                path.closeSubpath()
                i += 1
            default:
                i += 1
            }
        }
        
        return path
    }
}

// MARK: - SVG要素の構造体
struct SVGRect {
    var x: CGFloat = 0
    var y: CGFloat = 0
    var width: CGFloat = 0
    var height: CGFloat = 0
    var fillColor: UIColor = UIColor.clear
    var strokeColor: UIColor = UIColor.black
    var strokeWidth: CGFloat = 1
    var rx: CGFloat = 0
}

struct SVGLine {
    var x1: CGFloat = 0
    var y1: CGFloat = 0
    var x2: CGFloat = 0
    var y2: CGFloat = 0
    var strokeColor: UIColor = UIColor.black
    var strokeWidth: CGFloat = 1
    var isDashed: Bool = false
}

struct SVGText {
    var x: CGFloat = 0
    var y: CGFloat = 0
    var text: String = ""
    var font: UIFont = UIFont.systemFont(ofSize: 12)
    var color: UIColor = UIColor.black
    var textAnchor: String = "start"
    var dominantBaseline: String = "auto"
    var alignmentBaseline: String = "auto"
}

struct SVGCircle {
    var cx: CGFloat = 0
    var cy: CGFloat = 0
    var r: CGFloat = 0
    var fillColor: UIColor = UIColor.clear
    var strokeColor: UIColor = UIColor.black
    var strokeWidth: CGFloat = 1
}

struct SVGPath {
    var d: String = ""
    var fillColor: UIColor = UIColor.clear
    var strokeColor: UIColor = UIColor.black
    var strokeWidth: CGFloat = 1
}

struct SVGPolygon {
    var points: String = ""
    var fillColor: UIColor = UIColor.clear
    var strokeColor: UIColor = UIColor.black
    var strokeWidth: CGFloat = 1
}

// MARK: - クラス図用の構造体
struct ClassInfo {
    let name: String
    let attributes: [String]
    let methods: [String]
}

struct ClassRelationship {
    let from: String
    let to: String
    let type: String // association, inheritance, implementation, composition, aggregation
}

enum MermaidDiagramType {
    case sequence
    case classDiagram
    case gantt
    case flowchart
    case pie
}

enum MermaidError: LocalizedError {
    case invalidSVG
    case renderingFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidSVG:
            return "無効なSVGデータです"
        case .renderingFailed:
            return "レンダリングに失敗しました"
        }
    }
}

// MARK: - Custom Activity Item Source

/// テキストファイル用のアクティビティアイテムソース
class TextFileActivityItemSource: NSObject, UIActivityItemSource {
    private let memo: Memo
    
    init(memo: Memo) {
        self.memo = memo
        super.init()
    }
    
    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        return memo.content
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        // ファイル関連のアクティビティの場合はtxtファイルを提供
        if let activityType = activityType, 
           (activityType.rawValue.contains("SaveToFiles") || 
            activityType.rawValue.contains("Files") ||
            activityType == .openInIBooks ||
            activityType.rawValue.contains("com.apple.CloudDocsUI")) {
            
            let filename = "\(memo.displayTitle).txt"
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            
            do {
                try memo.content.write(to: tempURL, atomically: true, encoding: .utf8)
                return tempURL
            } catch {
                print("テキストファイルの作成に失敗しました: \(error)")
                return memo.content
            }
        }
        
        // その他のアクティビティには通常のテキストを提供
        return memo.content
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
        return memo.displayTitle
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?) -> String {
        // 標準の「ファイルに保存」の場合はプレーンテキストのUTI
        if let activityType = activityType, activityType.rawValue.contains("com.apple.DocumentManagerUICore.SaveToFiles") {
            return "public.plain-text"
        }
        return "public.text"
    }
}

// MARK: - Custom Activity Classes

/// マークダウンエクスポート用のカスタムアクティビティ
class MarkdownExportActivity: UIActivity {
    private let memo: Memo
    
    init(memo: Memo) {
        self.memo = memo
        super.init()
    }
    
    override var activityType: UIActivity.ActivityType? {
        return UIActivity.ActivityType("jp.edfusion.localmemo.markdownexport")
    }
    
    override var activityTitle: String? {
        return "マークダウン出力"
    }
    
    override var activityImage: UIImage? {
        return UIImage(systemName: "doc.text")
    }
    
    override func canPerform(withActivityItems activityItems: [Any]) -> Bool {
        return !memo.content.isEmpty
    }
    
    override func perform() {
        // 画像参照があるかチェック
        let imageReferences = extractImageReferences(from: memo.content)
        
        if imageReferences.isEmpty {
            // 画像がない場合は従来通りマークダウンファイルのみ
            let filename = "\(memo.displayTitle).md"
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            
            do {
                try memo.content.write(to: tempURL, atomically: true, encoding: .utf8)
                
                // ファイル共有ダイアログを表示
                showDocumentPicker(for: tempURL)
                
            } catch {
                print("❌ マークダウンファイル作成エラー: \(error)")
                self.activityDidFinish(false)
            }
        } else {
            // 画像がある場合はzipファイルで出力
            createMarkdownWithImagesZip()
        }
    }
    
    /// ドキュメントピッカーを表示してファイルを保存
    private func showDocumentPicker(for fileURL: URL) {
        DispatchQueue.main.async {
            let documentPicker = UIDocumentPickerViewController(forExporting: [fileURL], asCopy: true)
            documentPicker.modalPresentationStyle = .formSheet
            
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first,
               let rootViewController = window.rootViewController {
                var presentingController = rootViewController
                while let presented = presentingController.presentedViewController {
                    presentingController = presented
                }
                presentingController.present(documentPicker, animated: true)
                self.activityDidFinish(true)
            } else {
                self.activityDidFinish(false)
            }
        }
    }
    
    /// マークダウンテキストから画像参照を抽出
    private func extractImageReferences(from markdown: String) -> [String] {
        var imageReferences: [String] = []
        let imagePattern = #"!\[([^\]]*)\]\(([^)]+)\)"#
        
        do {
            let regex = try NSRegularExpression(pattern: imagePattern)
            let matches = regex.matches(in: markdown, range: NSRange(markdown.startIndex..., in: markdown))
            
            for match in matches {
                if let urlRange = Range(match.range(at: 2), in: markdown) {
                    let imageURL = String(markdown[urlRange])
                    // ローカル画像のみを対象とする（http/httpsで始まらない）
                    if !imageURL.hasPrefix("http://") && !imageURL.hasPrefix("https://") {
                        imageReferences.append(imageURL)
                    }
                }
            }
        } catch {
            print("❌ 画像参照の抽出に失敗: \(error)")
        }
        
        return imageReferences
    }
    
    /// マークダウンと画像を含むzipファイルを作成
    private func createMarkdownWithImagesZip() {
        let zipURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(memo.displayTitle).zip")
        
        do {
            // 一時ディレクトリを作成
            let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
            
            // マークダウン内容の画像パスを相対パスに調整
            let adjustedContent = adjustImagePathsInMarkdown(content: memo.content)
            
            // マークダウンファイルを作成
            let markdownURL = tempDirectory.appendingPathComponent("\(memo.displayTitle).md")
            try adjustedContent.write(to: markdownURL, atomically: true, encoding: .utf8)
            
            // imagesディレクトリを作成
            let imagesDirectory = tempDirectory.appendingPathComponent("images")
            try FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
            
            // 画像ファイルをコピー
            let imageReferences = extractImageReferences(from: memo.content)
            for imageFilename in imageReferences {
                if let imageData = loadLocalImageData(filename: imageFilename) {
                    let imageURL = imagesDirectory.appendingPathComponent(imageFilename)
                    try imageData.write(to: imageURL)
                }
            }
            
            // zipファイルを作成（簡易実装）
            try createZipFile(sourceDirectory: tempDirectory, destinationURL: zipURL)
            
            // 一時ディレクトリを削除
            try FileManager.default.removeItem(at: tempDirectory)
            
            // zipファイル共有ダイアログを表示
            showDocumentPicker(for: zipURL)
            
        } catch {
            print("❌ zipファイル作成に失敗: \(error)")
            self.activityDidFinish(false)
        }
    }
    
    /// zipファイルを作成（Foundationを使用）
    private func createZipFile(sourceDirectory: URL, destinationURL: URL) throws {
        // zipファイルがすでに存在する場合は削除
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        
        // アーカイブを作成
        let coordinator = NSFileCoordinator()
        var error: NSError?
        
        coordinator.coordinate(readingItemAt: sourceDirectory, options: [.forUploading], error: &error) { (zipURL) in
            do {
                _ = try FileManager.default.replaceItem(at: destinationURL, withItemAt: zipURL, backupItemName: nil, options: [], resultingItemURL: nil)
            } catch {
                print("❌ アーカイブ作成エラー: \(error)")
            }
        }
        
        if let error = error {
            throw error
        }
    }
    
    /// ローカル画像データを読み込み
    private func loadLocalImageData(filename: String) -> Data? {
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        
        // 新しいパス形式（images）を優先して確認
        let newImagesDirectory = documentsDirectory.appendingPathComponent("images")
        let newImageFileURL = newImagesDirectory.appendingPathComponent(filename)
        
        if FileManager.default.fileExists(atPath: newImageFileURL.path) {
            do {
                return try Data(contentsOf: newImageFileURL)
            } catch {
                print("❌ 新形式画像ファイルの読み込みに失敗: \(error)")
            }
        }
        
        // 旧形式（MemoImages）も確認（後方互換性のため）
        let oldImagesDirectory = documentsDirectory.appendingPathComponent("MemoImages")
        let oldImageFileURL = oldImagesDirectory.appendingPathComponent(filename)
        
        do {
            return try Data(contentsOf: oldImageFileURL)
        } catch {
            print("❌ 旧形式画像ファイルの読み込みに失敗: \(error)")
            return nil
        }
    }
    
    /// マークダウン内の画像パスを相対パス（images/ファイル名）に調整
    private func adjustImagePathsInMarkdown(content: String) -> String {
        var adjustedContent = content
        let imagePattern = #"!\[([^\]]*)\]\(([^)]+)\)"#
        
        do {
            let regex = try NSRegularExpression(pattern: imagePattern)
            let matches = regex.matches(in: content, range: NSRange(content.startIndex..., in: content))
            
            // 後ろから処理して文字列位置がずれないようにする
            for match in matches.reversed() {
                if let altRange = Range(match.range(at: 1), in: content),
                   let urlRange = Range(match.range(at: 2), in: content) {
                    let altText = String(content[altRange])
                    let imageURL = String(content[urlRange])
                    
                    // ローカル画像の場合のみパスを調整
                    if !imageURL.hasPrefix("http://") && !imageURL.hasPrefix("https://") {
                        let filename = URL(fileURLWithPath: imageURL).lastPathComponent
                        let newImageMarkdown = "![\(altText)](images/\(filename))"
                        
                        // 元の画像マークダウンを新しいパスに置換
                        let fullMatchRange = match.range
                        if let swiftRange = Range(fullMatchRange, in: adjustedContent) {
                            adjustedContent.replaceSubrange(swiftRange, with: newImageMarkdown)
                        }
                    }
                }
            }
        } catch {
            print("❌ 画像パスの調整に失敗: \(error)")
        }
        
        return adjustedContent
    }
}

/// PDFエクスポート用のカスタムアクティビティ
class PDFExportActivity: UIActivity {
    private let memo: Memo
    
    init(memo: Memo) {
        self.memo = memo
        super.init()
    }
    
    override var activityType: UIActivity.ActivityType? {
        return UIActivity.ActivityType("jp.edfusion.localmemo.pdfexport")
    }
    
    override var activityTitle: String? {
        return "PDFファイル出力"
    }
    
    override var activityImage: UIImage? {
        return UIImage(systemName: "doc.richtext")
    }
    
    override func canPerform(withActivityItems activityItems: [Any]) -> Bool {
        return !memo.content.isEmpty
    }
    
    override func perform() {
        let enableChapterNumbering = AppSettings.shared.isChapterNumberingEnabled
        MarkdownRenderer.generatePDF(from: memo, enableChapterNumbering: enableChapterNumbering) { [weak self] data in
            DispatchQueue.main.async {
                guard let self = self, let pdfData = data else {
                    print("PDFの生成に失敗しました")
                    self?.activityDidFinish(false)
                    return
                }
                
                let filename = "\(self.memo.displayTitle).pdf"
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
                
                do {
                    try pdfData.write(to: tempURL)
                    
                    // ファイルエクスポーターを使用してPDFを保存
                    let documentPicker = UIDocumentPickerViewController(forExporting: [tempURL], asCopy: true)
                    documentPicker.modalPresentationStyle = .formSheet
                    
                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let window = windowScene.windows.first,
                       let rootViewController = window.rootViewController {
                        var presentingController = rootViewController
                        while let presented = presentingController.presentedViewController {
                            presentingController = presented
                        }
                        presentingController.present(documentPicker, animated: true)
                    }
                    
                    self.activityDidFinish(true)
                } catch {
                    print("PDFファイルの作成に失敗しました: \(error)")
                    self.activityDidFinish(false)
                }
            }
        }
    }
}

/// 印刷用のカスタムアクティビティ
class PrintActivity: UIActivity {
    private let memo: Memo
    
    init(memo: Memo) {
        self.memo = memo
        super.init()
    }
    
    override var activityType: UIActivity.ActivityType? {
        return UIActivity.ActivityType("jp.edfusion.localmemo.print")
    }
    
    override var activityTitle: String? {
        return "プリント"
    }
    
    override var activityImage: UIImage? {
        return UIImage(systemName: "printer")
    }
    
    override func canPerform(withActivityItems activityItems: [Any]) -> Bool {
        return !memo.content.isEmpty && UIPrintInteractionController.isPrintingAvailable
    }
    
    override func perform() {
        MarkdownRenderer.generatePDF(from: memo, enableChapterNumbering: AppSettings.shared.isChapterNumberingEnabled) { [weak self] data in
            DispatchQueue.main.async {
                guard let self = self, let pdfData = data else {
                    print("印刷用PDFの生成に失敗しました")
                    self?.activityDidFinish(false)
                    return
                }
                
                let printController = UIPrintInteractionController.shared
                let printInfo = UIPrintInfo.printInfo()
                printInfo.outputType = .general
                printInfo.jobName = self.memo.displayTitle
                printController.printInfo = printInfo
                printController.printingItem = pdfData
                
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let window = windowScene.windows.first,
                   let rootViewController = window.rootViewController {
                    var presentingController = rootViewController
                    while let presented = presentingController.presentedViewController {
                        presentingController = presented
                    }
                    
                    printController.present(animated: true) { (_, completed, error) in
                        if let error = error {
                            print("印刷エラー: \(error)")
                        }
                        self.activityDidFinish(completed)
                    }
                } else {
                    self.activityDidFinish(false)
                }
            }
        }
    }
}

// MARK: - Due Date Picker View
struct DueDatePickerView: View {
    @Binding var dueDate: Date
    @Binding var hasPreNotification: Bool
    @Binding var preNotificationMinutes: Int
    let onSave: (Date, Bool, Int) -> Void
    let onCancel: () -> Void
    
    private let preNotificationOptions = [
        (5, "5分前"),
        (15, "15分前"),
        (30, "30分前"),
        (60, "1時間前"),
        (120, "2時間前"),
        (1440, "1日前")
    ]
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("期日")) {
                    DatePicker("日時", selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
                        .datePickerStyle(GraphicalDatePickerStyle())
                        .environment(\.locale, Locale(identifier: "ja_JP"))
                }
                
                Section(header: Text("通知設定")) {
                    Toggle("予備通知", isOn: $hasPreNotification)
                        .onChange(of: hasPreNotification) { _, newValue in
                            if !newValue {
                                preNotificationMinutes = 0
                            } else if preNotificationMinutes == 0 {
                                preNotificationMinutes = 60 // デフォルト1時間前
                            }
                        }
                    
                    if hasPreNotification {
                        Picker("通知タイミング", selection: $preNotificationMinutes) {
                            ForEach(preNotificationOptions, id: \.0) { minutes, title in
                                Text(title).tag(minutes)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                    }
                }
                
                Section {
                    HStack {
                        Text("期日時刻に通知")
                        Spacer()
                        Image(systemName: "bell")
                            .foregroundColor(.blue)
                    }
                    
                    if hasPreNotification {
                        HStack {
                            Text("予備通知")
                            Spacer()
                            Text("\(formatPreNotificationTime(preNotificationMinutes))前")
                                .foregroundColor(.secondary)
                            Image(systemName: "bell.badge")
                                .foregroundColor(.orange)
                        }
                    }
                } header: {
                    Text("通知スケジュール")
                } footer: {
                    Text("期日になると通知でお知らせします。予備通知を有効にすると、指定した時間前にも通知されます。")
                }
            }
            .navigationTitle("期日設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("キャンセル") {
                        onCancel()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") {
                        onSave(dueDate, hasPreNotification, preNotificationMinutes)
                    }
                }
            }
        }
    }
    
    private func formatPreNotificationTime(_ minutes: Int) -> String {
        if minutes < 60 {
            return "\(minutes)分"
        } else if minutes < 1440 {
            let hours = minutes / 60
            return "\(hours)時間"
        } else {
            let days = minutes / 1440
            return "\(days)日"
        }
    }
}
