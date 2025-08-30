import Intents
import Foundation

class IntentHandler: INExtension, MemoSelectionIntentHandling {
    
    override func handler(for intent: INIntent) -> Any {
        return self
    }
    
    func provideMemoOptionsCollection(for intent: MemoSelectionIntent, with completion: @escaping (INObjectCollection<MemoEntity>?, Error?) -> Void) {
        // App Groupsから利用可能なメモを取得
        let memos = loadAvailableMemos()
        let memoEntities = memos.map { memo in
            let entity = MemoEntity(identifier: memo.id.uuidString, display: memo.displayTitle)
            entity.displayString = memo.displayTitle
            return entity
        }
        
        let collection = INObjectCollection(items: memoEntities)
        completion(collection, nil)
    }
    
    func defaultMemo(for intent: MemoSelectionIntent) -> MemoEntity? {
        let memos = loadAvailableMemos()
        guard let firstMemo = memos.first else { return nil }
        
        let entity = MemoEntity(identifier: firstMemo.id.uuidString, display: firstMemo.displayTitle)
        entity.displayString = firstMemo.displayTitle
        return entity
    }
    
    private func loadAvailableMemos() -> [WidgetMemo] {
        guard let sharedDefaults = UserDefaults(suiteName: "group.memohero.edfusion.jp"),
              let data = sharedDefaults.data(forKey: "all_memos") else {
            return []
        }
        
        do {
            return try JSONDecoder().decode([WidgetMemo].self, from: data)
        } catch {
            print("❌ メモ一覧の読み込みに失敗: \(error)")
            return []
        }
    }
}