import SwiftUI
import Foundation

// MARK: - カレンダー日付インジケーター機能
/// カレンダーの各日付にメモの存在を示すインジケーター（小さい⚫︎）を表示する機能

// MARK: - 日付インジケーター用のデータ構造
/// 特定の日付にどのタイプのメモがあるかを示すデータ構造
struct DateIndicatorData {
    let date: Date
    var hasCreatedMemos: Bool = false      // 作成日に該当するメモがあるか（青）
    var hasUpdatedMemos: Bool = false      // 更新日に該当するメモがあるか（緑）
    var hasDueDateMemos: Bool = false      // 期日に該当するメモがあるか（赤）
    
    /// インジケーターの色リストを取得
    var indicatorColors: [Color] {
        var colors: [Color] = []
        if hasCreatedMemos { colors.append(.blue) }
        if hasUpdatedMemos { colors.append(.green) }
        if hasDueDateMemos { colors.append(.red) }
        return colors
    }
    
    /// 何らかのメモが存在するかどうか
    var hasAnyMemos: Bool {
        hasCreatedMemos || hasUpdatedMemos || hasDueDateMemos
    }
}

// MARK: - 日付インジケーター管理クラス
/// カレンダー用の日付インジケーターデータを管理するObservableObject
@MainActor
class CalendarDateIndicatorManager: ObservableObject {
    @Published private(set) var dateIndicators: [String: DateIndicatorData] = [:]
    private let calendar = Calendar.current
    
    /// 日付をキー文字列に変換
    private func dateKey(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    
    /// メモリストから日付インジケーターデータを更新
    /// - Parameter memos: 分析対象のメモ配列
    func updateIndicators(from memos: [Memo]) {
        var newIndicators: [String: DateIndicatorData] = [:]
        
        for memo in memos {
            // 作成日の処理
            let createdDateKey = dateKey(from: memo.createdAt)
            if newIndicators[createdDateKey] == nil {
                newIndicators[createdDateKey] = DateIndicatorData(date: memo.createdAt)
            }
            newIndicators[createdDateKey]?.hasCreatedMemos = true
            
            // 更新日の処理（作成日と異なる場合のみ）
            if !calendar.isDate(memo.createdAt, inSameDayAs: memo.updatedAt) {
                let updatedDateKey = dateKey(from: memo.updatedAt)
                if newIndicators[updatedDateKey] == nil {
                    newIndicators[updatedDateKey] = DateIndicatorData(date: memo.updatedAt)
                }
                newIndicators[updatedDateKey]?.hasUpdatedMemos = true
            }
            
            // 期日の処理
            if let dueDate = memo.dueDate {
                let dueDateKey = dateKey(from: dueDate)
                if newIndicators[dueDateKey] == nil {
                    newIndicators[dueDateKey] = DateIndicatorData(date: dueDate)
                }
                newIndicators[dueDateKey]?.hasDueDateMemos = true
            }
        }
        
        self.dateIndicators = newIndicators
        print("📅 日付インジケーター更新: \(newIndicators.count)日分のデータ")
    }
    
    /// 指定された日付のインジケーターデータを取得
    /// - Parameter date: 検索対象の日付
    /// - Returns: 該当する日付のインジケーターデータ（存在しない場合はnil）
    func indicatorData(for date: Date) -> DateIndicatorData? {
        let key = dateKey(from: date)
        return dateIndicators[key]
    }
    
    /// 指定された日付にメモが存在するかどうか
    /// - Parameter date: 検索対象の日付
    /// - Returns: メモが存在する場合true
    func hasMemosOn(date: Date) -> Bool {
        return indicatorData(for: date)?.hasAnyMemos ?? false
    }
    
    /// 日付範囲内のインジケーターデータを取得
    /// - Parameters:
    ///   - startDate: 開始日
    ///   - endDate: 終了日
    /// - Returns: 指定範囲内のインジケーターデータ配列
    func indicatorsInRange(from startDate: Date, to endDate: Date) -> [DateIndicatorData] {
        return dateIndicators.values.filter { indicator in
            indicator.date >= startDate && indicator.date <= endDate
        }.sorted { $0.date < $1.date }
    }
}

// MARK: - 日付インジケーター表示View
/// カレンダーの日付の下に表示する小さいインジケーター
struct CalendarDateIndicatorsView: View {
    let date: Date
    @ObservedObject var indicatorManager: CalendarDateIndicatorManager
    
    private var indicatorData: DateIndicatorData? {
        indicatorManager.indicatorData(for: date)
    }
    
