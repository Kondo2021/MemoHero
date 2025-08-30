import Foundation

// MARK: - Widget Memo Model
/// ウィジェット用のメモデータモデル
/// メインアプリとウィジェット間で共有されるデータ構造
struct WidgetMemo: Codable, Identifiable {
    let id: UUID
    let title: String
    var content: String
    let createdAt: Date
    var updatedAt: Date
    let dueDate: Date?
    
    var displayTitle: String {
        title.isEmpty ? "無題のメモ" : title
    }
    
    var previewContent: String {
        if content.isEmpty {
            return "内容なし"
        }
        
        // 改行を削除し、最初の100文字まで表示
        let cleanContent = content.replacingOccurrences(of: "\n", with: " ")
        if cleanContent.count > 100 {
            return String(cleanContent.prefix(100)) + "..."
        }
        return cleanContent
    }
}