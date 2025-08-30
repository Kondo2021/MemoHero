import SwiftUI
import Foundation

// MARK: - 実装確認用のメインView
/// カレンダーインジケーター機能が正しく動作することを確認するためのView

@main
struct CalendarIndicatorTestApp: App {
    var body: some Scene {
        WindowGroup {
            CalendarIndicatorDemoView()
        }
    }
}

// MARK: - デモ用メインView
struct CalendarIndicatorDemoView: View {
    @StateObject private var memoStore = MemoStore()
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // メモリストタブ（既存機能 + インジケーター対応カレンダー）
            NavigationStack {
                MemoListView(memoStore: memoStore, folderStore: FolderStore())
                    .withCalendarIndicators // ★ここが重要！インジケーター機能を追加
            }
            .tabItem {
                Image(systemName: "note.text")
                Text("メモ")
            }
            .tag(0)
            
            // カレンダー専用タブ
            NavigationStack {
                CustomCalendarWithIndicators(memos: memoStore.memos) { memo in
                    print("Selected memo: \(memo.title)")
                }
            }
            .tabItem {
                Image(systemName: "calendar")
                Text("カレンダー")
            }
            .tag(1)
            
            // 設定タブ
            NavigationStack {
                EnhancedCalendarSettingsView()
            }
            .tabItem {
                Image(systemName: "gear")
                Text("設定")
            }
            .tag(2)
            
            // テスト用タブ
            NavigationStack {
                CalendarIndicatorTestView()
            }
            .tabItem {
                Image(systemName: "testtube.2")
                Text("テスト")
            }
            .tag(3)
        }
        .onAppear {
            setupTestData()
        }
    }
    
    // MARK: - テストデータセットアップ
    private func setupTestData() {
        // 既存のメモをクリア
        memoStore.memos.removeAll()
        
        let calendar = Calendar.current
        
        // テスト用メモデータを作成
        let testMemos: [Memo] = [
            // 今日作成されたメモ
            Memo(title: "今日のタスク", content: "今日作成されたメモです。青い⚫︎が表示されるはずです。"),
            
            // 昨日作成、今日更新されたメモ
            {
                var memo = Memo(title: "更新されたメモ", content: "昨日作成、今日更新されたメモです。緑の⚫︎が今日に表示されるはずです。")
                memo.createdAt = calendar.date(byAdding: .day, value: -1, to: Date()) ?? Date()
                memo.updatedAt = Date()
                return memo
            }(),
            
            // 明日が期日のメモ
            Memo(title: "明日の会議", content: "明日が期日のメモです。赤い⚫︎が明日に表示されるはずです。", 
                 dueDate: calendar.date(byAdding: .day, value: 1, to: Date())),
            
            // 今日が期日のメモ
            Memo(title: "今日の締切", content: "今日が期日のメモです。赤い⚫︎が今日に表示されるはずです。", 
                 dueDate: Date()),
            
            // 1週間後が期日のメモ
            Memo(title: "来週のプレゼン", content: "1週間後が期日のメモです。", 
                 dueDate: calendar.date(byAdding: .weekOfYear, value: 1, to: Date())),
            
            // 3日前に作成されたメモ
            {
                var memo = Memo(title: "3日前のメモ", content: "3日前に作成されたメモです。")
                memo.createdAt = calendar.date(byAdding: .day, value: -3, to: Date()) ?? Date()
                memo.updatedAt = memo.createdAt
                return memo
            }(),
            
            // 複数の日付種別が重複するメモ
            {
                var memo = Memo(title: "複合メモ", content: "今日作成、今日が期日のメモです。青と赤の⚫︎が表示されるはず。", 
                                dueDate: Date())
                return memo
            }()
        ]
        
        // メモストアに追加
        testMemos.forEach { memo in
            memoStore.memos.append(memo)
        }
        
        print("✅ テストデータを作成しました: \(memoStore.memos.count)件のメモ")
        
        // 各日付のメモ分布をログ出力
        logMemoDistribution()
    }
    
    // MARK: - メモ分布ログ出力
    private func logMemoDistribution() {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "M/d"
        
        print("\n📅 メモの日付分布:")
        
        // 日付ごとにメモを分類
        var dateMemos: [String: [String]] = [:]
        
        for memo in memoStore.memos {
            // 作成日
            let createdDateKey = formatter.string(from: memo.createdAt)
            if dateMemos[createdDateKey] == nil {
                dateMemos[createdDateKey] = []
            }
            dateMemos[createdDateKey]?.append("🔵 作成: \(memo.title)")
            
            // 更新日（作成日と異なる場合）
            if !calendar.isDate(memo.createdAt, inSameDayAs: memo.updatedAt) {
                let updatedDateKey = formatter.string(from: memo.updatedAt)
                if dateMemos[updatedDateKey] == nil {
                    dateMemos[updatedDateKey] = []
                }
                dateMemos[updatedDateKey]?.append("🟢 更新: \(memo.title)")
            }
            
            // 期日
            if let dueDate = memo.dueDate {
                let dueDateKey = formatter.string(from: dueDate)
                if dateMemos[dueDateKey] == nil {
                    dateMemos[dueDateKey] = []
                }
                dateMemos[dueDateKey]?.append("🔴 期日: \(memo.title)")
            }
        }
        
        // ソートして出力
        let sortedDates = dateMemos.keys.sorted()
        for dateKey in sortedDates {
            print("  \(dateKey): \(dateMemos[dateKey]?.joined(separator: ", ") ?? "")")
        }
        
        print("\n🎯 期待される表示:")
        print("  - カレンダーの各日付の下に、該当する色の小さい⚫︎が表示される")
        print("  - 青⚫︎: 作成日, 緑⚫︎: 更新日, 赤⚫︎: 期日")
        print("  - 同じ日に複数種類がある場合は横並び表示（例: 🔵🔴）")
    }
}

