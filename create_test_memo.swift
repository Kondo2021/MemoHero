#!/usr/bin/env swift

import Foundation

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

// テストメモを作成
let testMemos = [
    Memo(content: "# 📘 メモ帳アプリ 機能仕様書（完全版）\n\nこれは既存メモのテストです。初回起動時に正しく表示されるかテストします。\n\n## 主要機能\n- 文字数カウント\n- マークダウンプレビュー\n- 検索機能\n- 編集時間計測"),
    Memo(content: "# テストメモ2\n\nこれは2番目のテストメモです。\n\n**太字テキスト**と*斜体テキスト*があります。\n\n```\nコードブロックのテスト\nここは等幅フォント\n```"),
    Memo(content: "シンプルなメモ\n\nこれは通常のテキストメモです。\n改行も含まれています。")
]

// シミュレーターのパスを取得
let deviceId = "5AD05DDF-BCA6-4245-952D-DFFAB17B745E"
let basePath = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Developer/CoreSimulator/Devices")
    .appendingPathComponent(deviceId)
    .appendingPathComponent("data/Containers/Data/Application")

do {
    let contents = try FileManager.default.contentsOfDirectory(atPath: basePath.path)
    
    for folder in contents {
        let plistPath = basePath.appendingPathComponent(folder)
            .appendingPathComponent(".com.apple.mobile_container_manager.metadata.plist")
        
        if FileManager.default.fileExists(atPath: plistPath.path),
           let plistData = try? Data(contentsOf: plistPath),
           let plist = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any],
           let bundleID = plist["MCMMetadataIdentifier"] as? String,
           bundleID == "com.memoapp.edfusion" {
            
            let documentsDir = basePath.appendingPathComponent(folder).appendingPathComponent("Documents")
            try FileManager.default.createDirectory(at: documentsDir, withIntermediateDirectories: true, attributes: nil)
            
            let memosFile = documentsDir.appendingPathComponent("memos.json")
            let data = try JSONEncoder().encode(testMemos)
            try data.write(to: memosFile)
            
            print("✅ テストメモが作成されました:")
            print("📍 パス: \(memosFile.path)")
            print("📊 メモ数: \(testMemos.count)")
            
            for (index, memo) in testMemos.enumerated() {
                print("📝 メモ\(index + 1): \(memo.content.prefix(30))...")
            }
            exit(0)
        }
    }
    
    print("❌ アプリのデータディレクトリが見つかりませんでした")
    print("💡 まず一度アプリを起動してからこのスクリプトを実行してください")
    
} catch {
    print("❌ エラー: \(error)")
}