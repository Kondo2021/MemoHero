import SwiftUI
import Photos
import UIKit
import Combine
import Foundation

// MARK: - MemoCreationOption
/// メモ新規作成の選択肢
enum MemoCreationOption: String, CaseIterable, Identifiable {
    case blank = "blank"
    case fromClipboard = "fromClipboard"
    
    var id: String { rawValue }
    
    /// 表示名
    var displayName: String {
        switch self {
        case .blank:
            return "空白のメモ"
        case .fromClipboard:
            return "クリップボードから貼り付け"
        }
    }
    
    /// アイコン名
    var iconName: String {
        switch self {
        case .blank:
            return "doc"
        case .fromClipboard:
            return "doc.on.clipboard"
        }
    }
    
    /// 説明文
    var description: String {
        switch self {
        case .blank:
            return "新しい空白のメモを作成"
        case .fromClipboard:
            return "クリップボードの内容でメモを作成"
        }
    }
}


// MARK: - ClipboardHelper
/// クリップボード操作のヘルパークラス
class ClipboardHelper {
    
    /// クリップボードからテキストを取得
    static func getTextFromClipboard() -> String? {
        return UIPasteboard.general.string
    }
    
}

// MARK: - MemoCreationHelper
/// メモ作成のヘルパークラス
class MemoCreationHelper {
    
    /// 新規作成オプションに基づいてメモを作成
    static func createMemo(
        option: MemoCreationOption,
        folderId: UUID? = nil
    ) -> (memo: Memo?, errorMessage: String?)? {
        switch option {
        case .blank:
            return (memo: Memo(folderId: folderId), errorMessage: nil)
            
        case .fromClipboard:
            guard let clipboardText = ClipboardHelper.getTextFromClipboard(),
                  !clipboardText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return (memo: nil, errorMessage: "コピーされているテキストはありませんでした。")
            }
            let memo = Memo(content: clipboardText, folderId: folderId)
            return (memo: memo, errorMessage: nil)
        }
    }
    
    /// 作成可能かチェック
    static func canCreate(option: MemoCreationOption) -> Bool {
        switch option {
        case .blank:
            return true
        case .fromClipboard:
            return true
        }
    }
    
    /// オプションが無効な理由を取得
    static func disabledReason(for option: MemoCreationOption) -> String? {
        switch option {
        case .blank:
            return nil
        case .fromClipboard:
            return nil
        }
    }
}

// MARK: - Error Types
enum MemoListError: Error, LocalizedError {
    case memoLimitExceeded(count: Int)
    case invalidMemoOperation
    case uiStateCorrupted
    
    var errorDescription: String? {
        switch self {
        case .memoLimitExceeded(let count):
            return "メモ数が上限に達しています: \(count)"
        case .invalidMemoOperation:
            return "無効なメモ操作です"
        case .uiStateCorrupted:
            return "UI状態が破損しています"
        }
    }
}

// MARK: - AppTheme
/// アプリのテーマ設定を管理する列挙型
/// システム、ライト、ダークの3つのテーマをサポート
enum AppTheme: String, CaseIterable {
    case system = "system"  // システム設定に従う
    case light = "light"    // ライトモード固定
    case dark = "dark"      // ダークモード固定
    
    /// 表示用の名前
    var displayName: String {
        switch self {
        case .system:
            return "システム"
        case .light:
            return "ライト"
        case .dark:
            return "ダーク"
        }
    }
    
    /// SwiftUIのColorSchemeに変換
    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil  // システム設定に従う
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
    
    /// テーマ表示用のアイコン
    var icon: String {
        switch self {
        case .system:
            return "circle.lefthalf.filled"
        case .light:
            return "sun.max"
        case .dark:
            return "moon"
        }
    }
}

// MARK: - AppSettings
/// アプリの設定を管理するシングルトンクラス
/// テーマ、マークダウン表示、写真権限などの設定を管理
class AppSettings: ObservableObject {
    /// シングルトンインスタンス
    static let shared = AppSettings()
    
    // MARK: - Published Properties
    /// 現在のテーマ設定
    @Published var currentTheme: AppTheme = .system
    /// マークダウン表示の有効/無効
    @Published var isMarkdownEnabled: Bool = true
    /// 見出し表示の章番号自動追加の有効/無効
    @Published var isChapterNumberingEnabled: Bool = true
    /// 写真ライブラリアクセス権限の状態
    @Published var photoLibraryAuthStatus: PHAuthorizationStatus = .notDetermined
    
    // MARK: - Private Properties
    /// UserDefaultsインスタンス
    private let userDefaults = UserDefaults.standard
    /// テーマ設定保存用キー
    private let themeKey = "app_theme"
    /// マークダウン設定保存用キー
    private let markdownKey = "markdown_enabled"
    /// 見出し表示の章番号自動追加設定保存用キー
    private let chapterNumberingKey = "chapter_numbering_enabled"
    
    // MARK: - Initializer
    /// 初期化時に設定を読み込み、写真権限をチェック
    init() {
        loadSettings()
        checkPhotoLibraryPermission()
    }
    
    // MARK: - Settings Loading Methods
    /// 全ての設定を読み込み
    func loadSettings() {
        loadTheme()
        loadMarkdownSetting()
        loadChapterNumberingSetting()
    }
    
    /// テーマ設定を読み込み
    func loadTheme() {
        if let themeString = userDefaults.string(forKey: themeKey),
           let theme = AppTheme(rawValue: themeString) {
            currentTheme = theme
        }
    }
    
    /// マークダウン設定を読み込み
    func loadMarkdownSetting() {
        if userDefaults.object(forKey: markdownKey) != nil {
            isMarkdownEnabled = userDefaults.bool(forKey: markdownKey)
        } else {
            isMarkdownEnabled = true  // デフォルトは有効
        }
    }
    
    /// 見出し表示の章番号自動追加設定を読み込み
    func loadChapterNumberingSetting() {
        if userDefaults.object(forKey: chapterNumberingKey) != nil {
            isChapterNumberingEnabled = userDefaults.bool(forKey: chapterNumberingKey)
        } else {
            isChapterNumberingEnabled = true  // デフォルトは有効
        }
    }
    
    // MARK: - Settings Saving Methods
    /// テーマ設定を保存
    func setTheme(_ theme: AppTheme) {
        currentTheme = theme
        userDefaults.set(theme.rawValue, forKey: themeKey)
        userDefaults.synchronize()
    }
    
    /// マークダウン設定を保存
    func setMarkdownEnabled(_ enabled: Bool) {
        isMarkdownEnabled = enabled
        userDefaults.set(enabled, forKey: markdownKey)
        userDefaults.synchronize()
    }
    
    /// 見出し表示の章番号自動追加設定を保存
    func setChapterNumberingEnabled(_ enabled: Bool) {
        isChapterNumberingEnabled = enabled
        userDefaults.set(enabled, forKey: chapterNumberingKey)
        userDefaults.synchronize()
    }
    
    // MARK: - Photo Library Permission Methods
    /// 写真ライブラリアクセス権限の状態をチェック
    func checkPhotoLibraryPermission() {
        photoLibraryAuthStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }
    
    /// 写真ライブラリアクセス権限をリクエスト
    func requestPhotoLibraryPermission() {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] status in
            DispatchQueue.main.async {
                self?.photoLibraryAuthStatus = status
            }
        }
    }
    
    /// アプリの設定画面を開く
    func openAppSettings() {
        if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsUrl)
        }
    }
}

