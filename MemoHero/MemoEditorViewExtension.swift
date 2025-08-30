import SwiftUI
import Foundation

// MARK: - MemoEditorView拡張（カレンダーインジケーター対応）
/// 既存のMemoEditorViewに新しいカレンダーインジケーター機能を統合する拡張

extension MemoEditorView {
    
    /// 拡張期日設定画面を表示するSheet修飾子
    var withEnhancedDueDatePicker: some View {
        self
            .sheet(isPresented: $showingDueDatePicker) {
                if useEnhancedCalendar {
                    // 新しいカレンダーインジケーター対応版
                    EnhancedDueDatePickerView(
                        dueDate: $tempDueDate,
                        hasPreNotification: $tempHasPreNotification,
                        preNotificationMinutes: $tempPreNotificationMinutes,
                        memos: memoStore.memos, // 全メモデータを提供
                        onSave: { dueDate, hasPreNotification, preNotificationMinutes in
                            saveDueDate(dueDate, hasPreNotification: hasPreNotification, preNotificationMinutes: preNotificationMinutes)
                            showingDueDatePicker = false
                        },
                        onCancel: {
                            showingDueDatePicker = false
                        }
                    )
                } else {
                    // 既存の期日設定画面
                    DueDatePickerView(
                        dueDate: $tempDueDate,
                        hasPreNotification: $tempHasPreNotification,
                        preNotificationMinutes: $tempPreNotificationMinutes,
                        onSave: { dueDate, hasPreNotification, preNotificationMinutes in
                            saveDueDate(dueDate, hasPreNotification: hasPreNotification, preNotificationMinutes: preNotificationMinutes)
                            showingDueDatePicker = false
                        },
                        onCancel: {
                            showingDueDatePicker = false
                        }
                    )
                }
            }
    }
    
    /// 拡張カレンダー機能を使用するかどうかの設定
    private var useEnhancedCalendar: Bool {
        // UserDefaultsで設定を管理
        UserDefaults.standard.bool(forKey: "useEnhancedCalendarIndicators")
    }
}

// MARK: - カレンダーインジケーター設定管理
/// カレンダーインジケーター機能の設定を管理するクラス
class CalendarIndicatorSettings: ObservableObject {
    
    /// シングルトンインスタンス
    static let shared = CalendarIndicatorSettings()
    
    private init() {}
    
    /// カレンダーインジケーター機能を有効にするかどうか
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "useEnhancedCalendarIndicators")
        }
    }
    
    /// 作成日インジケーター（青）を表示するかどうか
    @Published var showCreatedDateIndicators: Bool {
        didSet {
            UserDefaults.standard.set(showCreatedDateIndicators, forKey: "showCreatedDateIndicators")
        }
    }
    
    /// 更新日インジケーター（緑）を表示するかどうか
    @Published var showUpdatedDateIndicators: Bool {
        didSet {
            UserDefaults.standard.set(showUpdatedDateIndicators, forKey: "showUpdatedDateIndicators")
        }
    }
    
    /// 期日インジケーター（赤）を表示するかどうか
    @Published var showDueDateIndicators: Bool {
        didSet {
            UserDefaults.standard.set(showDueDateIndicators, forKey: "showDueDateIndicators")
        }
    }
    
    /// インジケーターのサイズ
    @Published var indicatorSize: CGFloat {
        didSet {
            UserDefaults.standard.set(indicatorSize, forKey: "calendarIndicatorSize")
        }
    }
    
    init() {
        self.isEnabled = UserDefaults.standard.object(forKey: "useEnhancedCalendarIndicators") as? Bool ?? true
        self.showCreatedDateIndicators = UserDefaults.standard.object(forKey: "showCreatedDateIndicators") as? Bool ?? true
        self.showUpdatedDateIndicators = UserDefaults.standard.object(forKey: "showUpdatedDateIndicators") as? Bool ?? true
        self.showDueDateIndicators = UserDefaults.standard.object(forKey: "showDueDateIndicators") as? Bool ?? true
        self.indicatorSize = UserDefaults.standard.object(forKey: "calendarIndicatorSize") as? CGFloat ?? 4.0
    }
}

// MARK: - カレンダーインジケーター設定画面
/// カレンダーインジケーター機能の設定画面
struct CalendarIndicatorSettingsView: View {
    @StateObject private var settings = CalendarIndicatorSettings.shared
    @State private var showingPreview = false
    
