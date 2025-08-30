import SwiftUI
import Foundation

// MARK: - MemoListView拡張（カレンダーインジケーター対応）
/// 既存のMemoListViewのカレンダー機能を拡張

extension MemoListView {
    
    /// インジケーター付きカレンダーを使用するかどうかの設定
    private var useIndicatorCalendar: Bool {
        UserDefaults.standard.object(forKey: "useEnhancedCalendarIndicators") as? Bool ?? true
    }
    
    /// カレンダーインジケーター機能付きのMemoListView
    var withCalendarIndicators: some View {
        self
            .sheet(isPresented: Binding(
                get: { showingCalendar },
                set: { _ in }
            )) {
                if useIndicatorCalendar {
                    // 新しいインジケーター付きカレンダー
                    CustomCalendarWithIndicators(memos: memoStore.memos) { memo in
                        showingCalendar = false
                        presentedMemo = memo
                    }
                } else {
                    // 既存のカレンダー
                    CalendarView(memos: memoStore.memos) { memo in
                        showingCalendar = false
                        presentedMemo = memo
                    }
                }
            }
    }
}

// MARK: - カレンダー設定管理
/// カレンダーインジケーター機能の設定を一元管理
class EnhancedCalendarSettings: ObservableObject {
    
    static let shared = EnhancedCalendarSettings()
    
    @Published var useEnhancedCalendar: Bool {
        didSet {
            UserDefaults.standard.set(useEnhancedCalendar, forKey: "useEnhancedCalendarIndicators")
        }
    }
    
    @Published var showCreatedIndicators: Bool {
        didSet {
            UserDefaults.standard.set(showCreatedIndicators, forKey: "showCreatedDateIndicators")
        }
    }
    
    @Published var showUpdatedIndicators: Bool {
        didSet {
            UserDefaults.standard.set(showUpdatedIndicators, forKey: "showUpdatedDateIndicators")
        }
    }
    
    @Published var showDueIndicators: Bool {
        didSet {
            UserDefaults.standard.set(showDueIndicators, forKey: "showDueDateIndicators")
        }
    }
    
    @Published var indicatorSize: Double {
        didSet {
            UserDefaults.standard.set(indicatorSize, forKey: "calendarIndicatorSize")
        }
    }
    
    private init() {
        self.useEnhancedCalendar = UserDefaults.standard.object(forKey: "useEnhancedCalendarIndicators") as? Bool ?? true
        self.showCreatedIndicators = UserDefaults.standard.object(forKey: "showCreatedDateIndicators") as? Bool ?? true
        self.showUpdatedIndicators = UserDefaults.standard.object(forKey: "showUpdatedDateIndicators") as? Bool ?? true
        self.showDueIndicators = UserDefaults.standard.object(forKey: "showDueDateIndicators") as? Bool ?? true
        self.indicatorSize = UserDefaults.standard.object(forKey: "calendarIndicatorSize") as? Double ?? 4.0
    }
}

// MARK: - カレンダー設定画面
struct EnhancedCalendarSettingsView: View {
    @StateObject private var settings = EnhancedCalendarSettings.shared
    @State private var showingPreview = false
    