// MARK: - SettingsView
/// アプリの設定画面
/// テーマ、マークダウン表示、写真権限、フォルダ管理などの設定を提供
struct SettingsView: View {
    /// 画面を閉じるためのEnvironment変数
    @Environment(\.dismiss) private var dismiss
    /// アプリ設定のStateObject
    @StateObject private var appSettings = AppSettings.shared
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("テーマ設定")) {
                    ForEach(AppTheme.allCases, id: \.self) { theme in
                        HStack {
                            Image(systemName: theme.icon)
                                .foregroundColor(theme == appSettings.currentTheme ? .accentColor : .secondary)
                                .frame(width: 20)
                            
                            Text(theme.displayName)
                            
                            Spacer()
                            
                            if theme == appSettings.currentTheme {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            appSettings.setTheme(theme)
                        }
                    }
                }
                
                Section(header: Text("マークダウン表記")) {
                    HStack {
                        Image(systemName: "textformat")
                            .foregroundColor(.orange)
                            .frame(width: 20)
                        Text("表記適用")
                        Spacer()
                        Toggle("", isOn: $appSettings.isMarkdownEnabled)
                            .onChange(of: appSettings.isMarkdownEnabled) { _, newValue in
                                appSettings.setMarkdownEnabled(newValue)
                            }
                    }
                    
                    HStack {
                        Image(systemName: "number.square")
                            .foregroundColor(.blue)
                            .frame(width: 20)
                        Text("章番号自動付与")
                        Spacer()
                        Toggle("", isOn: $appSettings.isChapterNumberingEnabled)
                            .onChange(of: appSettings.isChapterNumberingEnabled) { _, newValue in
                                appSettings.setChapterNumberingEnabled(newValue)
                            }
                    }
                }
                
                Section(header: Text("バックアップ")) {
                    NavigationLink(destination: iCloudBackupView()) {
                        HStack {
                            Image(systemName: "icloud.and.arrow.up")
                                .foregroundColor(.blue)
                                .frame(width: 20)
                            Text("iCloud")
                        }
                    }
                    
                }
                
                Section(header: Text("フォルダ管理")) {
                    NavigationLink(destination: FolderManagementView()) {
                        HStack {
                            Image(systemName: "folder")
                                .foregroundColor(.blue)
                                .frame(width: 20)
                            Text("フォルダ管理")
                        }
                    }
                }
                
                Section(header: Text("アプリ情報")) {
                    HStack {
                        Text("バージョン")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("ビルド番号")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完了") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// テーマ適用用のViewModifier
struct ThemedView: ViewModifier {
    @StateObject private var appSettings = AppSettings.shared
    
    func body(content: Content) -> some View {
        content
            .preferredColorScheme(appSettings.currentTheme.colorScheme)
    }
}

extension View {
    func themed() -> some View {
        self.modifier(ThemedView())
    }
}

extension UIDeviceOrientation {
    var isPortrait: Bool {
        return self == .portrait || self == .portraitUpsideDown
    }
}

// MARK: - MemoListView
/// メモ一覧を表示するメインビュー
/// 検索、フィルタリング、複数選択削除、新規作成などの機能を提供
struct MemoListView: View {
    // MARK: - Environment Objects
    /// メモストア（データ管理）
    @EnvironmentObject private var memoStore: MemoStore
    /// フォルダストア（データ管理）
    @EnvironmentObject private var folderStore: FolderStore
    /// 通知管理（データ管理）
    @EnvironmentObject private var notificationManager: NotificationManager
    /// アプリのライフサイクル監視（バッジ無効化用）
    @Environment(\.scenePhase) private var scenePhase
    
    // MARK: - State Properties
    /// 選択されたメモ（iPad用）
    @State private var selectedMemo: Memo?
    /// 検索テキスト
    @State private var searchText = ""
    /// 検索モードの状態
    @State private var isSearching = false
    /// 新規メモ作成中フラグ
    @State private var isNewMemoCreation = false
    /// 新規作成メニュー表示フラグ
    @State private var showingCreationMenu = false
    /// エディタキー（再描画用）
    @State private var editorKey = 0
    /// ストア準備完了フラグ
    @State private var isStoreReady = false
    /// 表示中のメモ（iPhone用）
    @State private var presentedMemo: Memo?
    /// カラム表示設定（iPad用）
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    /// 現在の向き（iPad用）
    @State private var currentOrientation: UIDeviceOrientation = UIDevice.current.orientation
    /// 設定画面表示状態
    @State private var showingSettings = false
    /// プロフィール画面表示状態
    @State private var showingProfile = false
    /// カレンダー画面表示状態
    @State private var showingCalendar = false
    /// 通知履歴画面表示状態
    @State private var showingNotificationHistory = false
    /// イベント一覧画面表示状態
    @State private var showingEventList = false
    /// 選択されたフォルダ
    @State private var selectedFolder: Folder?
    /// トーストメッセージ
    @State private var toastMessage: String = ""
    /// トースト表示状態
    @State private var showToast = false
    /// フォルダ選択画面表示用のメモ
    @State private var showingFolderPickerForMemo: Memo?
    /// 期日設定画面表示用のメモ
    @State private var showingDueDatePickerForMemo: Memo?
    /// 期日設定用の一時的な日時
    @State private var tempDueDate = Date()
    /// 予備通知の有効フラグ
    @State private var tempHasPreNotification = true
    /// 予備通知時間（分単位）
    @State private var tempPreNotificationMinutes = 60
    
    // MARK: - Multi-Selection Properties
    /// 複数選択モードの状態
    @State private var isMultiSelectMode = false
    /// 選択されたメモのIDセット
    @State private var selectedMemos: Set<UUID> = []
    /// 削除確認ダイアログの表示状態
    @State private var showingDeleteConfirmation = false
    /// ピン留めメモ削除確認ダイアログの表示状態
    @State private var showingPinnedMemoDeleteConfirmation = false
    /// 削除予定のピン留めメモ
    @State private var memoToDelete: Memo?
    /// 切り替え先のメモ（一時保存）
    @State private var pendingMemo: Memo?
    /// 現在編集中のメモ
    @State private var currentEditingMemo: Memo?
    /// 編集中かどうかのフラグ
    @State private var isCurrentlyEditing = false
    
    // MARK: - Computed Properties
    /// 全てのメモが選択されているかどうか
    private var isAllSelected: Bool {
        !filteredMemos.isEmpty && selectedMemos.count == filteredMemos.count
    }
    
    /// フィルタリング・ソート済みのメモ配列
    private var filteredMemos: [Memo] {
        var memos = memoStore.memos
        
        // フォルダフィルタリング
        if let selectedFolder = selectedFolder {
            memos = memos.filter { $0.folderId == selectedFolder.id }
        }
        
        // 検索フィルタリング
        if !searchText.isEmpty {
            memos = memos.filter { memo in
                memo.title.localizedCaseInsensitiveContains(searchText) ||
                memo.content.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        // ソート: ピン留め > 更新日時
        return memos.sorted { memo1, memo2 in
            if memo1.isPinned != memo2.isPinned {
                return memo1.isPinned
            }
            return memo1.updatedAt > memo2.updatedAt
        }
    }
    
    // MARK: - Body
    var body: some View {
        mainContent
    }
    
    /// 初期化中の読み込み表示
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                .scaleEffect(1.5)
            
            Text("読み込み中...")
                .font(.title2)
                .foregroundColor(.secondary)
            
            Text("データを初期化しています")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "note.text")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("メモがありません")
                .font(.title2)
                .fontWeight(.medium)
                .foregroundColor(.primary)
            
            Text("右上の＋ボタンでメモを作成できます")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Menu {
                ForEach(MemoCreationOption.allCases) { option in
                    Button {
                        createMemo(with: option)
                    } label: {
                        Label(option.displayName, systemImage: option.iconName)
                    }
                    .disabled(!MemoCreationHelper.canCreate(option: option))
                }
                
            } label: {
                HStack {
                    Image(systemName: "plus")
                    Text("新しいメモ")
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding()
                .background(Color.blue)
                .cornerRadius(10)
            }
            .disabled(!memoStore.isInitialized)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var searchBarView: some View {
        HStack {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                TextField("メモを検索", text: $searchText)
                    .textFieldStyle(PlainTextFieldStyle())
                    .onTapGesture {
                        isSearching = true
                    }
                
                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                        isSearching = false
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(Color(.systemGray6))
            .cornerRadius(10)
            
            Button("日付検索") {
                showingCalendar = true
            }
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(Color.blue.opacity(0.1))
            .foregroundColor(.blue)
            .cornerRadius(8)
            
            if isSearching {
                Button("キャンセル") {
                    searchText = ""
                    isSearching = false
                    
                    // 入力フィールドが有効な状態でのみ resignFirstResponder を実行
                    DispatchQueue.main.async {
                        // より安全なアプローチ：現在のキー・ウィンドウから endEditing を呼び出す
                        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                           let keyWindow = windowScene.windows.first(where: { $0.isKeyWindow }) {
                            keyWindow.endEditing(true)
                        } else {
                            // fallbackとして従来の方法を使用
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        }
                    }
                }
                .foregroundColor(.blue)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 0)
        .padding(.bottom, 2)
    }
    
    private var folderFilterView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // すべてのメモボタン
                Button(action: {
                    selectedFolder = nil
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.text")
                            .font(.caption)
                        Text("すべて")
                            .font(.caption)
                            .fontWeight(.medium)
                        Text("(\(memoStore.memos.count))")
                            .font(.caption2)
                            .foregroundColor(selectedFolder == nil ? .white.opacity(0.8) : .secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(selectedFolder == nil ? Color.blue : Color(.systemGray5))
                    .foregroundColor(selectedFolder == nil ? .white : .primary)
                    .cornerRadius(16)
                }
                .buttonStyle(PlainButtonStyle())
                
                // フォルダボタン
                ForEach(folderStore.folders) { folder in
                    Button(action: {
                        selectedFolder = folder
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "folder.fill")
                                .font(.caption)
                                .foregroundColor(.blue)
                            Text(folder.name)
                                .font(.caption)
                                .fontWeight(.medium)
                            Text("(\(folderStore.memoCount(in: folder.id, allMemos: memoStore.memos)))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(selectedFolder?.id == folder.id ? Color.blue : Color(.systemGray5))
                        .foregroundColor(selectedFolder?.id == folder.id ? .white : .primary)
                        .cornerRadius(16)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 8)
        }
        .padding(.bottom, 2)
    }
    
    private var searchEmptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 50))
                .foregroundColor(.gray)
            
            Text("検索結果なし")
                .font(.title2)
                .fontWeight(.medium)
                .foregroundColor(.primary)
            
            Text("「\(searchText)」に一致するメモが見つかりませんでした")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var memoListContent: some View {
        List {
            ForEach(filteredMemos) { memo in
                HStack {
                    if isMultiSelectMode {
                        Button(action: {
                            toggleMemoSelection(memo.id)
                        }) {
                            Image(systemName: selectedMemos.contains(memo.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(selectedMemos.contains(memo.id) ? .blue : .gray)
                                .font(.title2)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    MemoRowView(
                        memo: memo, 
                        searchText: searchText, 
                        formatDate: formatDate,
                        onTap: {
                            if isMultiSelectMode {
                                toggleMemoSelection(memo.id)
                            } else {
                                // 編集中のメモがある場合、自動保存して切り替え
                                if isCurrentlyEditing && currentEditingMemo != nil && currentEditingMemo?.id != memo.id {
                                    pendingMemo = memo
                                    saveMemoAndSwitch()
                                } else {
                                    selectMemo(memo)
                                }
                            }
                        }
                    )
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        if memo.isPinned {
                            memoToDelete = memo
                            showingPinnedMemoDeleteConfirmation = true
                        } else {
                            memoStore.deleteMemo(memo)
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "trash")
                                .font(.system(size: 20, weight: .medium))
                            Text("削除")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .frame(minWidth: 50, minHeight: 60)
                    }
                    
                    Button {
                        memoStore.duplicateMemo(memo)
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 20, weight: .medium))
                            Text("複製")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .frame(minWidth: 50, minHeight: 60)
                    }
                    .tint(.blue)
                    
                    Button {
                        showShareOptions(for: memo)
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 20, weight: .medium))
                            Text("共有")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .frame(minWidth: 50, minHeight: 60)
                    }
                    .tint(.indigo)
                }
                .swipeActions(edge: .leading) {
                    Button {
                        showingFolderPickerForMemo = memo
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "folder")
                                .font(.system(size: 20, weight: .medium))
                            Text("フォルダ")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .frame(minWidth: 50, minHeight: 60)
                    }
                    .tint(.purple)
                    
                    Button {
                        memoStore.togglePin(memo)
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: memo.isPinned ? "pin.slash" : "pin")
                                .font(.system(size: 20, weight: .medium))
                            Text(memo.isPinned ? "ピン解除" : "ピン留め")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .frame(minWidth: 50, minHeight: 60)
                    }
                    .tint(.orange)
                    
                    Button {
                        if let dueDate = memo.dueDate {
                            tempDueDate = dueDate
                            tempHasPreNotification = memo.hasPreNotification
                            tempPreNotificationMinutes = memo.preNotificationMinutes
                        } else {
                            tempDueDate = Date().addingTimeInterval(3600)
                            tempHasPreNotification = true
                            tempPreNotificationMinutes = 60
                        }
                        showingDueDatePickerForMemo = memo
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: memo.dueDate != nil ? "calendar.badge.clock" : "calendar.badge.plus")
                                .font(.system(size: 20, weight: .medium))
                            Text("期日")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .frame(minWidth: 50, minHeight: 60)
                    }
                    .tint(.green)
                }
            }
        }
        .listStyle(PlainListStyle())
    }
    
    private func createNewMemo() {
        let timestamp = DateFormatter.debugFormatter.string(from: Date())
        print("🆕 MemoListView.createNewMemo() 呼び出し [\(timestamp)]")
        print("   MemoStore初期化状態: \(memoStore.isInitialized)")
        print("   現在のメモ数: \(memoStore.memos.count)")
        
        do {
            // ストアが初期化完了していない場合は新規作成をスキップ
            guard memoStore.isInitialized else {
                print("❌ MemoListView - ストア初期化未完了のため新規メモ作成をスキップ")
                return
            }
            
            // メモ数の制限チェック（メモリ保護）
            if memoStore.memos.count >= 10000 {
                print("⚠️ メモ数が上限に達しています: \(memoStore.memos.count)")
                throw MemoListError.memoLimitExceeded(count: memoStore.memos.count)
            }
            
            let newMemo = Memo()
            print("   新規メモ作成 ID: \(newMemo.id.uuidString.prefix(8))")
            
            print("   memoStore.addMemo() 呼び出し")
            memoStore.addMemo(newMemo)
            
            presentedMemo = newMemo
            selectedMemo = newMemo
            currentEditingMemo = newMemo
            isNewMemoCreation = true
            isCurrentlyEditing = true
            editorKey += 1
            
            print("   UI状態更新完了 - presentedMemo設定, isNewMemoCreation=true, editorKey=\(editorKey)")
            
            // サイドバーの表示状態はユーザーの操作に委ねる
            print("   サイドバー制御スキップ - ユーザー操作に委ねる")
            
            print("✅ MemoListView.createNewMemo() 完了 [\(DateFormatter.debugFormatter.string(from: Date()))]")
            
        } catch {
            print("❌ ERROR: MemoListView.createNewMemo()中にエラーが発生 [\(DateFormatter.debugFormatter.string(from: Date()))]")
            print("   エラー詳細: \(error)")
            print("   エラータイプ: \(type(of: error))")
            
            // エラー状態でもUIは応答性を保つ
            if let listError = error as? MemoListError {
                print("   MemoListError: \(listError.localizedDescription)")
            }
        }
    }
    

    /// 新規作成オプションに基づいてメモを作成
    private func createMemo(with option: MemoCreationOption) {
        let timestamp = DateFormatter.debugFormatter.string(from: Date())
        print("🆕 MemoListView.createMemo(with: \(option.displayName)) 呼び出し [\(timestamp)]")
        print("   MemoStore初期化状態: \(memoStore.isInitialized)")
        
        do {
            // ストアが初期化完了していない場合は新規作成をスキップ
            guard memoStore.isInitialized else {
                print("❌ MemoListView - ストア初期化未完了のため新規メモ作成をスキップ")
                return
            }
            
            // メモ数の制限チェック（メモリ保護）
            if memoStore.memos.count >= 10000 {
                print("⚠️ メモ数が上限に達しています: \(memoStore.memos.count)")
                throw MemoListError.memoLimitExceeded(count: memoStore.memos.count)
            }
            
            // 選択されたオプションでメモを作成できるかチェック
            guard MemoCreationHelper.canCreate(option: option) else {
                print("❌ 選択されたオプションでメモを作成できません: \(option.displayName)")
                if let reason = MemoCreationHelper.disabledReason(for: option) {
                    print("   理由: \(reason)")
                }
                return
            }
            
            // メモを作成
            guard let result = MemoCreationHelper.createMemo(option: option, folderId: selectedFolder?.id) else {
                print("❌ メモ作成関数の呼び出しに失敗しました")
                return
            }
            
            guard let newMemo = result.memo else {
                print("❌ メモの作成に失敗しました: \(result.errorMessage ?? "不明なエラー")")
                if let errorMessage = result.errorMessage {
                    showToastMessage(errorMessage)
                }
                return
            }
            
            print("   新規メモ作成 ID: \(newMemo.id.uuidString.prefix(8))")
            print("   作成方法: \(option.displayName)")
            
            // メモストアに追加
            print("   memoStore.addMemo() 呼び出し")
            memoStore.addMemo(newMemo)
            
            // UI状態を更新
            presentedMemo = newMemo
            selectedMemo = newMemo
            currentEditingMemo = newMemo
            isNewMemoCreation = true
            isCurrentlyEditing = true
            editorKey += 1
            
            print("   UI状態更新完了 - presentedMemo設定, isNewMemoCreation=true, editorKey=\(editorKey)")
            print("✅ MemoListView.createMemo(with: \(option.displayName)) 完了 [\(DateFormatter.debugFormatter.string(from: Date()))]")
            
        } catch {
            print("❌ ERROR: MemoListView.createMemo(with: \(option.displayName))中にエラーが発生 [\(DateFormatter.debugFormatter.string(from: Date()))]")
            print("   エラー詳細: \(error)")
            print("   エラータイプ: \(type(of: error))")
            
            // エラー状態でもUIは応答性を保つ
            if let listError = error as? MemoListError {
                print("   MemoListError: \(listError.localizedDescription)")
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        var calendar = Calendar.current
        calendar.locale = Locale(identifier: "ja_JP")
        
        if calendar.isDate(date, inSameDayAs: Date()) {
            formatter.dateStyle = .none
            formatter.timeStyle = .short
            return "今日 \(formatter.string(from: date))"
        } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: Date()),
                  calendar.isDate(date, inSameDayAs: yesterday) {
            formatter.dateStyle = .none
            formatter.timeStyle = .short
            return "昨日 \(formatter.string(from: date))"
        } else if calendar.isDate(date, equalTo: Date(), toGranularity: .weekOfYear) {
            formatter.dateFormat = "E HH:mm"
            return formatter.string(from: date)
        } else if calendar.isDate(date, equalTo: Date(), toGranularity: .year) {
            formatter.dateFormat = "MM/dd HH:mm"
            return formatter.string(from: date)
        } else {
            formatter.dateFormat = "yyyy/MM/dd"
            return formatter.string(from: date)
        }
    }
    
    private func enterMultiSelectMode() {
        isMultiSelectMode = true
        selectedMemos.removeAll()
    }
    
    private func exitMultiSelectMode() {
        isMultiSelectMode = false
        selectedMemos.removeAll()
    }
    
    private func toggleMemoSelection(_ memoId: UUID) {
        if selectedMemos.contains(memoId) {
            selectedMemos.remove(memoId)
        } else {
            selectedMemos.insert(memoId)
        }
    }
    
    private func deleteSelectedMemos() {
        showingDeleteConfirmation = true
    }
    
    private func confirmDeleteSelectedMemos() {
        for memoId in selectedMemos {
            if let memo = memoStore.memos.first(where: { $0.id == memoId }) {
                memoStore.deleteMemo(memo)
            }
        }
        exitMultiSelectMode()
    }
    
    private func toggleSelectAll() {
        if isAllSelected {
            selectedMemos.removeAll()
        } else {
            selectedMemos = Set(filteredMemos.map { $0.id })
        }
    }
    
    private func selectMemo(_ memo: Memo) {
        print("=== メモ選択開始 ===")
        print("選択されたメモ - ID: \(memo.id), content: '\(memo.content.prefix(50))'")
        
        // メモを直接設定
        presentedMemo = memo
        selectedMemo = memo
        currentEditingMemo = memo
        isNewMemoCreation = false
        isCurrentlyEditing = false
        editorKey += 1
        
        // サイドバーの表示状態はユーザーの操作に委ねる
        
        print("設定完了 - presentedMemo: \(presentedMemo?.id.uuidString ?? "nil")")
        print("=== メモ選択終了 ===")
    }
    
    private func saveMemoAndSwitch() {
        guard let pendingMemo = pendingMemo else { return }
        
        print("🔄 保存して切り替え処理開始")
        
        // 現在編集中のメモを保存（MemoEditorViewで編集された最新の内容）
        if let currentMemo = currentEditingMemo {
            print("   現在編集中のメモを保存: \(currentMemo.id.uuidString.prefix(8))")
            print("   メモ内容: '\(currentMemo.content.prefix(50))'")
            
            // 更新日時を設定して保存
            var memoToSave = currentMemo
            memoToSave.updatedAt = Date()
            
            memoStore.updateMemo(memoToSave)
            
            // 保存後の確認
            if let savedMemo = memoStore.memos.first(where: { $0.id == memoToSave.id }) {
                print("   MemoStore.updateMemo() 完了")
                print("   保存確認 - ID: \(savedMemo.id.uuidString.prefix(8))")
                print("   保存確認 - 内容: '\(savedMemo.content.prefix(50))'")
                print("   保存確認 - 更新日時: \(savedMemo.updatedAt)")
                print("   タイトルがメモ一覧に反映されます")
            } else {
                print("   ❌ 保存後の確認でメモが見つかりません")
            }
        } else {
            print("   現在編集中のメモなし")
        }
        
        // 新しいメモに切り替え
        selectMemo(pendingMemo)
        self.pendingMemo = nil
        
        print("📝 保存して切り替え処理完了")
    }
    
    private func discardAndSwitch() {
        guard let pendingMemo = pendingMemo else { return }
        
        // 変更を破棄して新しいメモに切り替え
        selectMemo(pendingMemo)
        self.pendingMemo = nil
    }
    
    func onEditingStateChanged(isEditing: Bool) {
        isCurrentlyEditing = isEditing
    }
    
    func onMemoUpdated(_ updatedMemo: Memo) {
        // 編集中のメモの参照のみ更新（メモ一覧には反映しない）
        currentEditingMemo = updatedMemo
        print("📝 編集中メモ更新: \(updatedMemo.id.uuidString.prefix(8)) - content: '\(updatedMemo.content.prefix(30))'")
    }
    
    /// トーストメッセージを表示
    private func showToastMessage(_ message: String) {
        toastMessage = message
        withAnimation(.easeInOut(duration: 0.2)) {
            showToast = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeInOut(duration: 0.2)) {
                showToast = false
            }
        }
    }
    
    // MARK: - Main Content
    private var mainContent: some View {
        Group {
            // 初期化完了チェック
            if !memoStore.isInitialized || !folderStore.isInitialized {
                loadingView
            } else {
                // iPadの場合：NavigationSplitViewで分割表示
                if UIDevice.current.userInterfaceIdiom == .pad {
                    iPadLayout
                } else {
                    // iPhoneの場合：NavigationViewで標準表示
                    iPhoneLayout
                }
            }
        }
        .onAppear {
            // メインスレッドでの重い処理を避けるため、バックグラウンドで初期化処理を実行
            DispatchQueue.global(qos: .userInitiated).async {
                // 初期化状態の確認処理
                let storeInitialized = memoStore.isInitialized && folderStore.isInitialized
                
                // UI更新はメインスレッドで実行
                DispatchQueue.main.async {
                    if storeInitialized {
                        isStoreReady = true
                        print("✅ MemoListView - ストア初期化完了確認")
                    } else {
                        print("⏳ MemoListView - ストア初期化待機中")
                        // 少し待ってから再確認
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            if self.memoStore.isInitialized && self.folderStore.isInitialized {
                                self.isStoreReady = true
                                print("✅ MemoListView - ストア初期化完了（遅延確認）")
                            }
                        }
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenMemoFromNotification"))) { notification in
            if let userInfo = notification.userInfo,
               let memoId = userInfo["memoId"] as? UUID,
               let memo = memoStore.memos.first(where: { $0.id == memoId }) {
                
                // 既存の画面を全て閉じる
                presentedMemo = nil
                selectedMemo = nil
                showingSettings = false
                showingCalendar = false
                showingNotificationHistory = false
                
                // プレビュー状態でメモを開く
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    if UIDevice.current.userInterfaceIdiom == .phone {
                        self.presentedMemo = memo
                        self.isNewMemoCreation = false
                    } else {
                        self.selectedMemo = memo
                    }
                    
                    // エディターはプレビュー（読み取り専用）状態で開く
                    self.isCurrentlyEditing = false
                    self.editorKey += 1
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenMemoFromWidget"))) { notification in
            if let userInfo = notification.userInfo,
               let memoId = userInfo["memoId"] as? UUID,
               let memo = memoStore.memos.first(where: { $0.id == memoId }) {
                
                print("🚀 ウィジェットからメモを開く: \(memo.displayTitle)")
                
                // 既存の画面を全て閉じる
                presentedMemo = nil
                selectedMemo = nil
                showingSettings = false
                showingCalendar = false
                showingNotificationHistory = false
                
                // プレビュー状態でメモを開く
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    if UIDevice.current.userInterfaceIdiom == .phone {
                        self.presentedMemo = memo
                        self.isNewMemoCreation = false
                    } else {
                        self.selectedMemo = memo
                    }
                    
                    // エディターはプレビュー（読み取り専用）状態で開く
                    self.isCurrentlyEditing = false
                    self.editorKey += 1
                }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                // アプリがフォアグラウンドに戻った時にバッジを絶対に無効化
                notificationManager.disableBadge()
            }
        }
        .themed()
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showingProfile) {
            ProfileView()
        }
        .sheet(isPresented: $showingCalendar) {
            CalendarView(memos: memoStore.memos, onMemoSelected: { memo in
                showingCalendar = false
                presentedMemo = memo
            })
        }
        .sheet(isPresented: $showingNotificationHistory) {
            NotificationHistoryView()
        }
        .sheet(isPresented: $showingEventList) {
            EventListView { memo in
                showingEventList = false
                presentedMemo = memo
            }
        }
        .sheet(item: $showingFolderPickerForMemo) { memo in
            FolderSelectionView(memo: memo, memoStore: memoStore, folderStore: folderStore) {
                showingFolderPickerForMemo = nil
            }
        }
        .sheet(item: $showingDueDatePickerForMemo) { memo in
            DueDateSettingView(
                memo: memo,
                memoStore: memoStore,
                notificationManager: notificationManager,
                onDismiss: {
                    showingDueDatePickerForMemo = nil
                },
                tempDueDate: $tempDueDate,
                tempHasPreNotification: $tempHasPreNotification,
                tempPreNotificationMinutes: $tempPreNotificationMinutes
            )
        }
        .alert("メモの削除", isPresented: $showingDeleteConfirmation) {
            Button("削除", role: .destructive) {
                confirmDeleteSelectedMemos()
            }
            Button("キャンセル", role: .cancel) { }
        } message: {
            Text("\(selectedMemos.count)個のメモを削除しますか？この操作は取り消せません。")
        }
        .alert("ピン留めメモの削除", isPresented: $showingPinnedMemoDeleteConfirmation) {
            Button("削除", role: .destructive) {
                if let memo = memoToDelete {
                    memoStore.deleteMemo(memo)
                    memoToDelete = nil
                }
            }
            Button("キャンセル", role: .cancel) {
                memoToDelete = nil
            }
        } message: {
            Text("ピン留めされたメモを削除しますか？この操作は取り消せません。")
        }
        .sheet(item: UIDevice.current.userInterfaceIdiom == .phone ? $presentedMemo : .constant(nil), onDismiss: {
            print("=== Sheet閉じる時の処理 ===")
            selectedMemo = nil
            isNewMemoCreation = false
        }) { memo in
            let _ = print("=== Sheet表示開始 ===")
            let _ = print("表示するメモ - ID: \(memo.id), content: '\(memo.content.prefix(50))'")
            let _ = print("isNewMemoCreation: \(isNewMemoCreation)")
            
            NavigationView {
                MemoEditorView(
                    memo: memo, 
                    memoStore: memoStore, 
                    isNewMemo: isNewMemoCreation
                ) {
                    presentedMemo = nil
                } onEditingStateChanged: { isEditing in
                    onEditingStateChanged(isEditing: isEditing)
                } onMemoUpdated: { updatedMemo in
                    onMemoUpdated(updatedMemo)
                }
                .id(editorKey)
            }
        }
        .overlay(
            // トーストメッセージ
            VStack {
                if showToast {
                    Text(toastMessage)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.8))
                        .foregroundColor(.white)
                        .cornerRadius(8)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                Spacer()
            }
            .padding(.top, 50)
        )
    }
    
    // MARK: - iPad Layout
    private var iPadLayout: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            VStack(spacing: 15) {
                if !memoStore.memos.isEmpty {
                    searchBarView
                    folderFilterView
                }
                
                if filteredMemos.isEmpty && !searchText.isEmpty {
                    searchEmptyStateView
                } else if memoStore.memos.isEmpty {
                    emptyStateView
                } else {
                    memoListContent
                }
            }
            .navigationTitle("メモ")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if isMultiSelectMode {
                        Button("キャンセル") {
                            exitMultiSelectMode()
                        }
                    } else {
                        HStack(spacing: 16) {
                            Button(action: {
                                showingProfile = true
                            }) {
                                Image(systemName: "person.circle")
                                    .font(.title3)
                            }
                            Button(action: {
                                showingSettings = true
                            }) {
                                Image(systemName: "gearshape")
                                    .font(.title3)
                            }
                            Button(action: {
                                showingNotificationHistory = true
                            }) {
                                Image(systemName: "bell")
                                    .font(.title3)
                            }
                            Button(action: {
                                showingEventList = true
                            }) {
                                Image(systemName: "calendar")
                                    .font(.title3)
                            }
                        }
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    if isMultiSelectMode {
                        HStack(spacing: 12) {
                            Button(isAllSelected ? "全て解除" : "全て選択") {
                                toggleSelectAll()
                            }
                            .disabled(filteredMemos.isEmpty)
                            
                            Button(action: deleteSelectedMemos) {
                                Image(systemName: "trash")
                                    .font(.title3)
                                    .foregroundColor(.red)
                            }
                            .disabled(selectedMemos.isEmpty)
                        }
                    } else {
                        HStack(spacing: 12) {
                            Button("選択") {
                                enterMultiSelectMode()
                            }
                            .disabled(!memoStore.isInitialized || memoStore.memos.isEmpty)
                            
                            Menu {
                                ForEach(MemoCreationOption.allCases) { option in
                                    Button {
                                        createMemo(with: option)
                                    } label: {
                                        Label(option.displayName, systemImage: option.iconName)
                                    }
                                    .disabled(!MemoCreationHelper.canCreate(option: option))
                                }
                                
                            } label: {
                                Image(systemName: "square.and.pencil")
                                    .font(.title3)
                            }
                            .disabled(!memoStore.isInitialized)
                        }
                    }
                }
            }
        } detail: {
            if let memo = presentedMemo {
                MemoEditorView(
                    memo: memo,
                    memoStore: memoStore,
                    isNewMemo: isNewMemoCreation
                ) {
                    presentedMemo = nil
                } onEditingStateChanged: { isEditing in
                    onEditingStateChanged(isEditing: isEditing)
                } onMemoUpdated: { updatedMemo in
                    onMemoUpdated(updatedMemo)
                }
                .id(editorKey)
            } else {
                Text("メモを選択してください")
                    .font(.title2)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemBackground))
            }
        }
        .navigationSplitViewStyle(.balanced)
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            let newOrientation = UIDevice.current.orientation
            if newOrientation.isValidInterfaceOrientation {
                currentOrientation = newOrientation
            }
        }
    }
    
    // MARK: - iPhone Layout
    private var iPhoneLayout: some View {
        NavigationView {
            VStack(spacing: 15) {
                if !memoStore.memos.isEmpty {
                    searchBarView
                    folderFilterView
                }
                
                if filteredMemos.isEmpty && !searchText.isEmpty {
                    searchEmptyStateView
                } else if memoStore.memos.isEmpty {
                    emptyStateView
                } else {
                    memoListContent
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if isMultiSelectMode {
                        Button("キャンセル") {
                            exitMultiSelectMode()
                        }
                    } else {
                        HStack {
                            Button(action: {
                                showingProfile = true
                            }) {
                                Image(systemName: "person.circle")
                            }
                            Button(action: {
                                showingSettings = true
                            }) {
                                Image(systemName: "gearshape")
                            }
                            Button(action: {
                                showingNotificationHistory = true
                            }) {
                                Image(systemName: "bell")
                            }
                            Button(action: {
                                showingEventList = true
                            }) {
                                Image(systemName: "calendar")
                            }
                        }
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    if isMultiSelectMode {
                        HStack {
                            Button(isAllSelected ? "全て解除" : "全て選択") {
                                toggleSelectAll()
                            }
                            .disabled(filteredMemos.isEmpty)
                            
                            Button(action: deleteSelectedMemos) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                            .disabled(selectedMemos.isEmpty)
                        }
                    } else {
                        HStack {
                            Button("選択") {
                                enterMultiSelectMode()
                            }
                            .disabled(!memoStore.isInitialized || memoStore.memos.isEmpty)
                            Menu {
                                ForEach(MemoCreationOption.allCases) { option in
                                    Button {
                                        createMemo(with: option)
                                    } label: {
                                        Label(option.displayName, systemImage: option.iconName)
                                    }
                                    .disabled(!MemoCreationHelper.canCreate(option: option))
                                }
                                
                            } label: {
                                Image(systemName: "square.and.pencil")
                            }
                            .disabled(!memoStore.isInitialized)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - View Extensions
extension View {
    @ViewBuilder
    func applyModifiers() -> some View {
        self
    }
}

struct MemoRowView: View {
    let memo: Memo
    let searchText: String
    let formatDate: (Date) -> String
    let onTap: () -> Void
    
    init(memo: Memo, searchText: String = "", formatDate: @escaping (Date) -> String, onTap: @escaping () -> Void) {
        self.memo = memo
        self.searchText = searchText
        self.formatDate = formatDate
        self.onTap = onTap
    }
    
    private var displayTitle: String {
        // memoのtitleが空の場合、1行目から取得
        if memo.title.isEmpty {
            let firstLine = memo.content.components(separatedBy: .newlines).first ?? ""
            if firstLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "無題のメモ"
            }
            // マークダウンの見出し記号（#）を取り除く
            let cleanedLine = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "^#{1,6}\\s*", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            return cleanedLine.isEmpty ? "無題のメモ" : cleanedLine
        }
        return memo.title
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if memo.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                
                highlightedText(displayTitle)
                    .font(.headline)
                    .lineLimit(1)
                
                Spacer()
            }
            
            HStack {
                Text("作成日時: \(DateFormatter.dateTimeFormatterWithWeekday.string(from: memo.createdAt))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if memo.createdAt != memo.updatedAt {
                    Text("更新日時: \(DateFormatter.dateTimeFormatterWithWeekday.string(from: memo.updatedAt))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            if let dueDate = memo.dueDate {
                HStack {
                    Text("期日:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if memo.isOverdue {
                        Text("【期限切れ】")
                            .font(.caption)
                            .foregroundColor(.red)
                            .fontWeight(.medium)
                    } else if memo.isDueToday {
                        Text("【今日】")
                            .font(.caption)
                            .foregroundColor(.orange)
                            .fontWeight(.medium)
                    }
                    
                    Text(DateFormatter.dueDateFormatterWithWeekday.string(from: dueDate))
                        .font(.caption)
                        .foregroundColor(memo.isOverdue ? .red : (memo.isDueToday ? .orange : .secondary))
                    
                    Spacer()
                }
            }
        }
        .frame(minHeight: 60)  // 最小高さを確保
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
    }
    
    private func highlightedText(_ text: String) -> some View {
        if searchText.isEmpty {
            return AnyView(Text(text).foregroundColor(.primary))
        }
        
        return AnyView(createHighlightedView(text: text, searchText: searchText))
    }
    
    private func createHighlightedView(text: String, searchText: String) -> some View {
        guard !searchText.isEmpty else {
            return AnyView(Text(text).foregroundColor(.primary))
        }
        
        // 大文字小文字を区別しない検索のため、NSStringを使用
        let nsText = text as NSString
        let _ = searchText as NSString
        
        // すべてのマッチする範囲を見つける
        var ranges: [NSRange] = []
        var searchRange = NSRange(location: 0, length: nsText.length)
        
        while searchRange.location < nsText.length {
            let foundRange = nsText.range(of: searchText, options: .caseInsensitive, range: searchRange)
            if foundRange.location == NSNotFound {
                break
            }
            ranges.append(foundRange)
            searchRange.location = foundRange.location + foundRange.length
            searchRange.length = nsText.length - searchRange.location
        }
        
        guard !ranges.isEmpty else {
            return AnyView(Text(text).foregroundColor(.primary))
        }
        
        // テキストを分割してハイライト表示
        var textParts: [AnyView] = []
        var currentLocation = 0
        
        for range in ranges {
            // マッチ前のテキスト
            if currentLocation < range.location {
                let beforeText = nsText.substring(with: NSRange(location: currentLocation, length: range.location - currentLocation))
                if !beforeText.isEmpty {
                    textParts.append(AnyView(
                        Text(beforeText)
                            .foregroundColor(.primary)
                    ))
                }
            }
            
            // マッチしたテキスト（ハイライト）
            let matchText = nsText.substring(with: range)
            textParts.append(AnyView(
                Text(matchText)
                    .foregroundColor(.black)
                    .fontWeight(.bold)
                    .padding(.horizontal, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.yellow.opacity(0.8))
                    )
            ))
            
            currentLocation = range.location + range.length
        }
        
        // 最後のマッチ後のテキスト
        if currentLocation < nsText.length {
            let afterText = nsText.substring(from: currentLocation)
            if !afterText.isEmpty {
                textParts.append(AnyView(
                    Text(afterText)
                        .foregroundColor(.primary)
                ))
            }
        }
        
        return AnyView(
            HStack(spacing: 0) {
                ForEach(0..<textParts.count, id: \.self) { index in
                    textParts[index]
                }
            }
        )
    }
}

// フォルダ管理画面
struct FolderManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var folderStore: FolderStore
    @EnvironmentObject private var memoStore: MemoStore
    
    @State private var showingAddFolder = false
    @State private var editingFolder: Folder?
    @State private var showingDeleteAlert = false
    @State private var folderToDelete: Folder?
    
    var body: some View {
        List {
            Section("フォルダ管理") {
                ForEach(folderStore.folders) { folder in
                    HStack {
                        Image(systemName: "folder.fill")
                            .foregroundColor(.blue)
                        Text(folder.name)
                        Spacer()
                        Text("\(folderStore.memoCount(in: folder.id, allMemos: memoStore.memos))")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        editingFolder = folder
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            folderToDelete = folder
                            showingDeleteAlert = true
                        } label: {
                            Label("削除", systemImage: "trash")
                        }
                    }
                }
                .onDelete(perform: deleteFolders)
            }
        }
        .navigationTitle("フォルダ管理")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("追加") {
                    showingAddFolder = true
                }
                .disabled(!folderStore.isInitialized)
            }
        }
        .sheet(isPresented: $showingAddFolder) {
            FolderEditView(folder: nil)
        }
        .sheet(item: $editingFolder) { folder in
            FolderEditView(folder: folder)
        }
        .alert("フォルダを削除", isPresented: $showingDeleteAlert) {
            Button("削除", role: .destructive) {
                if let folder = folderToDelete {
                    folderStore.deleteFolder(folder, memoStore: memoStore)
                    folderToDelete = nil
                }
            }
            Button("キャンセル", role: .cancel) {
                folderToDelete = nil
            }
        } message: {
            Text("フォルダを削除しますか？フォルダ内のメモは「すべて」に移動されます。")
        }
    }
    
    private func deleteFolders(offsets: IndexSet) {
        for index in offsets {
            let folder = folderStore.folders[index]
            folderStore.deleteFolder(folder, memoStore: memoStore)
        }
    }
}

// フォルダ編集画面
struct FolderEditView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var folderStore: FolderStore
    
    let folder: Folder?
    @State private var name: String = ""
    
    private var isEditing: Bool { folder != nil }
    
    var body: some View {
        NavigationView {
            Form {
                Section("フォルダ情報") {
                    TextField("フォルダ名", text: $name)
                }
            }
            .navigationTitle(isEditing ? "フォルダ編集" : "新規フォルダ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") {
                        saveFolder()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || !folderStore.isInitialized)
                }
            }
        }
        .onAppear {
            if let folder = folder {
                name = folder.name
            }
        }
    }
    
    private func saveFolder() {
        let timestamp = DateFormatter.debugFormatter.string(from: Date())
        print("📁 FolderEditView.saveFolder() 呼び出し [\(timestamp)]")
        print("   FolderStore初期化状態: \(folderStore.isInitialized)")
        print("   編集モード: \(isEditing)")
        print("   フォルダ名: '\(name.trimmingCharacters(in: .whitespaces))'")
        
        // ストアが初期化完了していない場合は保存をスキップ
        guard folderStore.isInitialized else {
            print("❌ FolderEditView - ストア初期化未完了のため保存をスキップ")
            dismiss()
            return
        }
        
        if let folder = folder {
            // 編集
            print("   フォルダ編集モード - ID: \(folder.id.uuidString.prefix(8))")
            print("   名前変更: '\(folder.name)' → '\(name.trimmingCharacters(in: .whitespaces))'")
            
            var updatedFolder = folder
            updatedFolder.updateName(name.trimmingCharacters(in: .whitespaces))
            
            print("   folderStore.updateFolder() 呼び出し")
            folderStore.updateFolder(updatedFolder)
        } else {
            // 新規作成
            print("   フォルダ新規作成モード")
            let newFolder = Folder(name: name.trimmingCharacters(in: .whitespaces))
            print("   新規フォルダ作成 ID: \(newFolder.id.uuidString.prefix(8))")
            
            print("   folderStore.addFolder() 呼び出し")
            folderStore.addFolder(newFolder)
        }
        
        print("✅ FolderEditView.saveFolder() 完了 [\(DateFormatter.debugFormatter.string(from: Date()))]")
        dismiss()
    }
}


