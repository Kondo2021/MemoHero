import Foundation
import Combine

// MARK: - Error Types
enum FolderStoreError: Error, LocalizedError {
    case directoryNotWritable(path: String)
    case folderOperationFailed(underlyingError: Error)
    case invalidFolderData(message: String)
    
    var errorDescription: String? {
        switch self {
        case .directoryNotWritable(let path):
            return "ディレクトリに書き込み権限がありません: \(path)"
        case .folderOperationFailed(let error):
            return "フォルダ操作に失敗しました: \(error.localizedDescription)"
        case .invalidFolderData(let message):
            return "無効なフォルダデータ: \(message)"
        }
    }
}

// MARK: - FolderStore
/// フォルダの永続化とデータ管理を行うクラス
/// ObservableObject: SwiftUIのデータバインディングに対応
/// JSON形式でローカルファイルに保存し、フォルダとメモの関連付けを管理
class FolderStore: ObservableObject {
    // MARK: - Published Properties
    /// 全フォルダの配列（SwiftUIで監視される）
    @Published var folders: [Folder] = []
    /// ストアの初期化完了状態
    @Published var isInitialized: Bool = false
    
    // MARK: - Private Properties
    /// ドキュメントディレクトリのURL
    private let documentsDirectory: URL
    /// フォルダファイルのURL
    private let foldersFile: URL
    /// 保存操作のシリアルキュー
    private let saveQueue = DispatchQueue(label: "com.memoapp.folder-save", qos: .userInitiated)
    
    // MARK: - Initializer
    /// FolderStoreの初期化
    /// ファイルからフォルダを読み込み、存在しない場合はデフォルトフォルダを作成
    init() {
        let startTime = Date()
        print("==== FolderStore初期化開始 [\(DateFormatter.debugFormatter.string(from: startTime))] ====")
        
        // ドキュメントディレクトリの取得（同期）
        guard let docDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("❌ FATAL: FolderStore - ドキュメントディレクトリの取得に失敗")
            fatalError("FolderStore: ドキュメントディレクトリが取得できません")
        }
        
        documentsDirectory = docDirectory
        foldersFile = documentsDirectory.appendingPathComponent("folders.json")
        print("FolderStore - ファイルパス: \(foldersFile.path)")
        print("FolderStore - ドキュメントディレクトリ: \(documentsDirectory.path)")
        
        // 重いファイルI/O処理は非同期で実行（メインスレッドブロック回避）
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            // ドキュメントディレクトリの作成を確認
            print("FolderStore - ensureDocumentsDirectoryExists開始")
            self.ensureDocumentsDirectoryExists()
            print("FolderStore - ensureDocumentsDirectoryExists完了")
            
            print("FolderStore - loadFolders開始")
            self.loadFolders()
            print("FolderStore - loadFolders完了")
            
            print("FolderStore - 読み込み完了、フォルダ数: \(self.folders.count)")
            
            // 詳細ログ出力はバックグラウンドで実行（メインスレッドをブロックしないため）
            DispatchQueue.global(qos: .utility).async {
                for (index, folder) in self.folders.enumerated() {
                    print("  フォルダ[\(index)] - ID: \(folder.id.uuidString.prefix(8)), name: '\(folder.name)'")
                }
                print("==== FolderStore初期化完了 [\(DateFormatter.debugFormatter.string(from: Date()))] ====\n")
            }
            
