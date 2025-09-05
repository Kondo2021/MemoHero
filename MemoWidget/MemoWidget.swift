import WidgetKit
import SwiftUI
import Foundation
import AppIntents
import UIKit

// MARK: - Widget Intents

/// チェックボックスの状態を切り替えるIntent
@available(iOS 17.0, *)
struct ToggleCheckboxIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Checkbox"
    static var description = IntentDescription("Toggle checkbox state in memo")
    
    @Parameter(title: "Memo ID")
    var memoId: String
    
    @Parameter(title: "Line Index")
    var lineIndex: Int
    
    @Parameter(title: "Is Checked")
    var isChecked: Bool
    
    init() {}
    
    init(memoId: String, lineIndex: Int, isChecked: Bool) {
        self.memoId = memoId
        self.lineIndex = lineIndex
        self.isChecked = isChecked
    }
    
    func perform() async throws -> some IntentResult {
        print("🔄 ウィジェット: チェックボックストグル - メモID: \(memoId), 行: \(lineIndex), 現在の状態: \(isChecked)")
        
        // チェック状態を反転してメモを更新
        await toggleCheckboxInMemo(memoId: memoId, lineIndex: lineIndex, currentState: isChecked)
        
        // ウィジェットをリフレッシュ
        WidgetCenter.shared.reloadAllTimelines()
        
        return .result()
    }
}

/// メモを開くIntent
@available(iOS 17.0, *)
struct OpenMemoIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Memo"
    static var description = IntentDescription("Open memo in the main app")
    static var openAppWhenRun: Bool = true
    
    @Parameter(title: "Memo ID")
    var memoId: String
    
    init() {}
    
    init(memoId: String) {
        self.memoId = memoId
    }
    
    func perform() async throws -> some IntentResult {
        print("📱 ウィジェット: メモを開く - ID: \(memoId)")
        
        // UserDefaultsに開くべきメモIDを保存
        if let sharedDefaults = UserDefaults(suiteName: "group.memohero.edfusion.jp") {
            sharedDefaults.set(memoId, forKey: "widget_open_memo_id")
            print("✅ ウィジェット: 開くメモIDを保存しました")
        }
        
        return .result()
    }
}

// MARK: - Intent Helper Functions

/// チェックボックスの状態を切り替える
@available(iOS 17.0, *)
private func toggleCheckboxInMemo(memoId: String, lineIndex: Int, currentState: Bool) async {
    print("🔧 ウィジェット: チェックボックス状態変更処理開始")
    
    guard let sharedDefaults = UserDefaults(suiteName: "group.memohero.edfusion.jp") else {
        print("❌ ウィジェット: App Groups UserDefaultsにアクセスできません")
        return
    }
    
    // 全メモを取得
    guard let data = sharedDefaults.data(forKey: "all_memos"),
          var memos = try? JSONDecoder().decode([WidgetMemo].self, from: data) else {
        print("❌ ウィジェット: メモデータの取得に失敗")
        return
    }
    
    // 対象メモを検索
    guard let memoIndex = memos.firstIndex(where: { $0.id.uuidString == memoId }) else {
        print("❌ ウィジェット: 対象メモが見つかりません")
        return
    }
    
    var memo = memos[memoIndex]
    var lines = memo.content.components(separatedBy: .newlines)
    
    // 対象行のチェック状態を変更
    if lineIndex < lines.count {
        let line = lines[lineIndex]
        let newLine: String
        
        if currentState {
            // チェック済み → 未チェック
            newLine = line.replacingOccurrences(of: "- [x] ", with: "- [ ] ")
                         .replacingOccurrences(of: "- [X] ", with: "- [ ] ")
        } else {
            // 未チェック → チェック済み
            newLine = line.replacingOccurrences(of: "- [ ] ", with: "- [x] ")
        }
        
        lines[lineIndex] = newLine
        memo.content = lines.joined(separator: "\n")
        memo.updatedAt = Date()
        
        // メモを更新
        memos[memoIndex] = memo
        
        // データを保存
        if let updatedData = try? JSONEncoder().encode(memos) {
            sharedDefaults.set(updatedData, forKey: "all_memos")
            print("✅ ウィジェット: チェックボックス状態を更新しました")
        } else {
            print("❌ ウィジェット: データの保存に失敗")
        }
    } else {
        print("❌ ウィジェット: 行インデックスが範囲外です")
    }
}

// ウィジェット拡張では UIApplication.shared は使用不可のため削除

// MARK: - Timeline Providers
struct MemoProvider: TimelineProvider {
    func placeholder(in context: Context) -> MemoEntry {
        MemoEntry(date: Date(), memo: WidgetMemo(
            id: UUID(),
            title: "サンプルメモ",
            content: "これはサンプルのメモ内容です。ウィジェットでメモをプレビューできます。",
            createdAt: Date(),
            updatedAt: Date(),
            dueDate: nil
        ))
    }

    func getSnapshot(in context: Context, completion: @escaping (MemoEntry) -> ()) {
        let entry = MemoEntry(date: Date(), memo: loadLatestMemo())
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        print("🔄 ウィジェット: getTimeline() 開始")
        let currentDate = Date()
        let memo = loadLatestMemo()
        let entry = MemoEntry(date: currentDate, memo: memo)
        
        print("📅 ウィジェット: タイムラインエントリを作成しました - \(memo.title)")
        
        // 15分後に更新（より頻繁に更新）
        let refreshDate = Calendar.current.date(byAdding: .minute, value: 15, to: currentDate)!
        let timeline = Timeline(entries: [entry], policy: .after(refreshDate))
        
        print("✅ ウィジェット: タイムライン完成、次回更新は15分後")
        completion(timeline)
    }
    