// MARK: - Calendar Date Info
/// カレンダー日付の情報
struct CalendarDateInfo {
    let date: Date
    let hasCreatedMemos: Bool
    let hasUpdatedMemos: Bool
    let hasDueMemos: Bool
    let memos: [Memo]
}

/// メモの日付タイプ
enum MemoDateType: CaseIterable {
    case created
    case updated
    case due
    
    var color: Color {
        switch self {
        case .created:
            return .green
        case .updated:
            return .blue
        case .due:
            return .red
        }
    }
    
    var displayName: String {
        switch self {
        case .created:
            return "作成日"
        case .updated:
            return "更新日"
        case .due:
            return "期日"
        }
    }
}

// MARK: - Calendar View
struct CalendarView: View {
    let memos: [Memo]
    let onMemoSelected: (Memo) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDate = Date()
    @State private var memosForSelectedDate: [Memo] = []
    @State private var currentMonth = Date()
    @State private var calendarDateInfos: [Date: CalendarDateInfo] = [:]
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // レジェンド表示
                legendView
                
                // カスタムカレンダー
                VStack(spacing: 16) {
                    // 月切り替えヘッダー
                    monthNavigationView
                    
                    // カレンダーグリッド
                    calendarGridView
                }
                .padding()
                
                Divider()
                