    var body: some View {
        if let data = indicatorData, data.hasAnyMemos {
            HStack(spacing: 2) {
                ForEach(Array(data.indicatorColors.enumerated()), id: \.offset) { index, color in
                    Circle()
                        .fill(color)
                        .frame(width: 4, height: 4)
                        .shadow(color: color.opacity(0.3), radius: 0.5, x: 0, y: 0.5)
                }
            }
            .padding(.top, 1)
        }
    }
}

// MARK: - 拡張カレンダーセルView
/// 日付表示と日付インジケーターを組み合わせたカレンダーセル
struct EnhancedCalendarDateView: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let isCurrentMonth: Bool
    @ObservedObject var indicatorManager: CalendarDateIndicatorManager
    let onDateTapped: (Date) -> Void
    
    private let calendar = Calendar.current
    
    var body: some View {
        VStack(spacing: 2) {
            // 日付数字
            Text("\(calendar.component(.day, from: date))")
                .font(.system(size: 16, weight: isToday ? .semibold : .regular))
                .foregroundColor(dateTextColor)
                .frame(width: 32, height: 32)
                .background(dateBackground)
                .clipShape(Circle())
            
            // 日付インジケーター
            CalendarDateIndicatorsView(
                date: date,
                indicatorManager: indicatorManager
            )
            .frame(height: 6) // インジケーター用の固定高さ
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            onDateTapped(date)
        }
        .opacity(isCurrentMonth ? 1.0 : 0.3)
    }
    
    private var dateTextColor: Color {
        if isSelected {
            return .white
        } else if isToday {
            return .blue
        } else if isCurrentMonth {
            return .primary
        } else {
            return .secondary
        }
    }
    
    private var dateBackground: some View {
        Group {
            if isSelected {
                Circle()
                    .fill(Color.blue)
            } else if isToday {
                Circle()
                    .stroke(Color.blue, lineWidth: 2)
            } else {
                Circle()
                    .fill(Color.clear)
            }
        }
    }
}

// MARK: - 月間カレンダーView（インジケーター対応）
/// 日付インジケーター機能付きの月間カレンダー表示
struct EnhancedMonthlyCalendarView: View {
    @State private var currentDate = Date()
    @State private var selectedDate: Date?
    @StateObject private var indicatorManager = CalendarDateIndicatorManager()
    
    let memos: [Memo]
    let onDateSelected: ((Date) -> Void)?
    
    private let calendar = Calendar.current
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy年MM月"
        return formatter
    }()
    
    private var monthDates: [Date] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: currentDate),
              let monthFirstWeek = calendar.dateInterval(of: .weekOfYear, for: monthInterval.start),
              let monthLastWeek = calendar.dateInterval(of: .weekOfYear, for: monthInterval.end) else {
            return []
        }
        
        var dates: [Date] = []
        var currentDate = monthFirstWeek.start
        
        while currentDate < monthLastWeek.end {
            dates.append(currentDate)
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
        }
        
        return dates
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // ヘッダー
            calendarHeader
            
            // 曜日ヘッダー
            weekdayHeader
            
            // カレンダーグリッド
            calendarGrid
        }
        .padding()
        .background(Color(UIColor.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
        .onAppear {
            updateIndicators()
        }
        .onChange(of: memos) { _ in
            updateIndicators()
        }
    }
    
    private var calendarHeader: some View {
        HStack {
            Button(action: previousMonth) {
                Image(systemName: "chevron.left")
                    .font(.title2)
                    .foregroundColor(.blue)
            }
            
            Spacer()
            
            Text(dateFormatter.string(from: currentDate))
                .font(.title2)
                .fontWeight(.semibold)
            
            Spacer()
            
            Button(action: nextMonth) {
                Image(systemName: "chevron.right")
                    .font(.title2)
                    .foregroundColor(.blue)
            }
        }
        .padding(.bottom, 16)
    }
    
    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(calendar.shortWeekdaySymbols, id: \.self) { weekday in
                Text(weekday)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.bottom, 8)
    }
    
    private var calendarGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
            ForEach(monthDates, id: \.self) { date in
                EnhancedCalendarDateView(
                    date: date,
                    isSelected: selectedDate != nil && calendar.isDate(date, inSameDayAs: selectedDate!),
                    isToday: calendar.isDateInToday(date),
                    isCurrentMonth: calendar.isDate(date, equalTo: currentDate, toGranularity: .month),
                    indicatorManager: indicatorManager,
                    onDateTapped: { selectedDate in
                        self.selectedDate = selectedDate
                        onDateSelected?(selectedDate)
                        
                        // 選択時のハプティックフィードバック
                        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                        impactFeedback.impactOccurred()
                    }
                )
            }
        }
    }
    
    // MARK: - Methods
    private func previousMonth() {
        withAnimation(.easeInOut(duration: 0.3)) {
            currentDate = calendar.date(byAdding: .month, value: -1, to: currentDate) ?? currentDate
        }
        updateIndicators()
    }
    
    private func nextMonth() {
        withAnimation(.easeInOut(duration: 0.3)) {
            currentDate = calendar.date(byAdding: .month, value: 1, to: currentDate) ?? currentDate
        }
        updateIndicators()
    }
    
    private func updateIndicators() {
        indicatorManager.updateIndicators(from: memos)
    }
}

