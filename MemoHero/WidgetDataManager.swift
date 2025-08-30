import Foundation
import WidgetKit

// MARK: - Widget Data Manager
/// ウィジェットとアプリ間でデータを共有するためのマネージャー
class WidgetDataManager {
    
    static let shared = WidgetDataManager()
    
    private let appGroupIdentifier = "group.memohero.edfusion.jp"
    private let widgetMemoKey = "widget_memo"
    private let allMemosKey = "all_memos"
    
    private var sharedDefaults: UserDefaults? {
        return UserDefaults(suiteName: appGroupIdentifier)
    }
    
    private init() {}
    
    /// メモをウィジェット用に設定
    /// - Parameter memo: ウィジェットに表示するメモ
    func setWidgetMemo(_ memo: Memo) {
        guard let sharedDefaults = sharedDefaults else {
            print("❌ App Groupsが設定されていません")
            return
        }
        
        let widgetMemo = convertToWidgetMemo(memo)
        
        do {
            let data = try JSONEncoder().encode(widgetMemo)
            sharedDefaults.set(data, forKey: widgetMemoKey)
            sharedDefaults.synchronize()
            
            // ウィジェットを更新
            WidgetCenter.shared.reloadAllTimelines()
            
            print("✅ ウィジェット用メモを設定しました: \(memo.displayTitle)")
        } catch {
            print("❌ ウィジェット用メモの保存に失敗: \(error)")
        }
    }
    
    /// 現在ウィジェットに設定されているメモを取得
    /// - Returns: ウィジェットに設定されているメモ、設定されていない場合はnil
    func getWidgetMemo() -> WidgetMemo? {
        guard let sharedDefaults = sharedDefaults,
              let data = sharedDefaults.data(forKey: widgetMemoKey) else {
            return nil
        }
        
        do {
            return try JSONDecoder().decode(WidgetMemo.self, from: data)
        } catch {
            print("❌ ウィジェット用メモの読み込みに失敗: \(error)")
            return nil
        }
    }
    
    /// ウィジェット用メモをクリア
    func clearWidgetMemo() {
        guard let sharedDefaults = sharedDefaults else {
            print("❌ App Groupsが設定されていません")
            return
        }
        
        sharedDefaults.removeObject(forKey: widgetMemoKey)
        sharedDefaults.synchronize()
        
        // ウィジェットを更新
        WidgetCenter.shared.reloadAllTimelines()
        
        print("✅ ウィジェット用メモをクリアしました")
    }
    
    /// ウィジェットを手動で更新
    func refreshWidget() {
        WidgetCenter.shared.reloadAllTimelines()
        print("🔄 ウィジェットを更新しました")
    }
    
    /// ウィジェットからチェックリスト項目を更新
    /// - Parameters:
    ///   - memoId: 対象のメモID
    ///   - lineIndex: チェックリスト項目の行インデックス
    ///   - isChecked: 新しいチェック状態
    func updateChecklistItem(memoId: UUID, lineIndex: Int, isChecked: Bool) {
        guard let sharedDefaults = sharedDefaults else {
            print("❌ App Groupsが設定されていません")
            return
        }
        
        // 現在のウィジェットメモを取得
        guard var widgetMemo = getWidgetMemo(), widgetMemo.id == memoId else {
            print("❌ 対象のメモが見つかりません")
            return
        }
        
        // メモ内容の行を分割
        var lines = widgetMemo.content.components(separatedBy: .newlines)
        
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
        
        // 該当行がチェックリスト項目かチェック
        if actualLineIndex < lines.count {
            let line = lines[actualLineIndex]
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            
            if trimmedLine.hasPrefix("- [x] ") || trimmedLine.hasPrefix("- [X] ") {
                // チェック済み → 未チェックに変更
                if !isChecked {
                    lines[actualLineIndex] = line.replacingOccurrences(of: "- [x] ", with: "- [ ] ")
                        .replacingOccurrences(of: "- [X] ", with: "- [ ] ")
                }
            } else if trimmedLine.hasPrefix("- [ ] ") {
                // 未チェック → チェック済みに変更
                if isChecked {
                    lines[actualLineIndex] = line.replacingOccurrences(of: "- [ ] ", with: "- [x] ")
                }
            }
            
            // 更新されたコンテンツを保存
            widgetMemo.content = lines.joined(separator: "\n")
            widgetMemo.updatedAt = Date()
            
            do {
                let data = try JSONEncoder().encode(widgetMemo)
                sharedDefaults.set(data, forKey: widgetMemoKey)
                sharedDefaults.synchronize()
                
                // チェックリスト更新をメインアプリに通知
                notifyMainAppOfChecklistUpdate(memoId: memoId, updatedContent: widgetMemo.content)
                
                // ウィジェットを更新
                WidgetCenter.shared.reloadAllTimelines()
                
                print("✅ チェックリスト項目を更新しました: line=\(lineIndex), checked=\(isChecked)")
            } catch {
                print("❌ チェックリスト更新の保存に失敗: \(error)")
            }
        }
    }
    