    var body: some View {
        NavigationView {
            Form {
                // 基本設定
                basicSettingsSection
                
                // インジケーター設定
                indicatorSettingsSection
                
                // プレビューセクション
                previewSection
                
                // 説明セクション
                explanationSection
            }
            .navigationTitle("カレンダー設定")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    // MARK: - 基本設定セクション
    private var basicSettingsSection: some View {
        Section("基本設定") {
            Toggle("拡張カレンダー機能", isOn: $settings.useEnhancedCalendar)
                .onChange(of: settings.useEnhancedCalendar) { _, newValue in
                    if newValue {
                        // 有効化時のハプティックフィードバック
                        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                        impactFeedback.impactOccurred()
                    }
                }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("拡張カレンダー機能について")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text("カレンダーの日付の下に小さい⚫︎でメモの存在を表示します。期日（赤）、作成日（青）、更新日（緑）で色分けされます。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
        }
    }
    
    // MARK: - インジケーター設定セクション
    private var indicatorSettingsSection: some View {
        Section("インジケーター表示") {
            Group {
                HStack {
                    Toggle("作成日", isOn: $settings.showCreatedIndicators)
                    Spacer()
                    Circle()
                        .fill(Color.blue)
                        .frame(width: settings.indicatorSize, height: settings.indicatorSize)
                }
                .disabled(!settings.useEnhancedCalendar)
                
                HStack {
                    Toggle("更新日", isOn: $settings.showUpdatedIndicators)
                    Spacer()
                    Circle()
                        .fill(Color.green)
                        .frame(width: settings.indicatorSize, height: settings.indicatorSize)
                }
                .disabled(!settings.useEnhancedCalendar)
                
                HStack {
                    Toggle("期日", isOn: $settings.showDueIndicators)
                    Spacer()
                    Circle()
                        .fill(Color.red)
                        .frame(width: settings.indicatorSize, height: settings.indicatorSize)
                }
                .disabled(!settings.useEnhancedCalendar)
            }
            .opacity(settings.useEnhancedCalendar ? 1.0 : 0.6)
            
            // サイズ調整
            if settings.useEnhancedCalendar {
                VStack(alignment: .leading, spacing: 8) {
                    Text("インジケーターサイズ")
                        .font(.subheadline)
                    
                    HStack {
                        Text("小")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Slider(value: $settings.indicatorSize, in: 2...8, step: 0.5)
                        
                        Text("大")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Circle()
                            .fill(Color.blue)
                            .frame(width: settings.indicatorSize, height: settings.indicatorSize)
                    }
                }
            }
        }
    }
    
    // MARK: - プレビューセクション
    private var previewSection: some View {
        Section("プレビュー") {
            Button(action: {
                showingPreview.toggle()
            }) {
                HStack {
                    Image(systemName: "eye")
                        .foregroundColor(.blue)
                    
                    Text("プレビューを表示")
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Image(systemName: showingPreview ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }
            .buttonStyle(.plain)
            .disabled(!settings.useEnhancedCalendar)
            
            if showingPreview && settings.useEnhancedCalendar {
                calendarPreview
                    .padding(.vertical, 8)
            }
        }
    }
    
    // MARK: - 説明セクション
    private var explanationSection: some View {
        Section("インジケーターの意味") {
            VStack(spacing: 12) {
                explanationRow(
                    color: .blue,
                    title: "作成日（青い⚫︎）",
                    description: "メモが作成された日付に表示されます"
                )
                
                explanationRow(
                    color: .green,
                    title: "更新日（緑の⚫︎）",
                    description: "メモが更新された日付に表示されます（作成日と異なる場合のみ）"
                )
                
                explanationRow(
                    color: .red,
                    title: "期日（赤い⚫︎）",
                    description: "メモに期日が設定された日付に表示されます"
                )
            }
        }
    }
    
    private func explanationRow(color: Color, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .padding(.top, 4)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - カレンダープレビュー
    private var calendarPreview: some View {
        VStack(spacing: 8) {
            Text("カレンダープレビュー")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            
            // 簡易カレンダーグリッド（3×3）
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                ForEach(1...9, id: \.self) { day in
                    previewCell(day: day)
                }
            }
            .padding(.horizontal, 40)
        }
    }
    
    private func previewCell(day: Int) -> some View {
        VStack(spacing: 3) {
            Text("\(day)")
                .font(.caption)
                .fontWeight(.medium)
            
            // サンプルインジケーター
            HStack(spacing: 1) {
                if day % 3 == 1 && settings.showCreatedIndicators {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: settings.indicatorSize, height: settings.indicatorSize)
                }
                
                if day % 3 == 2 && settings.showUpdatedIndicators {
                    Circle()
                        .fill(Color.green)
                        .frame(width: settings.indicatorSize, height: settings.indicatorSize)
                }
                
                if day % 3 == 0 && settings.showDueIndicators {
                    Circle()
                        .fill(Color.red)
                        .frame(width: settings.indicatorSize, height: settings.indicatorSize)
                }
            }
            .frame(height: max(settings.indicatorSize, 6))
        }
        .frame(width: 32, height: 40)
        .background(Color(UIColor.systemGray6))
        .cornerRadius(4)
    }
}

// MARK: - 簡単な統合用View
/// MemoListViewとカレンダー機能を簡単に統合するためのView
struct MemoListWithEnhancedCalendar: View {
    @StateObject private var memoStore = MemoStore()
    @StateObject private var folderStore = FolderStore()
    
    var body: some View {
        MemoListView(memoStore: memoStore, folderStore: folderStore)
            .withCalendarIndicators
    }
}

// MARK: - 設定統合のためのContentView拡張
extension ContentView {
    
    /// カレンダーインジケーター設定を既存の設定画面に統合
    var withEnhancedCalendarSettings: some View {
        TabView {
            // メモ一覧タブ
            NavigationStack {
                VStack(spacing: 0) {
                    TopSyncStatusBar()
                    MemoListView(memoStore: memoStore, folderStore: folderStore)
                        .withCalendarIndicators // インジケーター機能を追加
                }
            }
            .tabItem {
                Image(systemName: "note.text")
                Text("メモ")
            }
            .tag(0)
            
            // 設定タブ（カレンダー設定を追加）
            NavigationStack {
                Form {
                    // 既存設定項目
                    Section("同期設定") {
                        // 既存の同期設定項目
                        NavigationLink(destination: SyncSettingsView()) {
                            HStack {
                                Image(systemName: "icloud")
                                    .foregroundColor(.blue)
                                Text("同期設定")
                            }
                        }
                    }
                    
                    // カレンダー設定項目（新規追加）
                    Section("表示設定") {
                        NavigationLink(destination: EnhancedCalendarSettingsView()) {
                            HStack {
                                Image(systemName: "calendar.badge.clock")
                                    .foregroundColor(.red)
                                Text("カレンダーインジケーター")
                            }
                        }
                    }
                }
                .navigationTitle("設定")
            }
            .tabItem {
                Image(systemName: "gear")
                Text("設定")
            }
            .tag(1)
        }
    }
}

// MARK: - テスト用のサンプルView
struct CalendarIndicatorTestView: View {
    @State private var testMemos: [Memo] = []
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("カレンダーインジケーターテスト")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                // テストデータ作成ボタン
                Button("テストデータを作成") {
                    createTestMemos()
                }
                .buttonStyle(.borderedProminent)
                
                // カレンダー表示
                if !testMemos.isEmpty {
                    CustomCalendarWithIndicators(memos: testMemos) { memo in
                        print("Selected memo: \(memo.title)")
                    }
                }
                
                Spacer()
            }
            .padding()
        }
        .onAppear {
            createTestMemos()
        }
    }
    
    private func createTestMemos() {
        let calendar = Calendar.current
        testMemos = [
            // 今日作成されたメモ
            Memo(title: "今日のタスク", content: "今日作成されたメモです"),
            
            // 昨日作成、今日更新されたメモ
            {
                var memo = Memo(title: "更新されたメモ", content: "昨日作成、今日更新されたメモです")
                memo.createdAt = calendar.date(byAdding: .day, value: -1, to: Date()) ?? Date()
                memo.updatedAt = Date()
                return memo
            }(),
            
            // 明日が期日のメモ
            Memo(title: "明日の期日", content: "明日が期日のメモです", dueDate: calendar.date(byAdding: .day, value: 1, to: Date())),
            
            // 1週間後が期日のメモ
            Memo(title: "来週の期日", content: "1週間後が期日のメモです", dueDate: calendar.date(byAdding: .weekOfYear, value: 1, to: Date())),
            
            // 3日前に作成されたメモ
            {
                var memo = Memo(title: "3日前のメモ", content: "3日前に作成されたメモです")
                memo.createdAt = calendar.date(byAdding: .day, value: -3, to: Date()) ?? Date()
                memo.updatedAt = memo.createdAt
                return memo
            }()
        ]
    }
}

// MARK: - Preview
struct MemoListViewCalendarExtension_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // 設定画面
            EnhancedCalendarSettingsView()
                .previewDisplayName("設定画面")
            
            // テスト画面
            CalendarIndicatorTestView()
                .previewDisplayName("テスト画面")
            
            // 統合MemoListView
            MemoListWithEnhancedCalendar()
                .previewDisplayName("統合メモリスト")
        }
    }
}