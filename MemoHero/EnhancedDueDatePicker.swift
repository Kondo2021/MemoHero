import SwiftUI
import Foundation

// MARK: - 拡張期日選択View（カレンダーインジケーター対応）
/// 既存のDueDatePickerViewを拡張し、メモの日付インジケーター機能を統合

struct EnhancedDueDatePickerView: View {
    @Binding var dueDate: Date
    @Binding var hasPreNotification: Bool
    @Binding var preNotificationMinutes: Int
    let memos: [Memo] // 全メモデータ（インジケーター表示用）
    let onSave: (Date, Bool, Int) -> Void
    let onCancel: () -> Void
    
    @StateObject private var indicatorManager = CalendarDateIndicatorManager()
    @State private var selectedCalendarDate: Date?
    @State private var showingCalendarView = false
    
    private let preNotificationOptions = [
        (5, "5分前"),
        (15, "15分前"),
        (30, "30分前"),
        (60, "1時間前"),
        (120, "2時間前"),
        (1440, "1日前")
    ]
    
    var body: some View {
        NavigationView {
            Form {
                // 期日設定セクション
                dueDateSection
                
                // カレンダー表示セクション
                calendarSection
                
                // 通知設定セクション
                notificationSection
                
                // 期日情報セクション
                dueDateInfoSection
            }
            .navigationTitle("期日設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("キャンセル", action: onCancel)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") {
                        onSave(dueDate, hasPreNotification, preNotificationMinutes)
                    }
                    .fontWeight(.medium)
                }
            }
        }
        .onAppear {
            indicatorManager.updateIndicators(from: memos)
        }
    }
    
    // MARK: - 期日設定セクション
    private var dueDateSection: some View {
        Section("期日") {
            DatePicker(
                "日時",
                selection: $dueDate,
                displayedComponents: [.date, .hourAndMinute]
            )
            .datePickerStyle(.graphical)
            .environment(\.locale, Locale(identifier: "ja_JP"))
            .onChange(of: dueDate) { _, newDate in
                selectedCalendarDate = newDate
            }
        }
    }
    
    // MARK: - カレンダー表示セクション
    private var calendarSection: some View {
        Section("カレンダー表示") {
            Button(action: {
                showingCalendarView.toggle()
            }) {
                HStack {
                    Image(systemName: "calendar")
                        .foregroundColor(.blue)
                    
                    Text(showingCalendarView ? "月間カレンダーを非表示" : "月間カレンダーを表示")
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Image(systemName: showingCalendarView ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }
            .buttonStyle(.plain)
            
            if showingCalendarView {
                VStack(spacing: 16) {
                    // インジケーター付きカレンダー
                    EnhancedMonthlyCalendarView(
                        memos: memos,
                        onDateSelected: { selectedDate in
                            dueDate = selectedDate
                            selectedCalendarDate = selectedDate
                            
                            // 選択時のハプティックフィードバック
                            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                            impactFeedback.impactOccurred()
                        }
                    )
                    
                    // 凡例
                    calendarLegend
                }
                .padding(.vertical, 8)
            }
        }
    }
    
    // MARK: - 通知設定セクション
    private var notificationSection: some View {
        Section("通知設定") {
            Toggle("予備通知", isOn: $hasPreNotification)
                .onChange(of: hasPreNotification) { _, newValue in
                    if !newValue {
                        preNotificationMinutes = 0
                    } else if preNotificationMinutes == 0 {
                        preNotificationMinutes = 60 // デフォルト1時間前
                    }
                }
            
            if hasPreNotification {
                Picker("通知タイミング", selection: $preNotificationMinutes) {
                    ForEach(preNotificationOptions, id: \.0) { minutes, title in
                        Text(title).tag(minutes)
                    }
                }
                .pickerStyle(.menu)
            }
            
            HStack {
                Text("期日時刻に通知")
                Spacer()
                Image(systemName: "bell")
                    .foregroundColor(.blue)
            }
            .foregroundColor(.secondary)
            .font(.caption)
        }
    }
    
    // MARK: - 期日情報セクション
    private var dueDateInfoSection: some View {
        Section("期日情報") {
            VStack(alignment: .leading, spacing: 8) {
                // 選択された日付の情報
                selectedDateInfo
                
                // 選択された日付のメモ詳細
                if let selectedDate = selectedCalendarDate {
                    CalendarDateDetailView(
                        date: selectedDate,
                        memos: memos,
                        indicatorManager: indicatorManager
                    )
                }
            }
        }
    }
    
    // MARK: - カレンダー凡例
    private var calendarLegend: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("凡例")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            
            HStack(spacing: 16) {
                legendItem(color: .blue, text: "作成日", icon: "plus.circle.fill")
                legendItem(color: .green, text: "更新日", icon: "pencil.circle.fill")
                legendItem(color: .red, text: "期日", icon: "calendar.circle.fill")
            }
        }
        .padding(.horizontal, 4)
    }
    
    private func legendItem(color: Color, text: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.caption2)
            
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            
            Text(text)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - 選択日付情報
    private var selectedDateInfo: some View {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateStyle = .full
        formatter.timeStyle = .short
        
        return VStack(alignment: .leading, spacing: 4) {
            Text("選択された期日")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            
            HStack {
                Image(systemName: "calendar.badge.clock")
                    .foregroundColor(.red)
                
                Text(formatter.string(from: dueDate))
                    .font(.subheadLine)
                    .fontWeight(.medium)
                
                Spacer()
                
                // 期日までの残り時間
                remainingTimeView
            }
        }
        .padding(.vertical, 4)
    }
    
    private var remainingTimeView: some View {
        let timeInterval = dueDate.timeIntervalSinceNow
        
        return Group {
            if timeInterval > 0 {
                // 未来の期日
                Text("残り\(formatTimeInterval(timeInterval))")
                    .font(.caption)
                    .foregroundColor(.blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
            } else {
                // 過去の期日
                Text("\(formatTimeInterval(-timeInterval))前")
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
            }
        }
    }
    
    private func formatTimeInterval(_ interval: TimeInterval) -> String {
        let days = Int(interval) / 86400
        let hours = Int(interval) % 86400 / 3600
        let minutes = Int(interval) % 3600 / 60
        
        if days > 0 {
            return "\(days)日"
        } else if hours > 0 {
            return "\(hours)時間"
        } else {
            return "\(minutes)分"
        }
    }
}