    private func loadLatestMemo() -> WidgetMemo {
        print("🔄 ウィジェット: loadLatestMemo() 開始")
        
        // 最新メモを取得
        if let latestMemo = getLatestMemoFromStorage() {
            print("✅ ウィジェット: 最新メモを取得しました - \(latestMemo.title)")
            return latestMemo
        }
        
        print("⚠️ ウィジェット: 最新メモが見つからないため、設定されたメモを確認")
        
        // 最新メモがない場合は設定されたメモを試す
        guard let sharedDefaults = UserDefaults(suiteName: "group.memohero.edfusion.jp") else {
            print("❌ ウィジェット: App Groups UserDefaultsにアクセスできません")
            return createPlaceholderMemo()
        }
        
        guard let data = sharedDefaults.data(forKey: "widget_memo") else {
            print("⚠️ ウィジェット: widget_memoキーにデータがありません")
            return createPlaceholderMemo()
        }
        
        guard let memo = try? JSONDecoder().decode(WidgetMemo.self, from: data) else {
            print("❌ ウィジェット: widget_memoのデコードに失敗")
            return createPlaceholderMemo()
        }
        
        print("✅ ウィジェット: 設定されたメモを取得しました - \(memo.title)")
        return memo
    }
}

// MARK: - Helper Functions
private func createPlaceholderMemo() -> WidgetMemo {
    print("📝 ウィジェット: プレースホルダーメモを作成")
    return WidgetMemo(
        id: UUID(),
        title: "ウィジェット設定中",
        content: "メモアプリを開いてメモを作成してください。\n作成されたメモが自動的にここに表示されます。",
        createdAt: Date(),
        updatedAt: Date(),
        dueDate: nil
    )
}

// データ管理のためのヘルパー関数
private func getLatestMemoFromStorage() -> WidgetMemo? {
    print("🔍 ウィジェット: getLatestMemoFromStorage() 開始")
    
    guard let sharedDefaults = UserDefaults(suiteName: "group.memohero.edfusion.jp") else {
        print("❌ ウィジェット: App Groups UserDefaultsにアクセスできません")
        return nil
    }
    
    guard let data = sharedDefaults.data(forKey: "all_memos") else {
        print("⚠️ ウィジェット: all_memosキーにデータがありません")
        return nil
    }
    
    print("✅ ウィジェット: all_memosデータを取得しました（\(data.count) bytes）")
    
    do {
        let memos = try JSONDecoder().decode([WidgetMemo].self, from: data)
        print("✅ ウィジェット: \(memos.count)個のメモをデコードしました")
        
        let latestMemo = memos.max(by: { $0.updatedAt < $1.updatedAt })
        if let memo = latestMemo {
            print("✅ ウィジェット: 最新メモを特定しました - \(memo.title)")
        } else {
            print("⚠️ ウィジェット: メモ配列は空です")
        }
        
        return latestMemo
    } catch {
        print("❌ ウィジェット: 最新メモの取得に失敗: \(error)")
        return nil
    }
}

// MARK: - Timeline Entry
struct MemoEntry: TimelineEntry {
    let date: Date
    let memo: WidgetMemo
}

// MARK: - Widget Views

// サイズ対応のウィジェットビュー
struct MemoWidgetEntryView: View {
    var entry: MemoEntry
    @Environment(\.widgetFamily) var widgetFamily

    var body: some View {
        switch widgetFamily {
        case .systemSmall:
            SmallMemoView(entry: entry)
        case .systemMedium:
            MediumMemoView(entry: entry)
        case .systemLarge:
            LargeMemoView(entry: entry)
        case .systemExtraLarge:
            ExtraLargeMemoView(entry: entry)
        case .accessoryCircular, .accessoryRectangular, .accessoryInline:
            SmallMemoView(entry: entry)
        @unknown default:
            SmallMemoView(entry: entry)
        }
    }
}

// 小サイズ（2x2）ウィジェット
struct SmallMemoView: View {
    let entry: MemoEntry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // メモ内容プレビュー（メイン表示）
            WidgetMarkdownView(content: entry.memo.content, fontSize: 11, lineLimit: 7, memoId: entry.memo.id)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            
            Spacer(minLength: 4)
            
            // 更新日時（下部に固定）
            HStack {
                Spacer()
                Text(formatDate(entry.memo.updatedAt))
                    .font(.system(size: 8))
                    .foregroundColor(.secondary.opacity(0.6))
                    .lineLimit(1)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 10)
        .background(Color(UIColor.systemBackground))
        .cornerRadius(8)
    }
}

// 中サイズ（4x2）ウィジェット
struct MediumMemoView: View {
    let entry: MemoEntry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // メモ内容プレビュー（メイン表示）
            WidgetMarkdownView(content: entry.memo.content, fontSize: 13, lineLimit: 5, memoId: entry.memo.id)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            
            Spacer()
            
            // 更新日時（下部に固定）
            HStack {
                Spacer()
                Text("更新: \(formatDate(entry.memo.updatedAt))")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary.opacity(0.5))
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(18)
        .background(Color(UIColor.systemBackground))
        .cornerRadius(8)
    }
}

