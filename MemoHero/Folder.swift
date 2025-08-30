import Foundation

// MARK: - Folder
/// フォルダデータを管理するモデル構造体
/// Identifiable: SwiftUIのForEachで使用可能
/// Codable: JSON形式でのシリアライズ/デシリアライズに対応
/// Hashable: Setや辞書のキーとして使用可能
struct Folder: Identifiable, Codable, Hashable {
    // MARK: - Properties
    /// 一意識別子
    let id: UUID
    /// フォルダ名
    var name: String
    /// 作成日時
    let createdAt: Date
    /// 最終更新日時
    var updatedAt: Date
    
    // MARK: - Initializer
    /// フォルダの初期化
    /// - Parameter name: フォルダ名（デフォルト: "新しいフォルダ"）
    init(name: String = "新しいフォルダ") {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.updatedAt = Date()
    }
    
    // MARK: - Mutating Methods
    /// フォルダ名を更新
    /// - Parameter newName: 新しいフォルダ名
    mutating func updateName(_ newName: String) {
        self.name = newName
        self.updatedAt = Date()
    }
}

// MARK: - Folder Extensions
/// フォルダのデフォルト値と便利メソッドを提供
extension Folder {
    /// 全メモ表示用の特別なフォルダ
    static let allMemos = Folder(name: "すべてのメモ")
    
    /// アプリ初回起動時に作成されるデフォルトフォルダ群
    static var defaultFolders: [Folder] {
        [
            Folder(name: "個人"),
            Folder(name: "仕事"),
            Folder(name: "アイデア")
        ]
    }
}