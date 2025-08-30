import Foundation

// MARK: - Memo
/// メモデータを管理するモデル構造体
/// Identifiable: SwiftUIのForEachで使用可能
/// Codable: JSON形式でのシリアライズ/デシリアライズに対応
public struct Memo: Identifiable, Codable {
    // MARK: - Properties
    /// 一意識別子
    public let id: UUID
    /// メモのタイトル
    public var title: String
    /// メモの本文内容
    public var content: String
    /// 作成日時
    public var createdAt: Date
    /// 最終更新日時
    public var updatedAt: Date
    /// 所属フォルダID（nilの場合はデフォルトフォルダ）
    public var folderId: UUID?
    /// ピン留めフラグ
    public var isPinned: Bool
    /// 期日（オプショナル）
    public var dueDate: Date?
    /// 予備通知フラグ（期日の前に通知するかどうか）
    public var hasPreNotification: Bool
    /// 予備通知時間（分単位）
    public var preNotificationMinutes: Int
    
    // MARK: - Initializer
    /// メモの初期化
    /// - Parameters:
    ///   - title: タイトル（デフォルト: 空文字）
    ///   - content: 本文内容（デフォルト: 空文字）
    ///   - folderId: フォルダID（デフォルト: nil）
    ///   - dueDate: 期日（デフォルト: nil）
    public init(title: String = "", content: String = "", folderId: UUID? = nil, dueDate: Date? = nil) {
        self.id = UUID()
        self.title = title
        self.content = content
        self.createdAt = Date()
        self.updatedAt = Date()
        self.folderId = folderId
        self.isPinned = false
        self.dueDate = dueDate
        self.hasPreNotification = true
        self.preNotificationMinutes = 60 // デフォルト1時間前
    }
    
    // MARK: - Computed Properties
    /// メモ一覧表示用のプレビューテキスト
    /// 本文の最初の非空行を返す
    var preview: String {
        let lines = content.components(separatedBy: .newlines)
        let nonEmptyLines = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return nonEmptyLines.first ?? "新規メモ"
    }
    
    /// 表示用タイトル
    /// タイトルが設定されていればそれを、なければ本文の最初の行から生成
    var displayTitle: String {
        // タイトルが設定されている場合はそれを使用
        if !title.isEmpty {
            return title
        }
        
        // マークダウン記法を除去してクリーンな文字列を生成
        let cleanContent = content
            .replacingOccurrences(of: #"^#+\s+"#, with: "", options: .regularExpression)     // 見出し記号除去
            .replacingOccurrences(of: #"\*\*(.*?)\*\*"#, with: "$1", options: .regularExpression)  // 太字記号除去
            .replacingOccurrences(of: #"\*(.*?)\*"#, with: "$1", options: .regularExpression)      // 斜体記号除去
            .replacingOccurrences(of: #"`(.*?)`"#, with: "$1", options: .regularExpression)        // インラインコード記号除去
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 最初の非空行を取得
        let firstLine = cleanContent.components(separatedBy: .newlines)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        
        if let line = firstLine, !line.isEmpty {
            return String(line.prefix(30))  // 30文字まで
        }
        
        return "新規メモ"
    }
    
    // MARK: - Mutating Methods
    /// メモの本文内容を更新
    /// - Parameter newContent: 新しい本文内容
    mutating func updateContent(_ newContent: String) {
        self.content = newContent
        self.updatedAt = Date()
    }
    
    /// メモのタイトルを更新
    /// - Parameter newTitle: 新しいタイトル
    mutating func updateTitle(_ newTitle: String) {
        self.title = newTitle
        self.updatedAt = Date()
    }
    
    
    /// メモを指定フォルダに移動
    /// - Parameter folderId: 移動先フォルダID（nilの場合はデフォルトフォルダ）
    mutating func moveToFolder(_ folderId: UUID?) {
        self.folderId = folderId
        self.updatedAt = Date()
    }
    
    /// ピン留め状態を切り替え
    mutating func togglePin() {
        self.isPinned.toggle()
        self.updatedAt = Date()
    }
    
    /// ピン留め状態を設定
    /// - Parameter pinned: ピン留めするかどうか
    mutating func setPin(_ pinned: Bool) {
        self.isPinned = pinned
        self.updatedAt = Date()
    }
    
    /// 期日を設定
    /// - Parameters:
    ///   - dueDate: 期日（nilの場合は期日なし）
    ///   - hasPreNotification: 予備通知を行うかどうか
    ///   - preNotificationMinutes: 予備通知時間（分単位）
    mutating func setDueDate(_ dueDate: Date?, hasPreNotification: Bool = true, preNotificationMinutes: Int = 60) {
        self.dueDate = dueDate
        self.hasPreNotification = hasPreNotification
        self.preNotificationMinutes = preNotificationMinutes
        self.updatedAt = Date()
    }
    
    /// 期日をクリア
    mutating func clearDueDate() {
        self.dueDate = nil
        self.updatedAt = Date()
    }
    
    /// 期日が過ぎているかどうかを判定
    var isOverdue: Bool {
        guard let dueDate = dueDate else { return false }
        return Date() > dueDate
    }
    
    /// 期日が今日かどうかを判定
    var isDueToday: Bool {
        guard let dueDate = dueDate else { return false }
        return Calendar.current.isDateInToday(dueDate)
    }
    
    /// プレビューテキスト（メモリスト表示用）
    var previewText: String {
        let lines = content.components(separatedBy: .newlines)
        let nonEmptyLines = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        
        // マークダウン記法を除去
        let cleanLine = nonEmptyLines.first?
            .replacingOccurrences(of: #"^#+\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\*\*(.*?)\*\*"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"\*(.*?)\*"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"`(.*?)`"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"- \[[ xX]\] "#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        return cleanLine?.isEmpty == false ? cleanLine! : "新規メモ"
    }
    
    /// チェックボックス（タスク）が含まれているかどうか
    var hasCheckboxes: Bool {
        do {
            let regex = try NSRegularExpression(pattern: #"- \[[ xX]\]"#)
            let range = NSRange(content.startIndex..., in: content)
            return regex.firstMatch(in: content, options: [], range: range) != nil
        } catch {
            return false
        }
    }
    
    /// 更新日時の表示用フォーマット
    var formattedUpdateDate: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        let calendar = Calendar.current
        
        if calendar.isDateInToday(updatedAt) {
            formatter.dateStyle = .none
            formatter.timeStyle = .short
            return "今日 \(formatter.string(from: updatedAt))"
        } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: Date()),
                  calendar.isDate(updatedAt, inSameDayAs: yesterday) {
            formatter.dateStyle = .none
            formatter.timeStyle = .short
            return "昨日 \(formatter.string(from: updatedAt))"
        } else if calendar.isDate(updatedAt, equalTo: Date(), toGranularity: .year) {
            formatter.dateFormat = "M/d"
            return formatter.string(from: updatedAt)
        } else {
            formatter.dateFormat = "yyyy/M/d"
            return formatter.string(from: updatedAt)
        }
    }
    
}