// MARK: - 検証用の個別機能テストView
struct IndividualFeatureTestView: View {
    @StateObject private var indicatorManager = CalendarDateIndicatorManager()
    @State private var testDate = Date()
    @State private var testMemos: [Memo] = []
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    Text("個別機能テスト")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    // インジケーターマネージャーテスト
                    indicatorManagerTest
                    
                    // 日付セルテスト
                    dateCellTest
                    
                    // カレンダーグリッドテスト
                    calendarGridTest
                }
                .padding()
            }
        }
        .onAppear {
            setupTestMemos()
        }
    }
    
    // MARK: - インジケーターマネージャーテスト
    private var indicatorManagerTest: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CalendarDateIndicatorManager テスト")
                .font(.headline)
            
            Button("テストデータ更新") {
                indicatorManager.updateIndicators(from: testMemos)
                print("✅ インジケーターデータ更新完了")
                print("   管理対象日数: \(indicatorManager.dateIndicators.count)")
            }
            .buttonStyle(.borderedProminent)
            
            Text("管理対象日数: \(indicatorManager.dateIndicators.count)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(UIColor.systemGray6))
        .cornerRadius(8)
    }
    
    // MARK: - 日付セルテスト
    private var dateCellTest: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CalendarDateCellWithIndicators テスト")
                .font(.headline)
            
            HStack(spacing: 16) {
                ForEach([Date(), 
                        Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date(),
                        Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
                       ], id: \.self) { date in
                    
                    CalendarDateCellWithIndicators(
                        date: date,
                        isSelected: Calendar.current.isDate(date, inSameDayAs: testDate),
                        isToday: Calendar.current.isDateInToday(date),
                        isCurrentMonth: true,
                        indicatorManager: indicatorManager,
                        onDateTapped: { selectedDate in
                            testDate = selectedDate
                            print("📅 選択された日付: \(selectedDate)")
                        }
                    )
                }
            }
        }
        .padding()
        .background(Color(UIColor.systemGray6))
        .cornerRadius(8)
    }
    
    // MARK: - カレンダーグリッドテスト
    private var calendarGridTest: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("簡易カレンダーグリッド テスト")
                .font(.headline)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 4) {
                ForEach(1...14, id: \.self) { day in
                    let date = Calendar.current.date(byAdding: .day, value: day - 7, to: Date()) ?? Date()
                    
                    CalendarDateCellWithIndicators(
                        date: date,
                        isSelected: false,
                        isToday: Calendar.current.isDateInToday(date),
                        isCurrentMonth: true,
                        indicatorManager: indicatorManager,
                        onDateTapped: { _ in }
                    )
                }
            }
        }
        .padding()
        .background(Color(UIColor.systemGray6))
        .cornerRadius(8)
    }
    
    // MARK: - テストメモセットアップ
    private func setupTestMemos() {
        let calendar = Calendar.current
        
        testMemos = [
            // 今日
            Memo(title: "今日のメモ", content: "今日作成", dueDate: Date()),
            
            // 明日
            {
                var memo = Memo(title: "明日のメモ", content: "明日が期日")
                memo.dueDate = calendar.date(byAdding: .day, value: 1, to: Date())
                return memo
            }(),
            
            // 昨日作成、今日更新
            {
                var memo = Memo(title: "更新メモ", content: "昨日作成、今日更新")
                memo.createdAt = calendar.date(byAdding: .day, value: -1, to: Date()) ?? Date()
                memo.updatedAt = Date()
                return memo
            }()
        ]
        
        indicatorManager.updateIndicators(from: testMemos)
    }
}