// 大サイズ（4x4）ウィジェット  
struct LargeMemoView: View {
    let entry: MemoEntry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // メモ内容プレビュー（メイン表示）
            WidgetMarkdownView(content: entry.memo.content, fontSize: 15, lineLimit: 20, memoId: entry.memo.id)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            
            // 更新日時（下部に固定）
            HStack {
                Spacer()
                Text("更新: \(formatDate(entry.memo.updatedAt))")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.5))
                Spacer()
            }
            .padding(.top, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 24)
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
        .background(Color(UIColor.systemBackground))
        .cornerRadius(12)
    }
}

// 特大サイズ（iPhone用4x4）ウィジェット
struct ExtraLargeMemoView: View {
    let entry: MemoEntry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // メモ内容プレビュー（ScrollView不使用）
            WidgetMarkdownView(content: entry.memo.content, fontSize: 16, lineLimit: 30, memoId: entry.memo.id)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            
            // 更新日時（下部に固定）
            HStack {
                Spacer()
                Text("更新: \(formatDate(entry.memo.updatedAt))")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.5))
                Spacer()
            }
            .padding(.top, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(12)
        .background(Color(UIColor.systemBackground))
        .cornerRadius(16)
    }
}

// MARK: - Widget Configurations
struct AutoMemoWidget: Widget {
    let kind: String = "AutoMemoWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MemoProvider()) { entry in
            MemoWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) {
            Color(UIColor.systemBackground)
        }
        }
        .configurationDisplayName("メモウィジェット（最新自動表示）")
        .description("最新のメモを自動的にホーム画面に表示します。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
    }
}

// MARK: - Helper Functions

// MARK: - WidgetMarkdownView
/// ウィジェット用のマークダウンビュー（チェックリスト操作対応）
struct WidgetMarkdownView: View {
    let content: String
    let fontSize: CGFloat
    let lineLimit: Int?
    let memoId: UUID
    
    init(content: String, fontSize: CGFloat = 14, lineLimit: Int? = nil, memoId: UUID) {
        self.content = content
        self.fontSize = fontSize
        self.lineLimit = lineLimit
        self.memoId = memoId
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(parseMarkdownLines(), id: \.id) { element in
                element.view
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: 0) // 残りのスペースを下に押しやる
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    
    private func parseMarkdownLines() -> [WidgetMarkdownElement] {
        let lines = content.components(separatedBy: .newlines)
        
        // シンプルな行数制限：先頭から指定行数だけを取得
        let limitedLines: [String]
        if let limit = lineLimit {
            limitedLines = Array(lines.prefix(limit))
            print("🔍 ウィジェット: 行数制限適用 - 全\(lines.count)行中の先頭\(limit)行を表示")
        } else {
            limitedLines = lines
            print("🔍 ウィジェット: 行数制限なし - 全\(lines.count)行を表示")
        }
        
        print("🔍 ウィジェット: 処理対象行数 \(limitedLines.count)行")
        for (i, line) in limitedLines.enumerated() {
            let preview = line.prefix(30)
            print("  [\(i)] '\(preview)...'")
        }
        
        var elements: [WidgetMarkdownElement] = []
        var inCodeBlock = false
        var codeBlockContent: [String] = []
        var inTable = false
        var tableRows: [String] = []
        
        // 番号付きリストのカウンター管理（レベル別）
        var numberedListCounters: [Int: Int] = [:]
        
        for (currentIndex, line) in limitedLines.enumerated() {
            
            // コードブロック処理
            if line.hasPrefix("```") {
                if inCodeBlock {
                    // コードブロック終了
                    let codeText = codeBlockContent.joined(separator: "\n")
                    if !codeText.isEmpty {
                        elements.append(WidgetMarkdownElement(view: AnyView(
                            Text(codeText)
                                .font(.system(size: fontSize * 0.9, weight: .regular, design: .monospaced))
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(.systemGray5))
                                .cornerRadius(4)
                        )))
                    }
                    codeBlockContent = []
                    inCodeBlock = false
                } else {
                    inCodeBlock = true
                }
                continue
            }
            
            if inCodeBlock {
                codeBlockContent.append(line)
                continue
            }
            
            // 表（Table）処理
            if line.hasPrefix("|") && line.hasSuffix("|") {
                // 表の開始
                if !inTable {
                    inTable = true
                    tableRows = []
                }
                
                tableRows.append(line)
                
                // 次の行が表の一部でないかチェック
                let isLastLine = currentIndex == limitedLines.count - 1
                let nextIndex = currentIndex + 1
                let nextLineIsTable = !isLastLine && limitedLines[nextIndex].hasPrefix("|") && limitedLines[nextIndex].hasSuffix("|")
                
                if isLastLine || !nextLineIsTable {
                    // 表の終了 - 表全体を表示
                    let tableView = createTableView(from: tableRows)
                    elements.append(WidgetMarkdownElement(view: tableView))
                    inTable = false
                    tableRows = []
                }
                continue
            }
            
            // 各行を処理
            if let element = processMarkdownLineForWidget(line, lineIndex: currentIndex, numberedListCounters: &numberedListCounters) {
                elements.append(element)
            }
        }
        
        return elements
    }
    
