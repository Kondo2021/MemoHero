import Foundation
import Combine
import WidgetKit
import CloudKit

// MARK: - Debug Extensions
extension DateFormatter {
    static let debugFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
}

// MARK: - Error Types
enum MemoStoreError: Error, LocalizedError {
    case directoryNotWritable(path: String)
    case arrayOperationFailed(underlyingError: Error)
    case fileOperationFailed(path: String, underlyingError: Error)
    case invalidMemoData(message: String)
    
    var errorDescription: String? {
        switch self {
        case .directoryNotWritable(let path):
            return "ディレクトリに書き込み権限がありません: \(path)"
        case .arrayOperationFailed(let error):
            return "配列操作に失敗しました: \(error.localizedDescription)"
        case .fileOperationFailed(let path, let error):
            return "ファイル操作に失敗しました (\(path)): \(error.localizedDescription)"
        case .invalidMemoData(let message):
            return "無効なメモデータ: \(message)"
        }
    }
}

// MARK: - MemoStore
/// メモの永続化とデータ管理を行うクラス
/// ObservableObject: SwiftUIのデータバインディングに対応
/// JSON形式でローカルファイルに保存し、ウィジェット用にApp Groupsにも共有
class MemoStore: ObservableObject {
    // MARK: - Published Properties
    /// 全メモの配列（SwiftUIで監視される）
    @Published var memos: [Memo] = []
    /// ストアの初期化完了状態
    @Published var isInitialized: Bool = false
    
    // MARK: - Private Properties
    /// ドキュメントディレクトリのURL
    private let documentsDirectory: URL
    /// メモファイルのURL
    private let memosFile: URL
    /// 保存操作のシリアルキュー
    private let saveQueue = DispatchQueue(label: "com.memoapp.save", qos: .userInitiated)
    
    // MARK: - Initializer
    /// MemoStoreの初期化
    /// ファイルからメモを読み込み、マイグレーション処理を実行
    init() {
        let startTime = Date()
        #if DEBUG
        print("==== MemoStore初期化開始 [\(DateFormatter.debugFormatter.string(from: startTime))] ====")
        #endif
        
        // ドキュメントディレクトリの取得（同期）
        guard let docDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            #if DEBUG
            print("❌ FATAL: ドキュメントディレクトリの取得に失敗")
            #endif
            fatalError("ドキュメントディレクトリが取得できません")
        }
        
        documentsDirectory = docDirectory
        memosFile = documentsDirectory.appendingPathComponent("memos.json")
        