    var body: some View {
        NavigationView {
            Form {
                // 基本設定セクション
                basicSettingsSection
                
                // 表示設定セクション
                displaySettingsSection
                
                // プレビューセクション
                previewSection
                
                // 説明セクション
                descriptionSection
            }
            .navigationTitle("カレンダー設定")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    // MARK: - 基本設定セクション
    private var basicSettingsSection: some View {
        Section("基本設定") {
            Toggle("カレンダーインジケーター機能", isOn: $settings.isEnabled)
                .onChange(of: settings.isEnabled) { _, newValue in
                    if newValue {
                        // 有効化時のハプティックフィードバック
                        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                        impactFeedback.impactOccurred()
                    }
                }
            
            if !settings.isEnabled {
                Text("カレンダーの日付に小さい⚫︎が表示されなくなります")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - 表示設定セクション
    private var displaySettingsSection: some View {
        Section("表示設定") {
            Group {
                HStack {
                    Toggle("作成日", isOn: $settings.showCreatedDateIndicators)
                    Spacer()
                    Circle()
                        .fill(Color.blue)
                        .frame(width: settings.indicatorSize, height: settings.indicatorSize)
                }
                .disabled(!settings.isEnabled)
                
                HStack {
                    Toggle("更新日", isOn: $settings.showUpdatedDateIndicators)
                    Spacer()
                    Circle()
                        .fill(Color.green)
                        .frame(width: settings.indicatorSize, height: settings.indicatorSize)
                }
                .disabled(!settings.isEnabled)
                
                HStack {
                    Toggle("期日", isOn: $settings.showDueDateIndicators)
                    Spacer()
                    Circle()
                        .fill(Color.red)
                        .frame(width: settings.indicatorSize, height: settings.indicatorSize)
                }
                .disabled(!settings.isEnabled)
            }
            .opacity(settings.isEnabled ? 1.0 : 0.6)
            
            // インジケーターサイズ調整
            if settings.isEnabled {
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
            .disabled(!settings.isEnabled)
            
            if showingPreview && settings.isEnabled {
                calendarPreview
                    .padding(.vertical, 8)
            }
        }
    }
    
    // MARK: - 説明セクション
    private var descriptionSection: some View {
        Section("説明") {
            VStack(alignment: .leading, spacing: 8) {
                descriptionRow(
                    color: .blue,
                    title: "作成日（青）",
                    description: "メモが作成された日にちに表示されます"
                )
                
                descriptionRow(
                    color: .green,
                    title: "更新日（緑）",
                    description: "メモが更新された日にちに表示されます（作成日と異なる場合のみ）"
                )
                
                descriptionRow(
                    color: .red,
                    title: "期日（赤）",
                    description: "メモに期日が設定された日にちに表示されます"
                )
            }
        }
    }
    
    private func descriptionRow(color: Color, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
                .padding(.top, 6)
            
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
            
            // 簡易カレンダーグリッド（3×3で9日分）
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                ForEach(1...9, id: \.self) { day in
                    previewCalendarCell(day: day)
                }
            }
            .padding(.horizontal, 40)
        }
    }
    
    private func previewCalendarCell(day: Int) -> some View {
        VStack(spacing: 2) {
            Text("\(day)")
                .font(.caption)
                .fontWeight(.medium)
            
            // サンプルインジケーター
            HStack(spacing: 1) {
                if day % 3 == 1 && settings.showCreatedDateIndicators {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: settings.indicatorSize, height: settings.indicatorSize)
                }
                
                if day % 3 == 2 && settings.showUpdatedDateIndicators {
                    Circle()
                        .fill(Color.green)
                        .frame(width: settings.indicatorSize, height: settings.indicatorSize)
                }
                
                if day % 3 == 0 && settings.showDueDateIndicators {
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

// MARK: - MemoListView拡張
extension MemoListView {
    
    /// カレンダータブ表示機能付きのMemoListView
    var withCalendarTab: some View {
        TabView {
            // メモリストタブ
            self
                .tabItem {
                    Image(systemName: "note.text")
                    Text("メモ")
                }
                .tag(0)
            
            // カレンダータブ
            MemoCalendarIntegrationView()
                .tabItem {
                    Image(systemName: "calendar")
                    Text("カレンダー")
                }
                .tag(1)
            
            // 設定タブ
            CalendarIndicatorSettingsView()
                .tabItem {
                    Image(systemName: "gear")
                    Text("設定")
                }
                .tag(2)
        }
    }
}

// MARK: - ContentView拡張
extension ContentView {
    
    /// カレンダーインジケーター機能付きのContentView
    var withCalendarIndicators: some View {
        TabView {
            // メモ一覧（既存）
            NavigationStack {
                VStack(spacing: 0) {
                    TopSyncStatusBar()
                    MemoListView(memoStore: memoStore, folderStore: folderStore)
                        .withPullToRefresh
                }
            }
            .tabItem {
                Image(systemName: "note.text")
                Text("メモ")
            }
            .tag(0)
            
            // カレンダー表示（新機能）
            NavigationStack {
                MemoCalendarIntegrationView()
            }
            .tabItem {
                Image(systemName: "calendar")
                Text("カレンダー")
            }
            .tag(1)
            
            // 設定（既存 + 新機能設定）
            NavigationStack {
                Form {
                    // 既存の設定項目
                    SyncSettingsView()
                    
                    // カレンダーインジケーター設定
                    Section {
                        NavigationLink(destination: CalendarIndicatorSettingsView()) {
                            HStack {
                                Image(systemName: "calendar.badge.clock")
                                    .foregroundColor(.blue)
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
            .tag(2)
        }
    }
}

// MARK: - Preview
struct MemoEditorViewExtension_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // カレンダーインジケーター設定画面
            CalendarIndicatorSettingsView()
                .previewDisplayName("設定画面")
            
            // カレンダー統合画面
            MemoCalendarIntegrationView()
                .previewDisplayName("カレンダー統合画面")
        }
    }
}