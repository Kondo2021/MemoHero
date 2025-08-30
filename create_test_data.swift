import Foundation

// テスト用のメモデータを作成
struct Memo: Codable {
    let id: UUID
    var title: String
    var content: String
    var createdAt: Date
    var updatedAt: Date
    var totalEditingTime: TimeInterval
    
    init(title: String = "", content: String = "") {
        self.id = UUID()
        self.title = title
        self.content = content
        self.createdAt = Date()
        self.updatedAt = Date()
        self.totalEditingTime = 0
    }
}

// テストデータを作成
let testMemos: [Memo] = [
    Memo(content: "# 📘 メモ帳アプリ 機能仕様書（完全版）\n\nこれは既存メモのテストです。\n\n## 主要機能\n- 文字数カウント\n- マークダウンプレビュー\n- 検索機能"),
    Memo(content: "# テストメモ2\n\nこれは2番目のテストメモです。\n\n**太字テキスト**と*斜体テキスト*があります。"),
    Memo(content: "シンプルなメモ\n\nこれは通常のテキストメモです。")
]

// シミュレーターのドキュメントディレクトリパスを取得
let simulatorPath = "/Users/kondokenji/Library/Developer/CoreSimulator/Devices/73615DE7-52DE-4018-B0F0-825442DBA6C6/data/Containers/Data/Application"

// アプリのバンドルIDでフォルダを探す
let fileManager = FileManager.default

func findAppDataDirectory() -> URL? {
    do {
        let contents = try fileManager.contentsOfDirectory(atPath: simulatorPath)
        for folder in contents {
            let plistPath = "\(simulatorPath)/\(folder)/.com.apple.mobile_container_manager.metadata.plist"
            if fileManager.fileExists(atPath: plistPath),
               let plistData = fileManager.contents(atPath: plistPath),
               let plist = try PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any],
               let bundleID = plist["MCMMetadataIdentifier"] as? String,
               bundleID == "com.memoapp.edfusion" {
                return URL(fileURLWithPath: "\(simulatorPath)/\(folder)/Documents")
            }
        }
    } catch {
        print("エラー: \(error)")
    }
    return nil
}

if let documentsDir = findAppDataDirectory() {
    let memosFile = documentsDir.appendingPathComponent("memos.json")
    
    do {
        // ディレクトリが存在しない場合は作成
        try fileManager.createDirectory(at: documentsDir, withIntermediateDirectories: true, attributes: nil)
        
        let data = try JSONEncoder().encode(testMemos)
        try data.write(to: memosFile)
        print("テストデータが作成されました: \(memosFile.path)")
        
        // 作成されたデータを確認
        let loadedData = try Data(contentsOf: memosFile)
        let loadedMemos = try JSONDecoder().decode([Memo].self, from: loadedData)
        print("作成されたメモ数: \(loadedMemos.count)")
        for (index, memo) in loadedMemos.enumerated() {
            print("メモ\(index + 1): ID=\(memo.id), content=\(memo.content.prefix(50))...")
        }
    } catch {
        print("エラー: \(error)")
    }
} else {
    print("アプリのデータディレクトリが見つかりませんでした")
    print("まず一度アプリを手動で起動してからこのスクリプトを実行してください")
}