// MARK: - カレンダー詳細情報表示View
/// 選択された日付のメモ詳細を表示するView
struct CalendarDateDetailView: View {
    let date: Date
    let memos: [Memo]
    @ObservedObject var indicatorManager: CalendarDateIndicatorManager
    
    private let calendar = Calendar.current
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "M月d日（E）"
        return formatter
    }()
    
    private var memosForDate: (created: [Memo], updated: [Memo], due: [Memo]) {
        let created = memos.filter { calendar.isDate($0.createdAt, inSameDayAs: date) }
        let updated = memos.filter { 
            calendar.isDate($0.updatedAt, inSameDayAs: date) && !calendar.isDate($0.createdAt, inSameDayAs: date)
        }
        let due = memos.filter { 
            if let dueDate = $0.dueDate {
                return calendar.isDate(dueDate, inSameDayAs: date)
            }
            return false
        }
        return (created, updated, due)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 日付ヘッダー
            HStack {
                Text(dateFormatter.string(from: date))
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                // インジケーター表示
                CalendarDateIndicatorsView(
                    date: date,
                    indicatorManager: indicatorManager
                )
            }
            
            let memoData = memosForDate
            
            // 作成されたメモ（青）
            if !memoData.created.isEmpty {
                memoSection(
                    title: "作成されたメモ",
                    memos: memoData.created,
                    color: .blue,
                    icon: "plus.circle.fill"
                )
            }
            
            // 更新されたメモ（緑）
            if !memoData.updated.isEmpty {
                memoSection(
                    title: "更新されたメモ",
                    memos: memoData.updated,
                    color: .green,
                    icon: "pencil.circle.fill"
                )
            }
            
            // 期日のメモ（赤）
            if !memoData.due.isEmpty {
                memoSection(
                    title: "期日のメモ",
                    memos: memoData.due,
                    color: .red,
                    icon: "calendar.circle.fill"
                )
            }
            
            // メモがない場合
            if memoData.created.isEmpty && memoData.updated.isEmpty && memoData.due.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "calendar")
                        .font(.largeTitle)
                        .foregroundColor(.gray)
                    
                    Text("この日にはメモがありません")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            }
        }
        .padding()
        .background(Color(UIColor.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
    
    private func memoSection(title: String, memos: [Memo], color: Color, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title)
                    .font(.headline)
                    .fontWeight(.medium)
                Text("(\(memos.count))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            VStack(spacing: 4) {
                ForEach(memos.prefix(3)) { memo in
                    HStack {
                        Circle()
                            .fill(color)
                            .frame(width: 6, height: 6)
                        
                        Text(memo.displayTitle)
                            .font(.subheadline)
                            .lineLimit(1)
                        
                        Spacer()
                    }
                }
                
                if memos.count > 3 {
                    HStack {
                        Circle()
                            .fill(Color.clear)
                            .frame(width: 6, height: 6)
                        
                        Text("他\(memos.count - 3)件...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Preview
struct CalendarDateIndicators_Previews: PreviewProvider {
    static var previews: some View {
        let sampleMemos = [
            Memo(title: "今日作成", content: "今日作成されたメモ"),
            Memo(title: "期日メモ", content: "期日が設定されたメモ", dueDate: Date()),
            Memo(title: "更新メモ", content: "更新されたメモ")
        ]
        
        VStack(spacing: 20) {
            EnhancedMonthlyCalendarView(
                memos: sampleMemos,
                onDateSelected: { date in
                    print("Selected: \(date)")
                }
            )
            
            CalendarDateDetailView(
                date: Date(),
                memos: sampleMemos,
                indicatorManager: CalendarDateIndicatorManager()
            )
        }
        .padding()
    }
}