                // 選択された日のメモ一覧
                if !memosForSelectedDate.isEmpty {
                    VStack(alignment: .leading) {
                        Text("\(DateFormatter.dayFormatter.string(from: selectedDate))のメモ")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        List(memosForSelectedDate, id: \.id) { memo in
                            CalendarMemoRowView(memo: memo)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    onMemoSelected(memo)
                                }
                        }
                    }
                } else {
                    Spacer()
                    Text("この日にはメモがありません")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
            .navigationTitle("カレンダー")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            updateCalendarData()
            updateMemosForDate(selectedDate)
        }
        .onChange(of: currentMonth) { _, _ in
            updateCalendarData()
        }
    }
    
    // MARK: - View Components
    
    private var legendView: some View {
        HStack(spacing: 20) {
            ForEach(MemoDateType.allCases, id: \.self) { type in
                HStack(spacing: 4) {
                    Circle()
                        .fill(type.color)
                        .frame(width: 8, height: 8)
                    Text(type.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
    
    private var monthNavigationView: some View {
        HStack {
            Button(action: {
                withAnimation {
                    currentMonth = Calendar.current.date(byAdding: .month, value: -1, to: currentMonth) ?? currentMonth
                }
            }) {
                Image(systemName: "chevron.left")
                    .font(.title2)
                    .foregroundColor(.blue)
            }
            
            Spacer()
            
            Text(DateFormatter.monthYearFormatter.string(from: currentMonth))
                .font(.title2)
                .fontWeight(.semibold)
            
            Spacer()
            
            Button(action: {
                withAnimation {
                    currentMonth = Calendar.current.date(byAdding: .month, value: 1, to: currentMonth) ?? currentMonth
                }
            }) {
                Image(systemName: "chevron.right")
                    .font(.title2)
                    .foregroundColor(.blue)
            }
        }
    }
    
    private var calendarGridView: some View {
        let days = generateDaysInMonth()
        let columns = Array(repeating: GridItem(.flexible()), count: 7)
        
        return VStack(spacing: 8) {
            // 曜日ヘッダー
            HStack {
                ForEach(["日", "月", "火", "水", "木", "金", "土"], id: \.self) { dayOfWeek in
                    Text(dayOfWeek)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            
            // 日付グリッド
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(days, id: \.self) { date in
                    if let date = date {
                        CalendarDateView(
                            date: date,
                            isSelected: Calendar.current.isDate(date, inSameDayAs: selectedDate),
                            isCurrentMonth: Calendar.current.isDate(date, equalTo: currentMonth, toGranularity: .month),
                            dateInfo: calendarDateInfos[normalizeDate(date)]
                        )
                        .onTapGesture {
                            selectedDate = date
                            updateMemosForDate(date)
                        }
                    } else {
                        Rectangle()
                            .fill(Color.clear)
                            .frame(height: 40)
                    }
                }
            }
        }
    }
    
    // MARK: - Helper Functions
    
    private func updateMemosForDate(_ date: Date) {
        var calendar = Calendar.current
        calendar.locale = Locale(identifier: "ja_JP")
        memosForSelectedDate = memos.filter { memo in
            calendar.isDate(memo.createdAt, inSameDayAs: date) ||
            calendar.isDate(memo.updatedAt, inSameDayAs: date) ||
            (memo.dueDate != nil && calendar.isDate(memo.dueDate!, inSameDayAs: date))
        }
    }
    
    private func updateCalendarData() {
        DispatchQueue.main.async {
            let calendar = Calendar.current
            self.calendarDateInfos.removeAll()
            
            // 表示される月の範囲を少し広げて、前後の月の一部も含める
            let startOfMonth = calendar.dateInterval(of: .month, for: self.currentMonth)?.start ?? self.currentMonth
            let endOfMonth = calendar.dateInterval(of: .month, for: self.currentMonth)?.end ?? self.currentMonth
            
            // 前月の最後の週と次月の最初の週も含める
            let startDate = calendar.date(byAdding: .day, value: -7, to: startOfMonth) ?? startOfMonth
            let endDate = calendar.date(byAdding: .day, value: 7, to: endOfMonth) ?? endOfMonth
            
            var date = startDate
            while date < endDate {
                let normalizedDate = self.normalizeDate(date)
                let memosForDate = self.memos.filter { memo in
                    calendar.isDate(memo.createdAt, inSameDayAs: date) ||
                    calendar.isDate(memo.updatedAt, inSameDayAs: date) ||
                    (memo.dueDate != nil && calendar.isDate(memo.dueDate!, inSameDayAs: date))
                }
                
                if !memosForDate.isEmpty {
                    let hasCreated = memosForDate.contains { calendar.isDate($0.createdAt, inSameDayAs: date) }
                    let hasUpdated = memosForDate.contains { 
                        calendar.isDate($0.updatedAt, inSameDayAs: date)
                    }
                    let hasDue = memosForDate.contains { memo in
                        memo.dueDate != nil && calendar.isDate(memo.dueDate!, inSameDayAs: date)
                    }
                    
                    self.calendarDateInfos[normalizedDate] = CalendarDateInfo(
                        date: date,
                        hasCreatedMemos: hasCreated,
                        hasUpdatedMemos: hasUpdated,
                        hasDueMemos: hasDue,
                        memos: memosForDate
                    )
                }
                
                date = calendar.date(byAdding: .day, value: 1, to: date) ?? date
            }
        }
    }
    
    private func generateDaysInMonth() -> [Date?] {
        let calendar = Calendar.current
        guard let monthInterval = calendar.dateInterval(of: .month, for: currentMonth) else {
            return []
        }
        
        let firstOfMonth = monthInterval.start
        let firstWeekday = calendar.component(.weekday, from: firstOfMonth)
        let daysInMonth = calendar.range(of: .day, in: .month, for: currentMonth)?.count ?? 0
        
        var days: [Date?] = []
        
        // 前の月の空セルを追加
        for _ in 1..<firstWeekday {
            days.append(nil)
        }
        
        // 当月の日付を追加
        for day in 1...daysInMonth {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: firstOfMonth) {
                days.append(date)
            }
        }
        
        return days
    }
    
    private func normalizeDate(_ date: Date) -> Date {
        let calendar = Calendar.current
        return calendar.startOfDay(for: date)
    }
    
}

// MARK: - Calendar Date View
/// カレンダーの日付セル
struct CalendarDateView: View {
    let date: Date
    let isSelected: Bool
    let isCurrentMonth: Bool
    let dateInfo: CalendarDateInfo?
    
    private var dayText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: date)
    }
    
    private var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }
    
    var body: some View {
        VStack(spacing: 2) {
            // 日付数字
            ZStack {
                Circle()
                    .fill(backgroundColor)
                    .frame(width: 32, height: 32)
                
                Text(dayText)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(textColor)
            }
            
            // メモタイプの丸印
            HStack(spacing: 2) {
                if let dateInfo = dateInfo {
                    if dateInfo.hasCreatedMemos {
                        Circle()
                            .fill(MemoDateType.created.color)
                            .frame(width: 4, height: 4)
                    }
                    if dateInfo.hasUpdatedMemos {
                        Circle()
                            .fill(MemoDateType.updated.color)
                            .frame(width: 4, height: 4)
                    }
                    if dateInfo.hasDueMemos {
                        Circle()
                            .fill(MemoDateType.due.color)
                            .frame(width: 4, height: 4)
                    }
                } else {
                    // 空のスペース確保のため透明な丸を配置
                    Circle()
                        .fill(Color.clear)
                        .frame(width: 4, height: 4)
                }
            }
            .frame(height: 6) // 高さを固定してレイアウトを安定させる
        }
        .frame(height: 40)
    }
    
    private var backgroundColor: Color {
        if isSelected {
            return .blue
        } else if isToday {
            return .blue.opacity(0.2)
        } else {
            return .clear
        }
    }
    
    private var textColor: Color {
        if isSelected {
            return .white
        } else if isToday {
            return .blue
        } else if isCurrentMonth {
            return .primary
        } else {
            return .secondary.opacity(0.5)
        }
    }
}

// MARK: - Calendar Memo Row View
struct CalendarMemoRowView: View {
    let memo: Memo
    
    private var displayTitle: String {
        // memoのtitleが空の場合、1行目から取得
        if memo.title.isEmpty {
            let firstLine = memo.content.components(separatedBy: .newlines).first ?? ""
            if firstLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "無題のメモ"
            }
            // マークダウンの見出し記号（#）を取り除く
            let cleanedLine = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "^#{1,6}\\s*", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            return cleanedLine.isEmpty ? "無題のメモ" : cleanedLine
        }
        return memo.title
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(displayTitle)
                .font(.headline)
                .lineLimit(1)
            
            HStack {
                Text("作成日時: \(DateFormatter.dateTimeFormatterWithWeekday.string(from: memo.createdAt))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if memo.createdAt != memo.updatedAt {
                    Text("更新日時: \(DateFormatter.dateTimeFormatterWithWeekday.string(from: memo.updatedAt))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            if let dueDate = memo.dueDate {
                HStack {
                    Text("期日:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if memo.isOverdue {
                        Text("【期限切れ】")
                            .font(.caption)
                            .foregroundColor(.red)
                            .fontWeight(.medium)
                    } else if memo.isDueToday {
                        Text("【今日】")
                            .font(.caption)
                            .foregroundColor(.orange)
                            .fontWeight(.medium)
                    }
                    
                    Text(DateFormatter.dueDateFormatterWithWeekday.string(from: dueDate))
                        .font(.caption)
                        .foregroundColor(memo.isOverdue ? .red : (memo.isDueToday ? .orange : .secondary))
                    
                    Spacer()
                }
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - DateFormatter Extensions
extension DateFormatter {
    static let monthYearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年M月"
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter
    }()
    
    static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日"
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter
    }()
    
    static let shortFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter
    }()
    
    static let shortFormatterWithWeekday: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d（E）"
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter
    }()
    
    static let dateTimeFormatterWithWeekday: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d（E） HH:mm"
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter
    }()
    
    static let dueDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d HH:mm"
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter
    }()
    
    static let dueDateFormatterWithWeekday: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d（E） HH:mm"
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter
    }()
}