            // 初期化完了をメインスレッドで通知（UI更新のため）
            DispatchQueue.main.async {
                let endTime = Date()
                print("FolderStore - 初期化完了フラグ設定 [\(DateFormatter.debugFormatter.string(from: endTime))] (所要時間: \(String(format: "%.3f", endTime.timeIntervalSince(startTime)))秒)")
                self.isInitialized = true
            }
        }
    }
    
    // MARK: - CRUD Operations
    /// 新しいフォルダを追加
    /// - Parameter folder: 追加するフォルダ（デフォルトで空のフォルダを作成）
    func addFolder(_ folder: Folder = Folder()) {
        let timestamp = DateFormatter.debugFormatter.string(from: Date())
        print("🟢 FolderStore.addFolder() 呼び出し [\(timestamp)] - isInitialized: \(isInitialized)")
        print("   追加フォルダ ID: \(folder.id.uuidString.prefix(8)), name: '\(folder.name)'")
        
        guard isInitialized else {
            print("❌ FolderStore - 初期化未完了のため追加をスキップ: \(folder.id.uuidString.prefix(8))")
            return
        }
        
        print("   現在のフォルダ数: \(folders.count) → \(folders.count + 1)")
        folders.append(folder)
        print("   フォルダ配列に追加完了")
        
        saveFolders()
        print("✅ FolderStore.addFolder() 完了 [\(DateFormatter.debugFormatter.string(from: Date()))]")
    }
    
    /// 既存フォルダを更新
    /// - Parameter folder: 更新するフォルダ
    func updateFolder(_ folder: Folder) {
        let timestamp = DateFormatter.debugFormatter.string(from: Date())
        print("🔄 FolderStore.updateFolder() 呼び出し [\(timestamp)] - isInitialized: \(isInitialized)")
        print("   更新フォルダ ID: \(folder.id.uuidString.prefix(8)), name: '\(folder.name)'")
        
        guard isInitialized else {
            print("❌ FolderStore - 初期化未完了のため更新をスキップ: \(folder.id.uuidString.prefix(8))")
            return
        }
        
        if let index = folders.firstIndex(where: { $0.id == folder.id }) {
            print("   フォルダが配列内で見つかりました (インデックス: \(index))")
            let oldName = folders[index].name
            folders[index] = folder
            print("   フォルダ名更新: '\(oldName)' → '\(folder.name)'")
            
            saveFolders()
            print("✅ FolderStore.updateFolder() 完了 [\(DateFormatter.debugFormatter.string(from: Date()))]")
        } else {
            print("❌ 更新対象のフォルダが見つかりません: \(folder.id.uuidString.prefix(8))")
            print("   現在の配列内フォルダ数: \(folders.count)")
            for (i, existingFolder) in folders.enumerated() {
                print("     [\(i)] ID: \(existingFolder.id.uuidString.prefix(8)), name: '\(existingFolder.name)'")
            }
        }
    }
    
    /// 指定フォルダを削除
    /// - Parameters:
    ///   - folder: 削除するフォルダ
    ///   - memoStore: 関連メモを移動するためのメモストア
    func deleteFolder(_ folder: Folder, memoStore: MemoStore) {
        // フォルダーを削除する前に、そのフォルダーに属するメモを「すべて」に移動
        memoStore.moveMemosFromDeletedFolder(folder.id)
        
        folders.removeAll { $0.id == folder.id }
        saveFolders()
    }
    
    /// 指定インデックスのフォルダを削除
    /// - Parameter offsets: 削除するフォルダのインデックス
    func deleteFolders(at offsets: IndexSet) {
        folders.remove(atOffsets: offsets)
        saveFolders()
    }
    
    // MARK: - Query Methods
    /// IDでフォルダを検索
    /// - Parameter id: 検索するフォルダのID
    /// - Returns: 見つかったフォルダ、または nil
    func folder(withId id: UUID) -> Folder? {
        return folders.first { $0.id == id }
    }
    
    /// 指定フォルダ内のメモ数を取得
    /// - Parameters:
    ///   - folderId: フォルダID（nilの場合はデフォルトフォルダ）
    ///   - allMemos: 全メモの配列
    /// - Returns: フォルダ内のメモ数
    func memoCount(in folderId: UUID?, allMemos: [Memo]) -> Int {
        if let folderId = folderId {
            return allMemos.filter { $0.folderId == folderId }.count
        } else {
            return allMemos.filter { $0.folderId == nil }.count
        }
    }
    
    // MARK: - Private Persistence Methods
    /// フォルダ配列をJSONファイルに保存
    private func saveFolders() {
        saveQueue.async { [weak self] in
            guard let self = self else { return }
            
            do {
                let data = try JSONEncoder().encode(self.folders)
                try data.write(to: self.foldersFile)
                print("FolderStore - 保存成功: \(self.folders.count)件のフォルダ")
            } catch {
                print("フォルダーの保存に失敗しました: \(error)")
                print("ファイルパス: \(self.foldersFile.path)")
                print("ディレクトリ存在確認: \(FileManager.default.fileExists(atPath: self.documentsDirectory.path))")
            }
        }
    }
    
    /// ドキュメントディレクトリの存在確認と作成
    private func ensureDocumentsDirectoryExists() {
        do {
            try FileManager.default.createDirectory(at: documentsDirectory, withIntermediateDirectories: true, attributes: nil)
            print("FolderStore - ドキュメントディレクトリ確認完了: \(documentsDirectory.path)")
        } catch {
            print("FolderStore - ドキュメントディレクトリ作成エラー: \(error)")
        }
    }
    
    /// JSONファイルからフォルダ配列を読み込み
    /// 初回起動時はデフォルトフォルダを作成
    private func loadFolders() {
        do {
            let data = try Data(contentsOf: foldersFile)
            let loadedFolders = try JSONDecoder().decode([Folder].self, from: data)
            
            // メインスレッドでUI更新
            DispatchQueue.main.async {
                self.folders = loadedFolders
                print("FolderStore - 読み込み成功: \(self.folders.count)件のフォルダ")
            }
        } catch {
            print("フォルダーの読み込みに失敗しました（初回起動の可能性があります）: \(error)")
            
            // メインスレッドでUI更新
            DispatchQueue.main.async {
                // デフォルトフォルダーを作成
                self.folders = Folder.defaultFolders
                self.saveFolders()
            }
        }
    }
    
    /// 破損したフォルダファイルをバックアップ
    private func backupCorruptedFolderFile() throws {
        let backupPath = foldersFile.appendingPathExtension("corrupted.\(Int(Date().timeIntervalSince1970))")
        do {
            try FileManager.default.copyItem(at: foldersFile, to: backupPath)
            print("📁 破損フォルダファイルをバックアップしました: \(backupPath.path)")
        } catch {
            print("⚠️ バックアップに失敗しましたが続行します: \(error)")
        }
    }
    
    /// フォルダ配列操作の安全な実行
    private func safeFolderOperation(_ operation: () throws -> Void) throws {
        do {
            try operation()
        } catch {
            print("❌ フォルダ配列操作中にエラーが発生: \(error)")
            throw FolderStoreError.folderOperationFailed(underlyingError: error)
        }
    }
}