    private func processMarkdownLineForWidget(_ line: String, lineIndex: Int, numberedListCounters: inout [Int: Int]) -> WidgetMarkdownElement? {
        let trimmedLine = line.trimmingCharacters(in: .whitespaces)
        
        // 空行をスキップ
        if trimmedLine.isEmpty {
            return nil
        }
        
        // 画像リンク行をスキップ（ウィジェットでは画像表示できないため）
        if trimmedLine.contains("![") && trimmedLine.contains("](") {
            return nil
        }
        
        // インデントレベルを計算
        let indentLevel = getIndentLevel(line)
        let baseIndent: CGFloat = 16 // ウィジェット用の小さめなインデント幅
        let totalIndent = CGFloat(indentLevel) * baseIndent
        
        // 見出し処理（プレビューと同じスタイリング）
        if trimmedLine.hasPrefix("# ") {
            let content = String(trimmedLine.dropFirst(2))
            return WidgetMarkdownElement(view: AnyView(
                Link(destination: URL(string: "memoapp://open/\(memoId.uuidString)")!) {
                    HStack {
                        VStack {
                            formatInlineMarkdownForWidget(content)
                                .font(.system(size: fontSize * 1.4, weight: .bold))
                                .foregroundColor(.primary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 2)
                }
            ))
        } else if trimmedLine.hasPrefix("## ") {
            let content = String(trimmedLine.dropFirst(3))
            return WidgetMarkdownElement(view: AnyView(
                Link(destination: URL(string: "memoapp://open/\(memoId.uuidString)")!) {
                    HStack {
                        VStack {
                            formatInlineMarkdownForWidget(content)
                                .font(.system(size: fontSize * 1.25, weight: .bold))
                                .foregroundColor(.primary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 1)
                    .overlay(
                        Rectangle()
                            .fill(Color.primary)
                            .frame(height: 2)
                            .padding(.top, 4),
                        alignment: .bottom
                    )
                }
            ))
        } else if trimmedLine.hasPrefix("### ") {
            let content = String(trimmedLine.dropFirst(4))
            return WidgetMarkdownElement(view: AnyView(
                Link(destination: URL(string: "memoapp://open/\(memoId.uuidString)")!) {
                    HStack {
                        Rectangle()
                            .fill(Color.primary)
                            .frame(width: 4)
                        VStack {
                            formatInlineMarkdownForWidget(content)
                                .font(.system(size: fontSize * 1.15, weight: .semibold))
                                .foregroundColor(.primary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 1)
                }
            ))
        } else if trimmedLine.hasPrefix("#### ") {
            let content = String(trimmedLine.dropFirst(5))
            return WidgetMarkdownElement(view: AnyView(
                Link(destination: URL(string: "memoapp://open/\(memoId.uuidString)")!) {
                    HStack {
                        Rectangle()
                            .fill(Color.primary)
                            .frame(width: 3)
                        VStack {
                            formatInlineMarkdownForWidget(content)
                                .font(.system(size: fontSize * 1.05, weight: .semibold))
                                .foregroundColor(.primary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 1)
                }
            ))
        } else if trimmedLine.hasPrefix("##### ") || trimmedLine.hasPrefix("###### ") {
            let content = String(trimmedLine.dropFirst(trimmedLine.hasPrefix("##### ") ? 6 : 7))
            return WidgetMarkdownElement(view: AnyView(
                Link(destination: URL(string: "memoapp://open/\(memoId.uuidString)")!) {
                    HStack {
                        Rectangle()
                            .fill(Color.primary)
                            .frame(width: 2)
                        VStack {
                            formatInlineMarkdownForWidget(content)
                                .font(.system(size: fontSize, weight: .semibold))
                                .foregroundColor(.primary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 1)
                }
            ))
        }
        // チェックリスト処理（ウィジェット上でタップ可能）
        else if trimmedLine.hasPrefix("- [x] ") || trimmedLine.hasPrefix("- [X] ") {
            let content = String(trimmedLine.dropFirst(6))
            return WidgetMarkdownElement(view: AnyView(
                HStack(alignment: .top, spacing: 6) {
                    // チェック済みアイコン（タップ可能）
                    if #available(iOS 17.0, *) {
                        Button(intent: ToggleCheckboxIntent(memoId: memoId.uuidString, lineIndex: lineIndex, isChecked: true)) {
                            ZStack {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 14, height: 14)
                                Image(systemName: "checkmark")
                                    .foregroundColor(.white)
                                    .font(.system(size: 8, weight: .bold))
                            }
                            .frame(minWidth: 14, alignment: .center)
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        // テキスト部分（メモを開く）
                        Button(intent: OpenMemoIntent(memoId: memoId.uuidString)) {
                            formatInlineMarkdownForWidget(content)
                                .font(.system(size: fontSize))
                                .foregroundColor(.secondary)
                                .strikethrough(true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(PlainButtonStyle())
                    } else {
                        // iOS 16以下では従来のLink使用
                        Link(destination: URL(string: "memoapp://open/\(memoId.uuidString)")!) {
                            ZStack {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 14, height: 14)
                                Image(systemName: "checkmark")
                                    .foregroundColor(.white)
                                    .font(.system(size: 8, weight: .bold))
                            }
                            .frame(minWidth: 14, alignment: .center)
                        }
                        
                        formatInlineMarkdownForWidget(content)
                            .font(.system(size: fontSize))
                            .foregroundColor(.secondary)
                            .strikethrough(true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.leading, totalIndent)
                .padding(.vertical, 1)
            ))
        } else if trimmedLine.hasPrefix("- [ ] ") {
            let content = String(trimmedLine.dropFirst(6))
            return WidgetMarkdownElement(view: AnyView(
                HStack(alignment: .top, spacing: 6) {
                    // 未チェックアイコン（タップ可能）
                    if #available(iOS 17.0, *) {
                        Button(intent: ToggleCheckboxIntent(memoId: memoId.uuidString, lineIndex: lineIndex, isChecked: false)) {
                            Circle()
                                .stroke(Color.secondary, lineWidth: 1)
                                .frame(width: 14, height: 14)
                                .frame(minWidth: 14, alignment: .center)
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        // テキスト部分（メモを開く）
                        Button(intent: OpenMemoIntent(memoId: memoId.uuidString)) {
                            formatInlineMarkdownForWidget(content)
                                .font(.system(size: fontSize))
                                .foregroundColor(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(PlainButtonStyle())
                    } else {
                        // iOS 16以下では従来のLink使用
                        Link(destination: URL(string: "memoapp://open/\(memoId.uuidString)")!) {
                            Circle()
                                .stroke(Color.secondary, lineWidth: 1)
                                .frame(width: 14, height: 14)
                                .frame(minWidth: 14, alignment: .center)
                        }
                        
                        formatInlineMarkdownForWidget(content)
                            .font(.system(size: fontSize))
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.leading, totalIndent)
                .padding(.vertical, 1)
            ))
        }
        // 通常のリスト処理（プレビューと同じスタイリング）
        else if trimmedLine.hasPrefix("- ") || trimmedLine.hasPrefix("* ") || trimmedLine.hasPrefix("+ ") {
            let content = String(trimmedLine.dropFirst(2))
            return WidgetMarkdownElement(view: AnyView(
                Link(destination: URL(string: "memoapp://open/\(memoId.uuidString)")!) {
                    HStack(alignment: .top, spacing: 6) {
                        Text("•")
                            .font(.system(size: fontSize * 0.8))
                            .foregroundColor(.primary)
                            .frame(minWidth: 12, alignment: .center)
                        formatInlineMarkdownForWidget(content)
                            .font(.system(size: fontSize))
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.leading, totalIndent)
                    .padding(.vertical, 1)
                }
            ))
        }
        // 番号付きリスト処理（プレビューと同じスタイリング）
        else if let match = trimmedLine.range(of: #"^\d+\.\s"#, options: .regularExpression) {
            let content = String(trimmedLine[match.upperBound...])
            
            // インデントレベルに応じたカウンター管理
            let currentCounter = numberedListCounters[indentLevel, default: 0] + 1
            numberedListCounters[indentLevel] = currentCounter
            
            // より深いレベルのカウンターをリセット
            for level in (indentLevel + 1)...10 {
                numberedListCounters[level] = nil
            }
            
            // インデントレベルに応じた番号形式を適用
            let formattedNumber = formatNumberForIndentLevel(currentCounter, indentLevel: indentLevel)
            
            // 丸囲み数字の場合はピリオドを付けない
            let displayText: String
            if indentLevel == 1 {
                displayText = formattedNumber // 丸囲み数字にはピリオドを付けない
            } else {
                displayText = "\(formattedNumber)." // その他の数字にはピリオドを付ける
            }
            
            return WidgetMarkdownElement(view: AnyView(
                Link(destination: URL(string: "memoapp://open/\(memoId.uuidString)")!) {
                    HStack(alignment: .top, spacing: 6) {
                        Text(displayText)
                            .font(.system(size: fontSize * 0.9, weight: .medium))
                            .foregroundColor(.primary)
                            .frame(minWidth: 20, alignment: .leading)
                        formatInlineMarkdownForWidget(content)
                            .font(.system(size: fontSize))
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.leading, totalIndent)
                    .padding(.vertical, 1)
                }
            ))
        }
        // 引用処理
        else if trimmedLine.hasPrefix("> ") {
            let content = String(trimmedLine.dropFirst(2))
            return WidgetMarkdownElement(view: AnyView(
                Link(destination: URL(string: "memoapp://open/\(memoId.uuidString)")!) {
                    HStack(alignment: .center, spacing: 6) {
                        Rectangle()
                            .fill(Color.secondary)
                            .frame(width: 3, height: fontSize + 4) // テキストの高さに合わせる
                        formatInlineMarkdownForWidget(content)
                            .font(.system(size: fontSize * 0.95))
                            .foregroundColor(.secondary)
                            .italic()
                        Spacer()
                    }
                }
            ))
        }
        // 水平線処理
        else if trimmedLine == "---" || trimmedLine == "***" || trimmedLine == "___" {
            return WidgetMarkdownElement(view: AnyView(
                Rectangle()
                    .fill(Color.secondary)
                    .frame(height: 1)
                    .frame(maxWidth: .infinity)
            ))
        }
        // 通常のテキスト
        else {
            return WidgetMarkdownElement(view: AnyView(
                Link(destination: URL(string: "memoapp://open/\(memoId.uuidString)")!) {
                    VStack {
                        formatInlineMarkdownForWidget(line)
                    }
                    .font(.system(size: fontSize))
                    .foregroundColor(.primary)
                    .padding(.vertical, 1)
                }
            ))
        }
    }
    
    private func formatInlineMarkdownForWidget(_ text: String) -> AnyView {
        // 取り消し線、太字、斜体、インラインコード、リンクが含まれているかチェック
        if text.contains("~~") || text.contains("**") || text.contains("*") || text.contains("`") || (text.contains("[") && text.contains("](")) {
            return AnyView(createFormattedText(text))
        } else {
            // 通常のテキスト処理
            return AnyView(Text(text))
        }
    }
    
    /// フォーマット済みテキストを作成
    private func createFormattedText(_ text: String) -> some View {
        HStack(spacing: 0) {
            ForEach(parseMarkdownSegments(text), id: \.id) { segment in
                if segment.isCode {
                    Text(segment.text)
                        .font(.system(size: fontSize, design: .monospaced))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color(.systemGray4))
                        .cornerRadius(3)
                } else if segment.isStrikethrough {
                    Text(segment.text)
                        .font(.system(size: fontSize))
                        .strikethrough()
                        .foregroundColor(.secondary)
                } else if segment.isBold {
                    Text(segment.text)
                        .font(.system(size: fontSize, weight: .bold))
                } else if segment.isItalic {
                    Text(segment.text)
                        .font(.system(size: fontSize))
                        .italic()
                } else if segment.isLink {
                    Text(segment.text)
                        .font(.system(size: fontSize))
                        .foregroundColor(.blue)
                        .underline()
                } else {
                    Text(segment.text)
                        .font(.system(size: fontSize))
                }
            }
        }
    }
    
    /// インラインコードセグメントを解析
    private func parseInlineCodeSegments(_ text: String) -> [InlineSegment] {
        var segments: [InlineSegment] = []
        var currentText = text
        var segmentId = 0
        
        // インラインコードパターンで分割
        while !currentText.isEmpty {
            if let range = currentText.range(of: #"`([^`]+)`"#, options: .regularExpression) {
                // コード前のテキスト
                if range.lowerBound > currentText.startIndex {
                    let beforeText = String(currentText[..<range.lowerBound])
                    if !beforeText.isEmpty {
                        segments.append(InlineSegment(id: segmentId, text: beforeText, isCode: false))
                        segmentId += 1
                    }
                }
                
                // コード部分（`を除去）
                let fullCodeText = String(currentText[range])
                let codeText = fullCodeText.replacingOccurrences(of: "`", with: "")
                segments.append(InlineSegment(id: segmentId, text: codeText, isCode: true))
                segmentId += 1
                
                // 残りのテキスト
                currentText = String(currentText[range.upperBound...])
            } else {
                // コードがない場合、残りのテキストを追加
                if !currentText.isEmpty {
                    segments.append(InlineSegment(id: segmentId, text: currentText, isCode: false))
                }
                break
            }
        }
        
        return segments
    }
    
    /// マークダウンセグメント構造体
    struct MarkdownSegment {
        let id: Int
        let text: String
        let isCode: Bool
        let isStrikethrough: Bool
        let isBold: Bool
        let isItalic: Bool
        let isLink: Bool
        let linkURL: String?
    }
    
    /// インラインセグメント構造体（下位互換性のため残す）
    struct InlineSegment {
        let id: Int
        let text: String
        let isCode: Bool
    }
    
    /// マークダウンセグメントを解析
    private func parseMarkdownSegments(_ text: String) -> [MarkdownSegment] {
        var segments: [MarkdownSegment] = []
        var currentText = text
        var segmentId = 0
        
        // マークダウンパターンの優先順位で処理（長いパターンから先に処理）
        let patterns = [
            (pattern: #"`([^`]+)`"#, type: "code"),
            (pattern: #"\[([^\]]+)\]\(([^)]+)\)"#, type: "link"),
            (pattern: #"~~([^~]+)~~"#, type: "strikethrough"),
            (pattern: #"\*\*([^*]+)\*\*"#, type: "bold"),
            (pattern: #"(?<!\*)\*([^*]+)\*(?!\*)"#, type: "italic")
        ]
        
        while !currentText.isEmpty {
            var nearestMatch: (range: Range<String.Index>, type: String, content: String, linkURL: String?)?
            
            // 最も近いマッチを探す
            for (pattern, type) in patterns {
                if let range = currentText.range(of: pattern, options: .regularExpression) {
                    if nearestMatch == nil || range.lowerBound < nearestMatch!.range.lowerBound {
                        // マッチしたコンテンツを抽出
                        let match = String(currentText[range])
                        var content = match
                        var linkURL: String? = nil
                        
                        switch type {
                        case "code":
                            content = content.replacingOccurrences(of: "`", with: "")
                        case "link":
                            // リンクの場合は[text](url)からtextとurlを抽出
                            if let linkMatch = match.range(of: #"\[([^\]]+)\]\(([^)]+)\)"#, options: .regularExpression) {
                                let linkText = String(match[linkMatch])
                                let regex = try! NSRegularExpression(pattern: #"\[([^\]]+)\]\(([^)]+)\)"#)
                                if let result = regex.firstMatch(in: linkText, range: NSRange(linkText.startIndex..., in: linkText)) {
                                    if let textRange = Range(result.range(at: 1), in: linkText) {
                                        content = String(linkText[textRange])
                                    }
                                    if let urlRange = Range(result.range(at: 2), in: linkText) {
                                        linkURL = String(linkText[urlRange])
                                    }
                                }
                            }
                        case "strikethrough":
                            content = content.replacingOccurrences(of: "~~", with: "")
                        case "bold":
                            content = content.replacingOccurrences(of: "**", with: "")
                        case "italic":
                            content = content.replacingOccurrences(of: "*", with: "")
                        default:
                            break
                        }
                        nearestMatch = (range: range, type: type, content: content, linkURL: linkURL)
                    }
                }
            }
            
            if let match = nearestMatch {
                // マッチ前のテキスト
                if match.range.lowerBound > currentText.startIndex {
                    let beforeText = String(currentText[..<match.range.lowerBound])
                    if !beforeText.isEmpty {
                        segments.append(MarkdownSegment(
                            id: segmentId, text: beforeText, isCode: false, 
                            isStrikethrough: false, isBold: false, isItalic: false, isLink: false, linkURL: nil
                        ))
                        segmentId += 1
                    }
                }
                
                // マッチしたテキスト
                segments.append(MarkdownSegment(
                    id: segmentId, text: match.content,
                    isCode: match.type == "code",
                    isStrikethrough: match.type == "strikethrough",
                    isBold: match.type == "bold",
                    isItalic: match.type == "italic",
                    isLink: match.type == "link",
                    linkURL: match.linkURL
                ))
                segmentId += 1
                
                currentText = String(currentText[match.range.upperBound...])
            } else {
                // マッチがない場合、残りのテキストを追加
                if !currentText.isEmpty {
                    segments.append(MarkdownSegment(
                        id: segmentId, text: currentText, isCode: false,
                        isStrikethrough: false, isBold: false, isItalic: false, isLink: false, linkURL: nil
                    ))
                }
                break
            }
        }
        
        return segments
    }
    
    private func processSimpleMarkdown(_ text: String) -> String {
        var result = text
        
        // 取り消し線処理 ~~text~~ → text
        result = result.replacingOccurrences(of: #"~~([^~]+)~~"#, with: "$1", options: .regularExpression)
        
        // 太字処理 **text** → text （記号だけ削除）
        result = result.replacingOccurrences(of: #"\*\*([^*]+)\*\*"#, with: "$1", options: .regularExpression)
        
        // 斜体処理 *text* → text
        result = result.replacingOccurrences(of: #"(?<!\*)\*([^*]+)\*(?!\*)"#, with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: #"(?<!_)_([^_]+)_(?!_)"#, with: "$1", options: .regularExpression)
        
        // インラインコード処理（記号を除去してプレーンテキストに）
        result = result.replacingOccurrences(of: #"`([^`]+)`"#, with: "$1", options: .regularExpression)
        
        // リンク処理 [text](url) → text
        result = result.replacingOccurrences(of: #"\[([^\]]+)\]\([^)]+\)"#, with: "$1", options: .regularExpression)
        
        return result
    }
    
    /// 表を作成するビュー（アプリ内プレビューと同じスタイル）
    private func createTableView(from rows: [String]) -> AnyView {
        // ヘッダー行と区切り行の処理
        var tableData: [[String]] = []
        for row in rows {
            let cells = row.components(separatedBy: "|")
            // 最初と最後の空要素を除去
            let cleanCells = Array(cells.dropFirst().dropLast()).map { $0.trimmingCharacters(in: .whitespaces) }
            if !cleanCells.isEmpty {
                tableData.append(cleanCells)
            }
        }
        
        // 区切り行（:---:形式）を削除
        if tableData.count > 1 {
            let secondRow = tableData[1]
            let isHeaderSeparator = secondRow.allSatisfy { cell in
                cell.allSatisfy { char in
                    char == "-" || char == ":" || char.isWhitespace
                }
            }
            if isHeaderSeparator {
                tableData.remove(at: 1)
            }
        }
        
        return AnyView(
            VStack(spacing: 0) {
                ForEach(Array(tableData.enumerated()), id: \.offset) { rowIndex, rowData in
                    HStack(spacing: 0) {
                        ForEach(Array(rowData.enumerated()), id: \.offset) { cellIndex, cellText in
                            VStack {
                                formatInlineMarkdownForWidget(cellText)
                                    .font(.system(size: fontSize * 0.85, weight: rowIndex == 0 ? .semibold : .regular))
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(rowIndex == 0 ? Color(.systemGray5) : Color(.systemBackground))
                            .overlay(
                                Rectangle()
                                    .stroke(Color.gray.opacity(0.4), lineWidth: 0.5)
                            )
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.gray.opacity(0.4), lineWidth: 1)
            )
            .padding(.vertical, 4)
        )
    }
    
    // MARK: - Number Format Helpers
    
    /// インデントレベルに応じた番号形式を取得
    /// - Parameters:
    ///   - number: 番号
    ///   - indentLevel: インデントレベル (0=数字, 1=①, 2=ローマ数字, 3=小文字アルファベット)
    /// - Returns: フォーマットされた番号文字列
    private func formatNumberForIndentLevel(_ number: Int, indentLevel: Int) -> String {
        switch indentLevel {
        case 0:
            return "\(number)"
        case 1:
            return convertToCircledNumber(number)
        case 2:
            return convertToRomanNumeral(number)
        case 3:
            return convertToLowerAlphabet(number)
        default:
            // 4レベル以上は通常の数字に戻す
            return "\(number)"
        }
    }
    
    /// 数字を①②③形式に変換（1-50まで対応）
    private func convertToCircledNumber(_ number: Int) -> String {
        let circledNumbers = ["①", "②", "③", "④", "⑤", "⑥", "⑦", "⑧", "⑨", "⑩",
                             "⑪", "⑫", "⑬", "⑭", "⑮", "⑯", "⑰", "⑱", "⑲", "⑳",
                             "㉑", "㉒", "㉓", "㉔", "㉕", "㉖", "㉗", "㉘", "㉙", "㉚",
                             "㉛", "㉜", "㉝", "㉞", "㉟", "㊱", "㊲", "㊳", "㊴", "㊵",
                             "㊶", "㊷", "㊸", "㊹", "㊺", "㊻", "㊼", "㊽", "㊾", "㊿"]
        
        if number >= 1 && number <= circledNumbers.count {
            return circledNumbers[number - 1]
        } else {
            return "\(number)" // 範囲外は通常の数字
        }
    }
    
    /// 数字をローマ数字に変換（1-50まで対応）
    private func convertToRomanNumeral(_ number: Int) -> String {
        if number < 1 || number > 50 {
            return "\(number)" // 範囲外は通常の数字
        }
        
        let values = [40, 10, 9, 5, 4, 1]
        let symbols = ["xl", "x", "ix", "v", "iv", "i"]
        
        var result = ""
        var num = number
        
        for (i, value) in values.enumerated() {
            let count = num / value
            if count > 0 {
                result += String(repeating: symbols[i], count: count)
                num %= value
            }
        }
        
        return result
    }
    
    /// 数字を小文字アルファベットに変換（1-26まで対応）
    private func convertToLowerAlphabet(_ number: Int) -> String {
        if number < 1 || number > 26 {
            return "\(number)" // 範囲外は通常の数字
        }
        
        let alphabets = ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z"]
        return alphabets[number - 1]
    }

    /// 行の先頭のインデントレベルを計算（メインアプリと同じロジック）
    /// タブ文字または2個以上の半角スペースでインデントレベルを判定
    /// - Parameter line: 解析対象の行
    /// - Returns: インデントレベル（0から開始）
    private func getIndentLevel(_ line: String) -> Int {
        let prefix = line.prefix { $0 == " " || $0 == "\t" }
        var indentLevel = 0
        var i = prefix.startIndex
        
        while i < prefix.endIndex {
            let char = prefix[i]
            if char == "\t" {
                // タブ文字は1レベル
                indentLevel += 1
                i = prefix.index(after: i)
            } else if char == " " {
                // 連続するスペースをカウント
                var consecutiveSpaces = 0
                var j = i
                while j < prefix.endIndex && prefix[j] == " " {
                    consecutiveSpaces += 1
                    j = prefix.index(after: j)
                }
                
                // 2個以上のスペースを1つのインデントレベルとして扱う
                if consecutiveSpaces >= 2 {
                    // スペース数に応じてレベルを計算
                    // 2個→1レベル、4個→2レベル、6個→3レベル...
                    indentLevel += consecutiveSpaces / 2
                }
                
                // 処理した分だけインデックスを進める
                i = j
            } else {
                // スペースでもタブでもない文字が出現したら終了
                break
            }
        }
        
        return indentLevel
    }
    
}

/// ウィジェット用マークダウン要素
struct WidgetMarkdownElement: Identifiable {
    let id = UUID()
    let view: AnyView
}


private func formatDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ja_JP")
    
    let calendar = Calendar.current
    if calendar.isDateInToday(date) {
        formatter.dateFormat = "HH:mm"
        return "今日 \(formatter.string(from: date))"
    } else if calendar.isDateInYesterday(date) {
        formatter.dateFormat = "HH:mm"
        return "昨日 \(formatter.string(from: date))"
    } else if calendar.isDate(date, equalTo: Date(), toGranularity: .year) {
        formatter.dateFormat = "M/d HH:mm"
        return formatter.string(from: date)
    } else {
        formatter.dateFormat = "yyyy/M/d"
        return formatter.string(from: date)
    }
}

private func formatDueDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ja_JP")
    
    let calendar = Calendar.current
    if calendar.isDateInToday(date) {
        formatter.dateFormat = "HH:mm"
        return "今日 \(formatter.string(from: date))"
    } else if calendar.isDateInTomorrow(date) {
        formatter.dateFormat = "HH:mm"
        return "明日 \(formatter.string(from: date))"
    } else {
        formatter.dateFormat = "M/d HH:mm"
        return formatter.string(from: date)
    }
}

// MARK: - Widget Bundle
@main
struct MemoWidgetBundle: WidgetBundle {
    var body: some Widget {
        AutoMemoWidget()
    }
}

// MARK: - Preview
#Preview(as: .systemSmall) {
    AutoMemoWidget()
} timeline: {
    MemoEntry(date: .now, memo: WidgetMemo(
        id: UUID(),
        title: "サンプルメモ",
        content: "これはサンプルのメモ内容です。ウィジェットでメモをプレビューできます。長いテキストも適切に表示されます。",
        createdAt: Date(),
        updatedAt: Date(),
        dueDate: Date().addingTimeInterval(3600)
    ))
}

#Preview(as: .systemMedium) {
    AutoMemoWidget()
} timeline: {
    MemoEntry(date: .now, memo: WidgetMemo(
        id: UUID(),
        title: "中サイズメモ",
        content: "このウィジェットは最新のメモを自動的に表示します。中サイズでより多くの情報を表示できます。",
        createdAt: Date(),
        updatedAt: Date(),
        dueDate: nil
    ))
}

#Preview(as: .systemLarge) {
    AutoMemoWidget()
} timeline: {
    MemoEntry(date: .now, memo: WidgetMemo(
        id: UUID(),
        title: "大サイズメモウィジェット",
        content: "大きなサイズのウィジェットでは、メモの内容をより詳細に表示できます。長い文章も読みやすく表示され、メモの全体像を把握しやすくなります。作成日時や更新日時などのメタ情報も含めて表示されます。",
        createdAt: Date().addingTimeInterval(-86400),
        updatedAt: Date(),
        dueDate: Date().addingTimeInterval(7200)
    ))
}