// MARK: - NotificationHistoryView
/// 通知履歴を表示するビュー
struct NotificationHistoryView: View {
    // MARK: - Environment Objects
    @EnvironmentObject private var notificationManager: NotificationManager
    @EnvironmentObject private var memoStore: MemoStore
    
    // MARK: - State Properties
    @Environment(\.dismiss) private var dismiss
    @State private var selectedHistory: NotificationHistory?
    @StateObject private var fcmHistoryManager = NotificationHistoryManager.shared
    @State private var showingEventList = false
    
    var body: some View {
        print("🔔 === NotificationHistoryView 描画開始 ===")
        print("🔔 期日通知履歴数: \(notificationManager.notificationHistory.count)")
        print("🔔 FCM通知履歴数: \(fcmHistoryManager.notifications.count)")
        
        // 期日通知履歴の詳細
        if !notificationManager.notificationHistory.isEmpty {
            print("🔔 === 期日通知履歴詳細 ===")
            for (index, history) in notificationManager.notificationHistory.enumerated() {
                print("🔔 期日[\(index)]: \(history.memoTitle) - タイプ:\(history.notificationType)")
            }
        }
        
        // FCM通知履歴の詳細  
        if !fcmHistoryManager.notifications.isEmpty {
            print("🔔 === FCM通知履歴詳細 ===") 
            for (index, fcm) in fcmHistoryManager.notifications.enumerated() {
                print("🔔 FCM[\(index)]: \(fcm.displayTitle) - FCM:\(fcm.isFromFCM)")
            }
        }
        
        return NavigationView {
            VStack {
                // 統合された通知履歴を表示
                if fcmHistoryManager.notifications.isEmpty {
                    emptyStateView
                } else {
                    combinedNotificationListView
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
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !fcmHistoryManager.notifications.isEmpty {
                        Menu {
                            Button("履歴をクリア", role: .destructive) {
                                fcmHistoryManager.clearHistory()
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "bell.slash")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("通知履歴がありません")
                .font(.title2)
                .fontWeight(.medium)
                .foregroundColor(.primary)
            
            Text("期日の通知が送信されると、こちらに履歴が表示されます")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var notificationListView: some View {
        List {
            ForEach(notificationManager.notificationHistory) { history in
                NotificationHistoryRowView(
                    history: history,
                    onTap: {
                        handleNotificationTap(history)
                    }
                )
            }
        }
    }
    
    /// 期日通知とFCM通知を統合表示するビュー
    private var combinedNotificationListView: some View {
        List {
            // 統合通知セクション
            if !fcmHistoryManager.notifications.isEmpty {
                Section("") {
                    ForEach(fcmHistoryManager.notifications) { fcmNotification in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(fcmNotification.displayTitle)
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                Spacer()
                            }
                            
                            if !fcmNotification.body.isEmpty {
                                Text(fcmNotification.body)
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                    .lineLimit(3)
                            }
                            
                            HStack {
                                Text(DateFormatter.notificationFormatter.string(from: fcmNotification.receivedAt))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                        }
                        .frame(minHeight: 60)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            handleFCMNotificationTap(fcmNotification)
                        }
                    }
                }
            }
            
            // 期日通知セクションは統合通知システムに移行済みのため削除
        }
        .sheet(isPresented: $showingEventList) {
            EventListView()
                .environmentObject(FirebaseService.shared)
        }
    }
    
    private func handleNotificationTap(_ history: NotificationHistory) {
        // 既読にする
        notificationManager.markHistoryAsRead(history.id)
        
        // メモを探す
        if let memo = memoStore.memos.first(where: { $0.id == history.memoId }) {
            print("📋 履歴からメモ遷移: \(memo.displayTitle)")
            
            // 直接メモを設定（NotificationCenter経由ではなく）
            // NotificationCenterを通じてメモ画面への遷移を通知
            NotificationCenter.default.post(
                name: NSNotification.Name("OpenMemoFromNotification"),
                object: nil,
                userInfo: ["memoId": memo.id]
            )
            
            // 通知履歴画面を閉じる
            dismiss()
        }
    }
    
    /// FCM通知のタップ処理
    private func handleFCMNotificationTap(_ fcmNotification: NotificationHistoryEntry) {
        print("📱 FCM通知がタップされました: \(fcmNotification.displayTitle)")
        print("📱 「新しいイベント」含有: \(fcmNotification.containsNewEventText)")
        print("📱 タイトル内容: '\(fcmNotification.title)'")
        print("📱 本文内容: '\(fcmNotification.body)'")
        
        // 期日通知の判定
        let title = fcmNotification.title
        let _ = fcmNotification.body
        let isDeadlineNotification = title.contains("期日になりました") || title.contains("期日が近づいています")
        
        if isDeadlineNotification {
            print("📝 期日通知 - メモページを開く")
            
            // userInfoからmemoIdまたはmemo_idを取得
            if let memoIdString = fcmNotification.userInfo["memoId"] ?? fcmNotification.userInfo["memo_id"],
               let memoId = UUID(uuidString: memoIdString) {
                print("📝 メモID発見: \(memoId)")
                
                // メモページを開く通知を送信
                NotificationCenter.default.post(
                    name: NSNotification.Name("OpenMemoFromNotification"),
                    object: nil,
                    userInfo: ["memoId": memoId, "source": "notification_history_tap"]
                )
                
                // 通知履歴画面を閉じる
                dismiss()
            } else {
                print("⚠️ 期日通知にメモIDが見つかりません")
                print("⚠️ userInfo内容: \(fcmNotification.userInfo)")
            }
        } else if fcmNotification.containsNewEventText {
            print("📅 「新しいイベント」通知 - イベント一覧を表示")
            showingEventList = true
        } else {
            print("ℹ️ その他の通知 - 特別な処理は行わない")
        }
    }
}

// MARK: - DateFormatter Extension
extension DateFormatter {
    static let notificationFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d HH:mm"
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter
    }()
}

// MARK: - NotificationHistoryRowView
/// 通知履歴の行ビュー
struct NotificationHistoryRowView: View {
    let history: NotificationHistory
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        if !history.isRead {
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 8, height: 8)
                        }
                        
                        Text(history.notificationType.displayName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.1))
                            .clipShape(Capsule())
                        
                        Spacer()
                        
                        Text(formatNotificationDate(history.sentAt))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Text(history.memoTitle)
                        .font(.body)
                        .fontWeight(history.isRead ? .regular : .medium)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func formatNotificationDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        var calendar = Calendar.current
        calendar.locale = Locale(identifier: "ja_JP")
        
        if calendar.isDate(date, equalTo: Date(), toGranularity: .day) {
            formatter.dateFormat = "HH:mm"
            return "今日 \(formatter.string(from: date))"
        } else if calendar.isDate(date, equalTo: calendar.date(byAdding: .day, value: -1, to: Date()) ?? Date(), toGranularity: .day) {
            formatter.dateFormat = "HH:mm"
            return "昨日 \(formatter.string(from: date))"
        } else {
            formatter.dateFormat = "M/d HH:mm"
            return formatter.string(from: date)
        }
    }
    
}