// MARK: - 使用方法説明View
struct UsageInstructionsView: View {
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("カレンダーインジケーター使用方法")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    // ステップ1
                    instructionStep(
                        number: "1",
                        title: "機能を有効にする",
                        description: "設定タブで「拡張カレンダー機能」をオンにします"
                    )
                    
                    // ステップ2
                    instructionStep(
                        number: "2",
                        title: "カレンダーを表示する",
                        description: "メモリスト画面のカレンダーボタンをタップします"
                    )
                    
                    // ステップ3
                    instructionStep(
                        number: "3",
                        title: "インジケーターを確認する",
                        description: "各日付の数字の下に小さい⚫︎が表示されます"
                    )
                    
                    // インジケーターの意味
                    VStack(alignment: .leading, spacing: 8) {
                        Text("インジケーターの意味")
                            .font(.headline)
                        
                        indicatorMeaning(color: .blue, text: "作成日")
                        indicatorMeaning(color: .green, text: "更新日")
                        indicatorMeaning(color: .red, text: "期日")
                    }
                    .padding()
                    .background(Color(UIColor.systemGray6))
                    .cornerRadius(8)
                    
                    // トラブルシューティング
                    VStack(alignment: .leading, spacing: 8) {
                        Text("⚫︎が表示されない場合")
                            .font(.headline)
                            .foregroundColor(.red)
                        
                        Text("1. 設定で「拡張カレンダー機能」がオンになっているか確認")
                        Text("2. メモが実際に存在するか確認")
                        Text("3. アプリを再起動してみる")
                        Text("4. テストタブでテストデータを確認")
                    }
                    .padding()
                    .background(Color(UIColor.systemRed).opacity(0.1))
                    .cornerRadius(8)
                }
                .padding()
            }
        }
        .navigationTitle("使用方法")
    }
    
    private func instructionStep(number: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
                .background(Color.blue)
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Text(description)
                    .font(.body)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func indicatorMeaning(color: Color, text: String) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            
            Text("\(text): メモが\(text == "作成日" ? "作成" : text == "更新日" ? "更新" : "期日に設定")された日")
                .font(.body)
        }
    }
}

// MARK: - Preview
struct CalendarIndicatorImplementation_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // メインデモ
            CalendarIndicatorDemoView()
                .previewDisplayName("メインデモ")
            
            // 個別機能テスト
            IndividualFeatureTestView()
                .previewDisplayName("個別機能テスト")
            
            // 使用方法
            UsageInstructionsView()
                .previewDisplayName("使用方法")
        }
    }
}