        // 重いファイルI/O処理は非同期で実行（メインスレッドブロック回避）
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            do {
                // ドキュメントディレクトリの作成を確認
                try self.ensureDocumentsDirectoryExists()
                try self.loadMemos()
                self.migrateOldMemos() // 既存メモをマイグレーション
                
                #if DEBUG
                print("MemoStore - 読み込み完了、メモ数: \(self.memos.count)")
                
                // 詳細ログ出力はバックグラウンドで実行（デバッグ時のみ）
                DispatchQueue.global(qos: .utility).async {
                    for (index, memo) in self.memos.enumerated() {
                        print("  メモ[\(index)] - ID: \(memo.id.uuidString.prefix(8)), content: '\(memo.content.prefix(30))', folder: \(memo.folderId?.uuidString.prefix(8) ?? "nil")")
                    }
                    print("==== MemoStore初期化完了 [\(DateFormatter.debugFormatter.string(from: Date()))] ====\n")
                }
                #endif
                
                // 初期化完了をメインスレッドで通知（UI更新のため）
                DispatchQueue.main.async {
                    let endTime = Date()
                    #if DEBUG
                    print("MemoStore - 初期化完了フラグ設定 [\(DateFormatter.debugFormatter.string(from: endTime))] (所要時間: \(String(format: "%.3f", endTime.timeIntervalSince(startTime)))秒)")
                    #endif
                    self.isInitialized = true
                    
                    // ウィジェットからのチェックリスト更新監視を開始
                    self.startMonitoringWidgetUpdates()
                }
                
            } catch {
                print("❌ FATAL ERROR: MemoStore初期化中に致命的エラーが発生: \(error)")
                
                // 緊急時の初期化（メインスレッドで）
                DispatchQueue.main.async {
                    #if DEBUG
                    print("🚨 緊急初期化モードに移行します")
                    #endif
                    self.memos = []
                    
                    // 遅延初期化完了通知（エラー状態でも最低限の機能を提供）
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        #if DEBUG
                        print("🚨 緊急初期化完了 - エラー状態ですが最低限の機能は利用可能")
                        #endif
                        self.isInitialized = true
                    }
                }
            }
        }
    }
    
    // MARK: - CRUD Operations
    /// 新しいメモを追加
    /// - Parameter memo: 追加するメモ（デフォルトで空のメモを作成）
    func addMemo(_ memo: Memo = Memo()) {
        let timestamp = DateFormatter.debugFormatter.string(from: Date())
        print("🟢 MemoStore.addMemo() 呼び出し [\(timestamp)] - isInitialized: \(isInitialized)")
        print("   追加メモ ID: \(memo.id.uuidString.prefix(8)), content: '\(memo.content.prefix(20))', folder: \(memo.folderId?.uuidString.prefix(8) ?? "nil")")
        
        do {
            guard isInitialized else {
                print("❌ MemoStore - 初期化未完了のため追加をスキップ: \(memo.id.uuidString.prefix(8))")
                return
            }
            
            print("   現在のメモ数: \(memos.count) → \(memos.count + 1)")
            
            // メモ配列への挿入を安全に実行
            try safeArrayOperation {
                self.memos.insert(memo, at: 0)  // 最新のメモを先頭に挿入
            }
            print("   メモ配列に挿入完了")
            
            saveMemos()
            saveToAppGroups()
            
            // WidgetCenter操作の例外処理
            try safeWidgetOperation {
                WidgetCenter.shared.reloadAllTimelines()
            }
            
            print("✅ MemoStore.addMemo() 完了 [\(DateFormatter.debugFormatter.string(from: Date()))]")
            
        } catch {
            print("❌ ERROR: addMemo()中にエラーが発生 [\(DateFormatter.debugFormatter.string(from: Date()))]")
            print("   エラー詳細: \(error)")
            print("   メモ ID: \(memo.id.uuidString.prefix(8))")
            
            // エラー発生時もメモ配列の整合性を確認
            print("   現在のメモ配列状態 - 要素数: \(memos.count)")
        }
    }
    
    /// 既存メモを更新
    /// - Parameter memo: 更新するメモ
    func updateMemo(_ memo: Memo) {
        let timestamp = DateFormatter.debugFormatter.string(from: Date())
        print("🔄 MemoStore.updateMemo() 呼び出し [\(timestamp)] - isInitialized: \(isInitialized)")
        print("   更新メモ ID: \(memo.id.uuidString.prefix(8)), content: '\(memo.content.prefix(20))', folder: \(memo.folderId?.uuidString.prefix(8) ?? "nil")")
        
        do {
            guard isInitialized else {
                print("❌ MemoStore - 初期化未完了のため更新をスキップ: \(memo.id.uuidString.prefix(8))")
                return
            }
            
            if let index = memos.firstIndex(where: { $0.id == memo.id }) {
                print("   メモが配列内で見つかりました (インデックス: \(index))")
                let oldContent = memos[index].content.prefix(20)
                
                // 配列操作を安全に実行
                try safeArrayOperation {
                    // メモ内容を更新
                    self.memos[index] = memo
                    print("   メモ内容更新: '\(oldContent)' → '\(memo.content.prefix(20))'")
                    
                    // 既存メモが先頭でない場合のみ移動処理を実行
                    if index > 0 && index < self.memos.count {
                        print("   メモを先頭に移動開始: インデックス \(index) → 0")
                        
                        // IndexSetを使った移動は起動直後に不安定なため、手動で安全に移動
                        let updatedMemo = self.memos[index]
                        self.memos.remove(at: index)
                        self.memos.insert(updatedMemo, at: 0)
                        
                        print("   メモを先頭に移動完了 (手動移動)")
                    } else if index == 0 {
                        print("   メモは既に先頭位置のため移動をスキップ")
                    } else {
                        print("   無効なインデックス(\(index))のため移動をスキップ")
                    }
                }
                
                saveMemos()
                saveToAppGroups()
                
                // WidgetCenter操作の例外処理
                try safeWidgetOperation {
                    WidgetCenter.shared.reloadAllTimelines()
                }
                
                print("✅ MemoStore.updateMemo() 完了 [\(DateFormatter.debugFormatter.string(from: Date()))]")
            } else {
                print("❌ 更新対象のメモが見つかりません: \(memo.id.uuidString.prefix(8))")
                print("   現在の配列内メモ数: \(memos.count)")
                for (i, existingMemo) in memos.enumerated() {
                    print("     [\(i)] ID: \(existingMemo.id.uuidString.prefix(8))")
                }
            }
            
        } catch {
            print("❌ ERROR: updateMemo()中にエラーが発生 [\(DateFormatter.debugFormatter.string(from: Date()))]")
            print("   エラー詳細: \(error)")
            print("   メモ ID: \(memo.id.uuidString.prefix(8))")
            
            // エラー発生時の配列状態確認
            print("   現在のメモ配列状態 - 要素数: \(memos.count)")
        }
    }
    
    /// 指定メモを削除
    /// - Parameter memo: 削除するメモ
    func deleteMemo(_ memo: Memo) {
        memos.removeAll { $0.id == memo.id }
        saveMemos()
        saveToAppGroups()
        WidgetCenter.shared.reloadAllTimelines()
        
        // 未使用画像をクリーンアップ
        cleanupUnusedImages()
    }
    
    /// 指定インデックスのメモを削除
    /// - Parameter offsets: 削除するメモのインデックス
    func deleteMemos(at offsets: IndexSet) {
        memos.remove(atOffsets: offsets)
        saveMemos()
        saveToAppGroups()
        WidgetCenter.shared.reloadAllTimelines()
        
        // 未使用画像をクリーンアップ
        cleanupUnusedImages()
    }
    
    // MARK: - Folder Operations
    /// メモを指定フォルダに移動
    /// - Parameters:
    ///   - memo: 移動するメモ
    ///   - folderId: 移動先フォルダID（nilの場合はデフォルトフォルダ）
    func moveMemo(_ memo: Memo, to folderId: UUID?) {
        let timestamp = DateFormatter.debugFormatter.string(from: Date())
        print("📁 MemoStore.moveMemo() 呼び出し [\(timestamp)] - isInitialized: \(isInitialized)")
        print("   移動メモ ID: \(memo.id.uuidString.prefix(8))")
        print("   移動元フォルダ: \(memo.folderId?.uuidString.prefix(8) ?? "nil")")
        print("   移動先フォルダ: \(folderId?.uuidString.prefix(8) ?? "nil")")
        
        guard isInitialized else {
            print("❌ MemoStore - 初期化未完了のためフォルダ移動をスキップ: \(memo.id.uuidString.prefix(8))")
            return
        }
        
        if let index = memos.firstIndex(where: { $0.id == memo.id }) {
            print("   メモが配列内で見つかりました (インデックス: \(index))")
            let oldFolderId = memos[index].folderId
            memos[index].moveToFolder(folderId)
            print("   フォルダ移動完了: \(oldFolderId?.uuidString.prefix(8) ?? "nil") → \(folderId?.uuidString.prefix(8) ?? "nil")")
            
            saveMemos()
            saveToAppGroups()
            WidgetCenter.shared.reloadAllTimelines()
            
            print("✅ MemoStore.moveMemo() 完了 [\(DateFormatter.debugFormatter.string(from: Date()))]")
        } else {
            print("❌ 移動対象のメモが見つかりません: \(memo.id.uuidString.prefix(8))")
        }
    }
    
    /// メモのピン留め状態を切り替え
    /// - Parameter memo: ピン留めを切り替えるメモ
    func togglePin(_ memo: Memo) {
        if let index = memos.firstIndex(where: { $0.id == memo.id }) {
            memos[index].togglePin()
            saveMemos()
            saveToAppGroups()
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
    
    /// 指定フォルダ内のメモを取得
    /// - Parameter folderId: フォルダID（nilの場合はデフォルトフォルダ）
    /// - Returns: フォルダ内のメモ配列
    func memosInFolder(_ folderId: UUID?) -> [Memo] {
        return memos.filter { $0.folderId == folderId }
    }
    
    /// メモを複製
    /// - Parameter memo: 複製するメモ
    func duplicateMemo(_ memo: Memo) {
        let timestamp = DateFormatter.debugFormatter.string(from: Date())
        print("📋 MemoStore.duplicateMemo() 呼び出し [\(timestamp)] - isInitialized: \(isInitialized)")
        
        // ストアが初期化されていない場合は処理をスキップ
        guard isInitialized else {
            print("❌ MemoStore初期化未完了のため複製をスキップ")
            return
        }
        
        // 新しいメモを作成（IDは自動生成される）
        var duplicatedMemo = Memo(
            content: memo.content,
            folderId: memo.folderId
        )
        
        // 重複しないタイトルを生成
        let newTitle = generateUniqueTitle(basedOn: duplicatedMemo.displayTitle)
        
        // コンテンツの最初の行を新しいタイトルに変更
        if !duplicatedMemo.content.isEmpty {
            let lines = duplicatedMemo.content.components(separatedBy: .newlines)
            if let firstLine = lines.first, !firstLine.isEmpty {
                var newLines = [newTitle]
                if lines.count > 1 {
                    newLines.append(contentsOf: lines.dropFirst())
                }
                duplicatedMemo.content = newLines.joined(separator: "\n")
            } else {
                // 最初の行が空の場合は、新しいタイトルを先頭に追加
                duplicatedMemo.content = newTitle + "\n" + duplicatedMemo.content
            }
        } else {
            // コンテンツが空の場合は、新しいタイトルをコンテンツとして設定
            duplicatedMemo.content = newTitle
        }
        
        memos.insert(duplicatedMemo, at: 0)  // 先頭に追加
        
        saveMemos()
        saveToAppGroups()
        WidgetCenter.shared.reloadAllTimelines()
        
        print("✅ MemoStore.duplicateMemo() 完了 [\(DateFormatter.debugFormatter.string(from: Date()))]")
    }
    
    /// 重複しないタイトルを生成
    /// - Parameter baseTitle: ベースとなるタイトル
    /// - Returns: 重複しないタイトル
    private func generateUniqueTitle(basedOn baseTitle: String) -> String {
        // 既存のタイトル一覧を取得（displayTitleを使用）
        let existingTitles = Set(memos.map { $0.displayTitle })
        
        // ベースタイトルに(コピー)を前に付けたタイトル
        let copyTitle = "(コピー)\(baseTitle)"
        
        // そのタイトルが重複していなければそのまま返す
        if !existingTitles.contains(copyTitle) {
            return copyTitle
        }
        
        // 重複している場合は連番を付けて重複しないタイトルを探す
        var counter = 2
        while true {
            let numberedTitle = "(コピー\(counter))\(baseTitle)"
            if !existingTitles.contains(numberedTitle) {
                return numberedTitle
            }
            counter += 1
        }
    }
    
    /// 削除されたフォルダ内のメモをデフォルトフォルダに移動
    /// - Parameter folderId: 削除されたフォルダのID
    func moveMemosFromDeletedFolder(_ folderId: UUID) {
        for i in 0..<memos.count {
            if memos[i].folderId == folderId {
                memos[i].moveToFolder(nil)  // デフォルトフォルダに移動
            }
        }
        saveMemos()
        saveToAppGroups()
        WidgetCenter.shared.reloadAllTimelines()
    }
    
    // MARK: - Private Persistence Methods
    /// メモ配列をJSONファイルに保存
    private func saveMemos() {
        let timestamp = DateFormatter.debugFormatter.string(from: Date())
        print("💾 MemoStore.saveMemos() 開始 [\(timestamp)] - メモ数: \(memos.count)")
        
        saveQueue.async { [weak self] in
            guard let self = self else {
                print("❌ self が nil のため保存をスキップ")
                return
            }
            
            let saveStartTime = Date()
            print("💾 ファイル保存開始 [\(DateFormatter.debugFormatter.string(from: saveStartTime))] - スレッド: \(Thread.current)")
            
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = .prettyPrinted
                let data = try encoder.encode(self.memos)
                
                print("   JSON エンコード完了 - データサイズ: \(data.count) bytes")
                print("   保存先: \(self.memosFile.path)")
                print("   ディレクトリ存在: \(FileManager.default.fileExists(atPath: self.documentsDirectory.path))")
                
                try data.write(to: self.memosFile)
                
                let saveEndTime = Date()
                print("✅ MemoStore - 保存成功 [\(DateFormatter.debugFormatter.string(from: saveEndTime))] (所要時間: \(String(format: "%.3f", saveEndTime.timeIntervalSince(saveStartTime)))秒)")
                print("   保存したメモ数: \(self.memos.count)")
                
                // 保存後の検証
                if FileManager.default.fileExists(atPath: self.memosFile.path) {
                    let fileSize = try FileManager.default.attributesOfItem(atPath: self.memosFile.path)[.size] as? UInt64 ?? 0
                    print("   保存ファイル確認 - サイズ: \(fileSize) bytes")
                } else {
                    print("❌ 保存後にファイルが見つかりません")
                }
                
                // ウィジェット用にメモデータを保存し、強制更新
                DispatchQueue.main.async {
                    print("🔄 MemoStore: ウィジェットデータ更新を実行")
                    WidgetDataManager.shared.saveAllMemos(self.memos)
                    WidgetCenter.shared.reloadAllTimelines()
                    print("🔄 MemoStore: ウィジェット強制リロード完了")
                }
                
            } catch {
                print("❌ メモの保存に失敗しました [\(DateFormatter.debugFormatter.string(from: Date()))]")
                print("   エラー: \(error)")
                print("   ファイルパス: \(self.memosFile.path)")
                print("   ディレクトリ存在: \(FileManager.default.fileExists(atPath: self.documentsDirectory.path))")
                print("   ディレクトリ書き込み権限: \(FileManager.default.isWritableFile(atPath: self.documentsDirectory.path))")
            }
        }
    }
    
    /// JSONファイルからメモ配列を読み込み
    private func loadMemos() throws {
        print("loadMemos開始 - ファイル存在確認: \(FileManager.default.fileExists(atPath: memosFile.path))")
        
        do {
            // ファイルが存在しない場合は空配列で初期化
            guard FileManager.default.fileExists(atPath: memosFile.path) else {
                print("loadMemos - ファイルが存在しないため空配列で初期化")
                DispatchQueue.main.async {
                    self.memos = []
                }
                return
            }
            
            let data = try Data(contentsOf: memosFile)
            print("loadMemos - ファイルサイズ: \(data.count) bytes")
            
            // 空ファイルの場合の処理
            if data.isEmpty {
                print("loadMemos - 空ファイルのため空配列で初期化")
                DispatchQueue.main.async {
                    self.memos = []
                }
                return
            }
            
            // JSONデコード
            let decoder = JSONDecoder()
            let loadedMemos = try decoder.decode([Memo].self, from: data)
            print("loadMemos成功 - デコードしたメモ数: \(loadedMemos.count)")
            
            // メインスレッドでUI更新
            DispatchQueue.main.async {
                self.memos = loadedMemos
            }
            
            // デコード後の検証
            for (index, memo) in loadedMemos.enumerated() {
                if memo.id.uuidString.isEmpty {
                    print("⚠️ 無効なメモが検出されました (インデックス: \(index))")
                }
            }
            
        } catch let decodingError as DecodingError {
            print("❌ JSONデコードエラー: \(decodingError)")
            print("   デコードエラー詳細:")
            switch decodingError {
            case .dataCorrupted(let context):
                print("     データ破損: \(context.debugDescription)")
            case .keyNotFound(let key, let context):
                print("     キーが見つかりません: \(key), context: \(context.debugDescription)")
            case .typeMismatch(let type, let context):
                print("     型の不一致: \(type), context: \(context.debugDescription)")
            case .valueNotFound(let type, let context):
                print("     値が見つかりません: \(type), context: \(context.debugDescription)")
            @unknown default:
                print("     不明なデコードエラー")
            }
            
            // 破損したファイルをバックアップして初期化
            try backupCorruptedFile()
            memos = []
            
        } catch {
            print("❌ ファイル読み込みエラー: \(error)")
            throw MemoStoreError.fileOperationFailed(path: memosFile.path, underlyingError: error)
        }
    }
    
    /// 破損したファイルをバックアップ
    private func backupCorruptedFile() throws {
        let backupPath = memosFile.appendingPathExtension("corrupted.\(Int(Date().timeIntervalSince1970))")
        do {
            try FileManager.default.copyItem(at: memosFile, to: backupPath)
            print("📁 破損ファイルをバックアップしました: \(backupPath.path)")
        } catch {
            print("⚠️ バックアップに失敗しましたが続行します: \(error)")
        }
    }
    
    /// ドキュメントディレクトリの存在確認と作成
    private func ensureDocumentsDirectoryExists() throws {
        do {
            try FileManager.default.createDirectory(at: documentsDirectory, withIntermediateDirectories: true, attributes: nil)
            print("MemoStore - ドキュメントディレクトリ確認完了: \(documentsDirectory.path)")
            
            // 権限確認
            let isWritable = FileManager.default.isWritableFile(atPath: documentsDirectory.path)
            print("MemoStore - ディレクトリ書き込み権限: \(isWritable)")
            
            if !isWritable {
                throw MemoStoreError.directoryNotWritable(path: documentsDirectory.path)
            }
            
        } catch {
            print("❌ MemoStore - ドキュメントディレクトリ作成エラー: \(error)")
            throw error
        }
    }
    
    /// 配列操作の安全な実行
    private func safeArrayOperation(_ operation: () throws -> Void) throws {
        do {
            try operation()
        } catch {
            print("❌ 配列操作中にエラーが発生: \(error)")
            throw MemoStoreError.arrayOperationFailed(underlyingError: error)
        }
    }
    
    /// WidgetCenter操作の安全な実行
    private func safeWidgetOperation(_ operation: () throws -> Void) throws {
        do {
            try operation()
        } catch {
            print("⚠️ WidgetCenter操作中にエラーが発生（継続可能）: \(error)")
            // WidgetCenterのエラーはアプリの動作に影響しないため、ログ出力のみ
        }
    }
    
    /// 既存メモのマイグレーション処理
    /// 新しいプロパティのデフォルト値は既にMemoのinitで設定済みのため、特別な処理は不要
    private func migrateOldMemos() {
        print("migrateOldMemos - マイグレーション開始")
        
        // メモ配列の整合性チェック
        var needsSave = false
        var invalidMemoIndices: [Int] = []
        
        for (index, memo) in memos.enumerated() {
            // UUIDの検証
            if memo.id.uuidString.isEmpty {
                print("⚠️ 無効なUUIDを持つメモを発見 (インデックス: \(index))")
                invalidMemoIndices.append(index)
                continue
            }
            
            // 日付の検証
            if memo.createdAt > Date() {
                print("⚠️ 未来の作成日時を持つメモを発見 (ID: \(memo.id.uuidString.prefix(8)))")
                needsSave = true
            }
            
            if memo.updatedAt < memo.createdAt {
                print("⚠️ 更新日時が作成日時より前のメモを発見 (ID: \(memo.id.uuidString.prefix(8)))")
                needsSave = true
            }
        }
        
        // 無効なメモを削除
        if !invalidMemoIndices.isEmpty {
            print("🗑️ \(invalidMemoIndices.count)個の無効なメモを削除します")
            for index in invalidMemoIndices.reversed() {
                memos.remove(at: index)
            }
            needsSave = true
        }
        
        // 必要に応じて保存
        if needsSave {
            print("💾 マイグレーション後のデータを保存します")
            saveMemos()
        }
        
        print("✅ migrateOldMemos - マイグレーション完了")
    }
    
    // MARK: - App Groups Integration
    /// ウィジェット用にApp Groupsにデータを保存
    /// 最新の3件のメモを共有コンテナに保存
    private func saveToAppGroups() {
        // WidgetDataManagerを使用してメモをウィジェットと共有
        WidgetDataManager.shared.saveAllMemos(memos)
        print("📱 saveToAppGroups: WidgetDataManagerを使用してメモを共有")
        
        /*
        // App Groups設定完了後に以下のコードを使用:
        guard let sharedContainer = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.YOUR_ACTUAL_GROUP_ID") else {
            print("App Groups コンテナにアクセスできません")
            return
        }
        
        let sharedMemoFile = sharedContainer.appendingPathComponent("shared_memos.json")
        
        do {
            // 最新の3件のメモを取得
            let recentMemos = Array(memos.prefix(3))
            let sharedData = SharedMemoData(memos: recentMemos)
            let data = try JSONEncoder().encode(sharedData)
            try data.write(to: sharedMemoFile)
        } catch {
            print("App Groups へのデータ保存に失敗: \(error)")
        }
        */
    }
    
    // MARK: - Widget Updates Monitoring
    /// ウィジェットからのチェックリスト更新を監視
    private func startMonitoringWidgetUpdates() {
        print("🔄 ウィジェット更新監視を開始")
        
        // 定期的にApp Groupsのチェックリスト更新をチェック
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkForWidgetChecklistUpdates()
        }
    }
    
    /// ウィジェットからのチェックリスト更新をチェック
    private func checkForWidgetChecklistUpdates() {
        let appGroupIdentifier = "group.memohero.edfusion.jp"
        
        guard let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            return
        }
        
        // チェックリスト更新の確認
        if let updateInfo = sharedDefaults.object(forKey: "checklist_update") as? [String: Any],
           let memoIdString = updateInfo["memoId"] as? String,
           let updatedContent = updateInfo["content"] as? String,
           let timestamp = updateInfo["timestamp"] as? TimeInterval,
           let memoId = UUID(uuidString: memoIdString) {
            
            // 既に処理した更新かチェック（重複処理防止）
            let lastProcessedKey = "last_processed_checklist_update"
            let lastProcessedTimestamp = sharedDefaults.double(forKey: lastProcessedKey)
            
            if timestamp > lastProcessedTimestamp {
                // 新しい更新を処理
                updateMemoFromWidget(memoId: memoId, content: updatedContent)
                
                // 処理済みタイムスタンプを更新
                sharedDefaults.set(timestamp, forKey: lastProcessedKey)
                sharedDefaults.synchronize()
                
                print("✅ ウィジェットからのチェックリスト更新を適用: \(memoId.uuidString.prefix(8))")
            }
        }
    }
    
    /// ウィジェットからのメモ更新を適用
    /// - Parameters:
    ///   - memoId: 更新するメモのID
    ///   - content: 新しいメモ内容
    private func updateMemoFromWidget(memoId: UUID, content: String) {
        guard let memoIndex = memos.firstIndex(where: { $0.id == memoId }) else {
            print("❌ 更新対象のメモが見つかりません: \(memoId.uuidString.prefix(8))")
            return
        }
        
        // メモの内容を更新
        memos[memoIndex].content = content
        memos[memoIndex].updatedAt = Date()
        
        // 変更を保存
        saveMemos()
        
        print("📝 メモを更新しました: \(memoId.uuidString.prefix(8))")
    }
    
    /// IDでメモを取得
    /// - Parameter id: メモのID
    /// - Returns: 見つかったメモ、または nil
    func memo(withId id: UUID) -> Memo? {
        return memos.first { $0.id == id }
    }
    
    // MARK: - iCloud Backup Methods
    /// メモをiCloudにバックアップ
    func backupToiCloud(comment: String = "") async throws {
        let timestamp = DateFormatter.debugFormatter.string(from: Date())
        print("☁️ MemoStore.backupToiCloud() 開始 [\(timestamp)]")
        
        try await iCloudBackupManager.shared.backupMemos(memos, comment: comment)
        
        print("✅ iCloudバックアップ完了 [\(DateFormatter.debugFormatter.string(from: Date()))]")
    }
    
    /// iCloudからメモを復元（最新のバックアップから）
    func restoreFromiCloud() async throws {
        let timestamp = DateFormatter.debugFormatter.string(from: Date())
        print("☁️ MemoStore.restoreFromiCloud() 開始 [\(timestamp)]")
        
        let restoredMemos = try await iCloudBackupManager.shared.restoreLatestBackup()
        
        // メインスレッドでメモを更新
        await MainActor.run {
            self.memos = restoredMemos
            self.saveMemos()
            self.saveToAppGroups()
            WidgetCenter.shared.reloadAllTimelines()
        }
        
        print("✅ iCloud復元完了: \(restoredMemos.count)件のメモ [\(DateFormatter.debugFormatter.string(from: Date()))]")
    }
    
    /// メモを指定された配列で完全に置き換える
    func replaceMemos(with newMemos: [Memo]) async {
        let timestamp = DateFormatter.debugFormatter.string(from: Date())
        print("🔄 MemoStore.replaceMemos() 開始: \(newMemos.count)件のメモで置換 [\(timestamp)]")
        
        await MainActor.run {
            self.memos = newMemos
            self.saveMemos()
            self.saveToAppGroups()
            WidgetCenter.shared.reloadAllTimelines()
        }
        
        print("✅ メモ置換完了: \(newMemos.count)件のメモ [\(DateFormatter.debugFormatter.string(from: Date()))]")
    }
    
    // MARK: - Image Management
    /// 未使用画像をクリーンアップ
    private func cleanupUnusedImages() {
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("❌ ドキュメントディレクトリが取得できません")
            return
        }
        
        let imagesDirectory = documentsDirectory.appendingPathComponent("MemoImages")
        
        // 画像ディレクトリが存在しない場合は何もしない
        guard FileManager.default.fileExists(atPath: imagesDirectory.path) else {
            return
        }
        
        do {
            // 画像ディレクトリ内のすべてのファイルを取得
            let imageFiles = try FileManager.default.contentsOfDirectory(at: imagesDirectory, includingPropertiesForKeys: nil)
            
            // すべてのメモの内容から画像参照を抽出
            let usedImages = Set(extractImageReferencesFromMemos())
            
            var deletedCount = 0
            for imageFile in imageFiles {
                let filename = imageFile.lastPathComponent
                
                // 使用されていない画像ファイルを削除
                if !usedImages.contains(filename) {
                    do {
                        try FileManager.default.removeItem(at: imageFile)
                        deletedCount += 1
                        print("🗑️ 未使用画像を削除: \(filename)")
                    } catch {
                        print("❌ 画像削除に失敗: \(filename) - \(error)")
                    }
                }
            }
            
            print("✅ 画像クリーンアップ完了: \(deletedCount)個のファイルを削除")
            
        } catch {
            print("❌ 画像クリーンアップ中にエラーが発生: \(error)")
        }
    }
    
    /// すべてのメモから画像参照を抽出
    private func extractImageReferencesFromMemos() -> [String] {
        var imageReferences: [String] = []
        
        let imagePattern = #"!\[([^\]]*)\]\(([^)]+)\)"#
        
        for memo in memos {
            do {
                let regex = try NSRegularExpression(pattern: imagePattern)
                let matches = regex.matches(in: memo.content, range: NSRange(memo.content.startIndex..., in: memo.content))
                
                for match in matches {
                    if let urlRange = Range(match.range(at: 2), in: memo.content) {
                        let imageURL = String(memo.content[urlRange])
                        imageReferences.append(imageURL)
                    }
                }
            } catch {
                print("❌ 画像参照の抽出に失敗: \(error)")
            }
        }
        
        return imageReferences
    }
}

// MARK: - SharedMemoData
/// ウィジェットとの共有用データ構造
/// App Groupsで共有されるメモデータとメタ情報を含む
struct SharedMemoData: Codable {
    /// 共有するメモ配列
    let memos: [Memo]
    /// 最終更新日時
    let lastUpdated: Date
    
    /// 初期化
    /// - Parameter memos: 共有するメモ配列
    init(memos: [Memo]) {
        self.memos = memos
        self.lastUpdated = Date()
    }
}