// MARK: - FolderSelectionView
/// フォルダ選択ビュー（スワイプアクション用）
struct FolderSelectionView: View {
    let memo: Memo
    let memoStore: MemoStore
    let folderStore: FolderStore
    let onDismiss: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var selectedFolderId: UUID?
    
    var body: some View {
        NavigationView {
            List {
                Section("フォルダを選択") {
                    // すべてフォルダ（フォルダなし）
                    HStack {
                        Image(systemName: "doc.text")
                            .foregroundColor(.gray)
                        Text("すべて")
                        Spacer()
                        if memo.folderId == nil {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedFolderId = nil
                        updateMemoFolder()
                    }
                    
                    // フォルダ一覧
                    ForEach(folderStore.folders) { folder in
                        HStack {
                            Image(systemName: "folder.fill")
                                .foregroundColor(.blue)
                            Text(folder.name)
                            Spacer()
                            if memo.folderId == folder.id {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedFolderId = folder.id
                            updateMemoFolder()
                        }
                    }
                }
            }
            .navigationTitle("フォルダを変更")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("キャンセル") {
                        onDismiss()
                    }
                }
            }
        }
        .onAppear {
            selectedFolderId = memo.folderId
        }
    }
    
    private func updateMemoFolder() {
        var updatedMemo = memo
        updatedMemo.folderId = selectedFolderId
        updatedMemo.updatedAt = Date()
        memoStore.updateMemo(updatedMemo)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            onDismiss()
        }
    }
}