    /// メインアプリにチェックリスト更新を通知
    /// - Parameters:
    ///   - memoId: 更新されたメモのID
    ///   - updatedContent: 更新されたメモ内容
    private func notifyMainAppOfChecklistUpdate(memoId: UUID, updatedContent: String) {
        guard let sharedDefaults = sharedDefaults else { return }
        
        let updateInfo = [
            "memoId": memoId.uuidString,
            "content": updatedContent,
            "timestamp": Date().timeIntervalSince1970
        ] as [String: Any]
        
        sharedDefaults.set(updateInfo, forKey: "checklist_update")
        sharedDefaults.synchronize()
        
        print("📤 メインアプリにチェックリスト更新を通知しました")
    }
    
    /// すべてのメモをウィジェット用に保存（Intent選択用）
    /// - Parameter memos: 保存するメモ配列
    func saveAllMemos(_ memos: [Memo]) {
        print("🔄 WidgetDataManager: saveAllMemos() 開始 - \(memos.count)件のメモ")
        
        guard let sharedDefaults = sharedDefaults else {
            print("❌ WidgetDataManager: App Groupsが設定されていません")
            return
        }
        
        let widgetMemos = memos.map { convertToWidgetMemo($0) }
        print("📝 WidgetDataManager: \(widgetMemos.count)件のWidgetMemoに変換完了")
        
        do {
            let data = try JSONEncoder().encode(widgetMemos)
            print("📦 WidgetDataManager: JSONエンコード完了（\(data.count) bytes）")
            
            sharedDefaults.set(data, forKey: allMemosKey)
            sharedDefaults.synchronize()
            
            print("✅ WidgetDataManager: 全メモ(\(widgetMemos.count)件)をウィジェット用に保存しました")
            
            // 最新メモを自動的にウィジェット用にも設定
            if let latestMemo = widgetMemos.max(by: { $0.updatedAt < $1.updatedAt }) {
                do {
                    let latestData = try JSONEncoder().encode(latestMemo)
                    sharedDefaults.set(latestData, forKey: widgetMemoKey)
                    print("✅ WidgetDataManager: 最新メモをwidget_memoキーにも設定しました - \(latestMemo.title)")
                } catch {
                    print("❌ WidgetDataManager: 最新メモの設定に失敗: \(error)")
                }
            }
            
            // 保存確認
            if let checkData = sharedDefaults.data(forKey: allMemosKey) {
                print("🔍 WidgetDataManager: 保存確認 - \(checkData.count) bytesが保存されています")
            } else {
                print("❌ WidgetDataManager: 保存確認失敗 - データが見つかりません")
            }
            
        } catch {
            print("❌ WidgetDataManager: 全メモの保存に失敗: \(error)")
        }
    }
    
    /// 最新のメモを取得
    /// - Returns: 最新のメモ、存在しない場合はnil
    func getLatestMemo() -> WidgetMemo? {
        guard let sharedDefaults = sharedDefaults,
              let data = sharedDefaults.data(forKey: allMemosKey) else {
            return nil
        }
        
        do {
            let memos = try JSONDecoder().decode([WidgetMemo].self, from: data)
            return memos.max(by: { $0.updatedAt < $1.updatedAt })
        } catch {
            print("❌ 最新メモの取得に失敗: \(error)")
            return nil
        }
    }
}

// MARK: - Memo to WidgetMemo Conversion
extension WidgetDataManager {
    /// メインアプリのMemoをWidgetMemoに変換
    /// - Parameter memo: 変換元のMemo
    /// - Returns: 変換されたWidgetMemo
    private func convertToWidgetMemo(_ memo: Memo) -> WidgetMemo {
        return WidgetMemo(
            id: memo.id,
            title: memo.title,
            content: memo.content,
            createdAt: memo.createdAt,
            updatedAt: memo.updatedAt,
            dueDate: memo.dueDate
        )
    }
}