// MARK: - MemoStore拡張（期日設定統合用）
extension MemoStore {
    /// 拡張期日設定画面を表示するためのメソッド
    func presentEnhancedDueDatePicker(
        for memo: Memo,
        dueDate: Binding<Date>,
        hasPreNotification: Binding<Bool>,
        preNotificationMinutes: Binding<Int>,
        onSave: @escaping (Date, Bool, Int) -> Void,
        onCancel: @escaping () -> Void
    ) -> some View {
        EnhancedDueDatePickerView(
            dueDate: dueDate,
            hasPreNotification: hasPreNotification,
            preNotificationMinutes: preNotificationMinutes,
            memos: memos, // 全メモデータを提供
            onSave: onSave,
            onCancel: onCancel
        )
    }
}

// MARK: - カレンダー統合View
/// メモリストとカレンダーを統合した表示
struct MemoCalendarIntegrationView: View {
    @StateObject private var memoStore = MemoStore()
    @StateObject private var indicatorManager = CalendarDateIndicatorManager()
    @State private var selectedDate: Date?
    @State private var showingDateDetail = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // カレンダー表示
                EnhancedMonthlyCalendarView(
                    memos: memoStore.memos,
                    onDateSelected: { date in
                        selectedDate = date
                        showingDateDetail = true
                    }
                )
                .padding()
                
                Divider()
                
                // メモリスト
                List {
                    ForEach(memoStore.memos) { memo in
                        MemoRowWithDateIndicators(memo: memo)
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("メモカレンダー")
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                indicatorManager.updateIndicators(from: memoStore.memos)
            }
            .sheet(isPresented: $showingDateDetail) {
                if let date = selectedDate {
                    NavigationView {
                        CalendarDateDetailView(
                            date: date,
                            memos: memoStore.memos,
                            indicatorManager: indicatorManager
                        )
                        .navigationTitle("日付詳細")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button("閉じる") {
                                    showingDateDetail = false
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - 日付インジケーター付きメモ行
struct MemoRowWithDateIndicators: View {
    let memo: Memo
    
    var body: some View {
        HStack(spacing: 12) {
            // メモ情報
            VStack(alignment: .leading, spacing: 4) {
                Text(memo.displayTitle)
                    .font(.headline)
                    .lineLimit(1)
                
                Text(memo.preview)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                
                // 日付情報
                dateIndicatorsRow
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .foregroundColor(.tertiary)
                .font(.caption)
        }
        .padding(.vertical, 4)
    }
    
    private var dateIndicatorsRow: some View {
        HStack(spacing: 8) {
            // 作成日
            dateIndicator(
                date: memo.createdAt,
                color: .blue,
                icon: "plus.circle.fill",
                prefix: "作成"
            )
            
            // 更新日（作成日と異なる場合のみ）
            if !Calendar.current.isDate(memo.createdAt, inSameDayAs: memo.updatedAt) {
                dateIndicator(
                    date: memo.updatedAt,
                    color: .green,
                    icon: "pencil.circle.fill",
                    prefix: "更新"
                )
            }
            
            // 期日
            if let dueDate = memo.dueDate {
                dateIndicator(
                    date: dueDate,
                    color: .red,
                    icon: "calendar.circle.fill",
                    prefix: memo.isOverdue ? "期限切れ" : "期日"
                )
            }
            
            Spacer()
        }
    }
    
    private func dateIndicator(date: Date, color: Color, icon: String, prefix: String) -> some View {
        HStack(spacing: 2) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.caption2)
            
            Circle()
                .fill(color)
                .frame(width: 4, height: 4)
            
            Text("\(prefix): \(date.formatted(.dateTime.month().day()))")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Preview
struct EnhancedDueDatePicker_Previews: PreviewProvider {
    static var previews: some View {
        let sampleMemos = [
            Memo(title: "今日のタスク", content: "今日やることリスト"),
            Memo(title: "明日の会議", content: "プレゼン準備", dueDate: Calendar.current.date(byAdding: .day, value: 1, to: Date())),
            Memo(title: "来週の予定", content: "スケジュール確認", dueDate: Calendar.current.date(byAdding: .weekOfYear, value: 1, to: Date()))
        ]
        
        Group {
            // 期日設定画面
            EnhancedDueDatePickerView(
                dueDate: .constant(Date()),
                hasPreNotification: .constant(true),
                preNotificationMinutes: .constant(60),
                memos: sampleMemos,
                onSave: { _, _, _ in },
                onCancel: { }
            )
            
            // カレンダー統合画面
            MemoCalendarIntegrationView()
        }
    }
}