// MARK: - DueDateSettingView
/// 期日設定ビュー（スワイプアクション用）
struct DueDateSettingView: View {
    let memo: Memo
    let memoStore: MemoStore
    let notificationManager: NotificationManager
    let onDismiss: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @Binding var tempDueDate: Date
    @Binding var tempHasPreNotification: Bool
    @Binding var tempPreNotificationMinutes: Int
    
    var body: some View {
        NavigationView {
            Form {
                Section("期日設定") {
                    DatePicker("期日", selection: $tempDueDate, displayedComponents: [.date, .hourAndMinute])
                    
                    Toggle("事前通知", isOn: $tempHasPreNotification)
                    
                    if tempHasPreNotification {
                        Picker("通知タイミング", selection: $tempPreNotificationMinutes) {
                            Text("5分前").tag(5)
                            Text("15分前").tag(15)
                            Text("30分前").tag(30)
                            Text("1時間前").tag(60)
                            Text("2時間前").tag(120)
                            Text("1日前").tag(1440)
                        }
                    }
                }
                
                if memo.dueDate != nil {
                    Section {
                        Button("期日を削除", role: .destructive) {
                            removeDueDate()
                        }
                    }
                }
            }
            .navigationTitle(memo.dueDate != nil ? "期日を変更" : "期日を設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("キャンセル") {
                        onDismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") {
                        saveDueDate()
                    }
                }
            }
        }
    }
    
    private func saveDueDate() {
        var updatedMemo = memo
        updatedMemo.setDueDate(tempDueDate)
        updatedMemo.hasPreNotification = tempHasPreNotification
        updatedMemo.preNotificationMinutes = tempPreNotificationMinutes
        updatedMemo.updatedAt = Date()
        
        memoStore.updateMemo(updatedMemo)
        
        if tempHasPreNotification {
            notificationManager.scheduleNotification(for: updatedMemo)
        }
        
        onDismiss()
    }
    
    private func removeDueDate() {
        var updatedMemo = memo
        updatedMemo.clearDueDate()
        updatedMemo.updatedAt = Date()
        
        memoStore.updateMemo(updatedMemo)
        notificationManager.removeNotifications(for: updatedMemo)
        
        onDismiss()
    }
}

