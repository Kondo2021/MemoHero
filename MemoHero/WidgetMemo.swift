import Foundation

// MARK: - Widget Memo Model
/// ウィジェット用のメモデータモデル
/// メインアプリとウィジェット間で共有されるデータ構造
struct WidgetMemo: Codable, Identifiable {
    let id: UUID
    let title: String
    let content: String
    let createdAt: Date
    let updatedAt: Date
    let dueDate: Date?
    
    var displayTitle: String {
        title.isEmpty ? "無題のメモ" : title
    }
    
    var previewContent: String {
        if content.isEmpty {
            return "内容なし"
        }
        
        // マークダウンレンダリング用にそのまま返す（除去処理を行わない）
        // 長さ制限のみ適用
        if content.count > 200 {
            return String(content.prefix(200)) + "..."
        }
        return content
    }
    
    /// マークダウン記法を除去してプレーンテキストを取得
    private func removeMarkdownFormatting(_ text: String) -> String {
        var result = text
        
        // ヘッダー記法を除去 (# ## ### など)
        result = result.replacingOccurrences(of: #"^#{1,6}\s+"#, with: "", options: [.regularExpression, .anchorsMatchLines])
        
        // 太字記法を除去 (**text** や __text__)
        result = result.replacingOccurrences(of: #"\*\*(.*?)\*\*"#, with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: #"__(.*?)__"#, with: "$1", options: .regularExpression)
        
        // イタリック記法を除去 (*text* や _text_)
        result = result.replacingOccurrences(of: #"\*(.*?)\*"#, with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: #"_(.*?)_"#, with: "$1", options: .regularExpression)
        
        // コードブロック記法を除去 (```code```)
        result = result.replacingOccurrences(of: #"```[\s\S]*?```"#, with: "", options: .regularExpression)
        
        // インラインコード記法を除去 (`code`)
        result = result.replacingOccurrences(of: #"`(.*?)`"#, with: "$1", options: .regularExpression)
        
        // リンク記法を除去 ([text](url))
        result = result.replacingOccurrences(of: #"\[([^\]]+)\]\([^\)]+\)"#, with: "$1", options: .regularExpression)
        
        // 画像記法を除去 (![alt](url))
        result = result.replacingOccurrences(of: #"!\[([^\]]*)\]\([^\)]+\)"#, with: "$1", options: .regularExpression)
        
        // リスト記法を除去 (- や * や +)
        result = result.replacingOccurrences(of: #"^[\s]*[-\*\+]\s+"#, with: "", options: [.regularExpression, .anchorsMatchLines])
        
        // 番号付きリスト記法を除去 (1. 2. など)
        result = result.replacingOccurrences(of: #"^[\s]*\d+\.\s+"#, with: "", options: [.regularExpression, .anchorsMatchLines])
        
        // 引用記法を除去 (>)
        result = result.replacingOccurrences(of: #"^[\s]*>\s+"#, with: "", options: [.regularExpression, .anchorsMatchLines])
        
        // 水平線を除去 (--- や ***)
        result = result.replacingOccurrences(of: #"^[\s]*[-\*]{3,}[\s]*$"#, with: "", options: [.regularExpression, .anchorsMatchLines])
        
        // 連続する空白を単一の空白に変換
        result = result.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        
        // 前後の空白を除去
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}