// MARK: - Share Extensions
extension MemoListView {
    /// 共有オプションを表示
    private func showShareOptions(for memo: Memo) {
        // txtファイル用のアクティビティアイテムソースを作成
        let textFileSource = MemoListTextFileActivityItemSource(memo: memo)
        
        // カスタムアクティビティを作成
        let markdownExportActivity = MemoListMarkdownExportActivity(memo: memo)
        let pdfExportActivity = MemoListPDFExportActivity(memo: memo)
        let printActivity = MemoListPrintActivity(memo: memo)
        
        // アクティビティアイテムを準備
        let activityItems: [Any] = [textFileSource]
        let applicationActivities = [markdownExportActivity, pdfExportActivity, printActivity]
        
        let activityViewController = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: applicationActivities
        )
        
        // 不要なアクティビティを除外
        activityViewController.excludedActivityTypes = [.saveToCameraRoll, .addToReadingList]
        
        // iPadの場合はポップオーバーとして表示
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootViewController = window.rootViewController {
            
            if UIDevice.current.userInterfaceIdiom == .pad {
                activityViewController.popoverPresentationController?.sourceView = window
                activityViewController.popoverPresentationController?.sourceRect = CGRect(x: window.bounds.midX, y: window.bounds.midY, width: 0, height: 0)
                activityViewController.popoverPresentationController?.permittedArrowDirections = []
            }
            
            rootViewController.present(activityViewController, animated: true)
        }
    }
}

// MARK: - Share Activity Classes
/// テキストファイル用のアクティビティアイテムソース
class MemoListTextFileActivityItemSource: NSObject, UIActivityItemSource {
    private let memo: Memo
    
    init(memo: Memo) {
        self.memo = memo
        super.init()
    }
    
    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        return memo.content
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        return memo.content
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
        return memo.displayTitle
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?) -> String {
        return "public.plain-text"
    }
}

/// マークダウンエクスポートアクティビティ
class MemoListMarkdownExportActivity: UIActivity {
    private let memo: Memo
    
    init(memo: Memo) {
        self.memo = memo
        super.init()
    }
    
    override var activityType: UIActivity.ActivityType? {
        return UIActivity.ActivityType("jp.edfusion.localmemo.markdownexport")
    }
    
    override var activityTitle: String? {
        return "マークダウンファイル出力"
    }
    
    override var activityImage: UIImage? {
        return UIImage(systemName: "doc.text")
    }
    
    override func canPerform(withActivityItems activityItems: [Any]) -> Bool {
        return !memo.content.isEmpty
    }
    
    override func perform() {
        let fileName = memo.displayTitle
        let cleanFileName = fileName.replacingOccurrences(of: "[^\\w\\s-]", with: "", options: .regularExpression)
        
        let markdownContent = memo.content
        
        if let data = markdownContent.data(using: .utf8) {
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(cleanFileName).md")
            
            do {
                try data.write(to: tempURL)
                
                DispatchQueue.main.async {
                    let documentPicker = UIDocumentPickerViewController(forExporting: [tempURL], asCopy: true)
                    documentPicker.shouldShowFileExtensions = true
                    
                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let window = windowScene.windows.first,
                       let rootViewController = window.rootViewController {
                        rootViewController.present(documentPicker, animated: true)
                    }
                    
                    self.activityDidFinish(true)
                }
            } catch {
                print("Markdownファイルの書き込みに失敗: \(error)")
                self.activityDidFinish(false)
            }
        }
    }
}

/// PDFエクスポートアクティビティ
class MemoListPDFExportActivity: UIActivity {
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
                    self?.activityDidFinish(false)
                    return
                }
                
                let fileName = self.memo.displayTitle
                let cleanFileName = fileName.replacingOccurrences(of: "[^\\w\\s-]", with: "", options: .regularExpression)
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(cleanFileName).pdf")
                
                do {
                    try pdfData.write(to: tempURL)
                    
                    let documentPicker = UIDocumentPickerViewController(forExporting: [tempURL], asCopy: true)
                    documentPicker.shouldShowFileExtensions = true
                    
                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let window = windowScene.windows.first,
                       let rootViewController = window.rootViewController {
                        rootViewController.present(documentPicker, animated: true)
                    }
                    
                    self.activityDidFinish(true)
                } catch {
                    print("PDFファイルの書き込みに失敗: \(error)")
                    self.activityDidFinish(false)
                }
            }
        }
    }
}

/// プリントアクティビティ
class MemoListPrintActivity: UIActivity {
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
        let enableChapterNumbering = AppSettings.shared.isChapterNumberingEnabled
        MarkdownRenderer.generatePDF(from: memo, enableChapterNumbering: enableChapterNumbering) { [weak self] data in
            DispatchQueue.main.async {
                guard let self = self, let pdfData = data else {
                    self?.activityDidFinish(false)
                    return
                }
                
                let printController = UIPrintInteractionController.shared
                printController.printingItem = pdfData
                
                let printInfo = UIPrintInfo(dictionary: nil)
                printInfo.jobName = self.memo.displayTitle
                printInfo.outputType = .general
                printController.printInfo = printInfo
                
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let window = windowScene.windows.first {
                    printController.present(from: CGRect(x: window.bounds.midX, y: window.bounds.midY, width: 0, height: 0), in: window, animated: true) { (controller, completed, error) in
                        self.activityDidFinish(completed)
                    }
                } else {
                    self.activityDidFinish(false)
                }
            }
        }
    }
}

#Preview {
    MemoListView()
}
