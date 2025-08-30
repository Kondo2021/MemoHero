import SwiftUI
import Foundation

// MARK: - 既存CalendarViewにインジケーター機能を追加
/// 既存のCalendarViewを拡張して、日付インジケーター機能を追加

// MARK: - インジケーター付きCalendarView
struct CalendarViewWithIndicators: View {
    let memos: [Memo]
    let onMemoSelected: (Memo) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDate = Date()
    @State private var memosForSelectedDate: [Memo] = []
    @StateObject private var indicatorManager = CalendarDateIndicatorManager()
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // インジケーター凡例
                indicatorLegend
                
                // カレンダー表示（インジケーター付き）
                calendarWithIndicators
                
                // 選択日のメモリスト
                selectedDateMemosList
            }
            .navigationTitle("カレンダー")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            indicatorManager.updateIndicators(from: memos)
            updateMemosForDate(selectedDate)
        }
        .onChange(of: memos) { _, newMemos in
            indicatorManager.updateIndicators(from: newMemos)
            updateMemosForDate(selectedDate)
        }
    }
    
    // MARK: - インジケーター凡例
    private var indicatorLegend: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("凡例")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            
            HStack(spacing: 16) {
                legendItem(color: .blue, text: "作成", icon: "plus.circle.fill")
                legendItem(color: .green, text: "更新", icon: "pencil.circle.fill")  
                legendItem(color: .red, text: "期日", icon: "calendar.circle.fill")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(UIColor.systemGray6))
        .cornerRadius(8)
        .padding(.horizontal)
    }
    
    private func legendItem(color: Color, text: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.caption2)
            
            Circle()
                .fill(color)
                .frame(width: 4, height: 4)
            
            Text(text)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - インジケーター付きカレンダー
    private var calendarWithIndicators: some View {
        ZStack {
            // 既存のDatePicker
            VStack {
                Text("日付を選択")
                    .font(.headline)
                    .padding(.bottom, 8)
                
                DatePicker("", selection: $selectedDate, displayedComponents: [.date])
                    .datePickerStyle(.graphical)
                    .environment(\.locale, Locale(identifier: "ja_JP"))
                    .onChange(of: selectedDate) { _, newDate in
                        updateMemosForDate(newDate)
                    }
            }
            
            // インジケーターオーバーレイ
            CalendarIndicatorOverlay(
                selectedDate: selectedDate,
                indicatorManager: indicatorManager
            )
        }
    }
    
    // MARK: - 選択日のメモリスト
    private var selectedDateMemosList: some View {
        Group {
            if !memosForSelectedDate.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(DateFormatter.dayFormatter.string(from: selectedDate))のメモ (\(memosForSelectedDate.count)件)")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    List(memosForSelectedDate, id: \.id) { memo in
                        CalendarMemoRowWithIndicators(memo: memo, selectedDate: selectedDate)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                onMemoSelected(memo)
                            }
                    }
                    .listStyle(.plain)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "calendar")
                        .font(.largeTitle)
                        .foregroundColor(.gray)
                    
                    Text("この日にはメモがありません")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    
    // MARK: - Methods
    private func updateMemosForDate(_ date: Date) {
        var calendar = Calendar.current
        calendar.locale = Locale(identifier: "ja_JP")
        memosForSelectedDate = memos.filter { memo in
            calendar.isDate(memo.createdAt, inSameDayAs: date) ||
            calendar.isDate(memo.updatedAt, inSameDayAs: date) ||
            (memo.dueDate != nil && calendar.isDate(memo.dueDate!, inSameDayAs: date))
        }
    }
}

// MARK: - カレンダーインジケーターオーバーレイ
struct CalendarIndicatorOverlay: View {
    let selectedDate: Date
    @ObservedObject var indicatorManager: CalendarDateIndicatorManager
    
    @State private var calendarSize: CGSize = .zero
    @State private var overlayPositions: [Date: CGPoint] = [:]
    
    private let calendar = Calendar.current
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // オーバーレイインジケーター
                ForEach(Array(indicatorManager.dateIndicators.keys), id: \.self) { dateKey in
                    if let indicatorData = indicatorManager.dateIndicators[dateKey],
                       let position = calculateIndicatorPosition(for: indicatorData.date, in: geometry) {
                        
                        HStack(spacing: 1) {
                            ForEach(Array(indicatorData.indicatorColors.enumerated()), id: \.offset) { index, color in
                                Circle()
                                    .fill(color)
                                    .frame(width: 4, height: 4)
                                    .shadow(color: color.opacity(0.3), radius: 0.5, x: 0, y: 0.5)
                            }
                        }
                        .position(x: position.x, y: position.y + 20) // 数字の下に配置
                    }
                }
            }
        }
        .allowsHitTesting(false) // タッチイベントを下に通す
    }
    
    // MARK: - インジケーター位置計算
    private func calculateIndicatorPosition(for date: Date, in geometry: GeometryProxy) -> CGPoint? {
        // カレンダーグリッドの推定位置計算
        guard let monthInterval = calendar.dateInterval(of: .month, for: selectedDate),
              let firstDayOfMonth = calendar.dateInterval(of: .month, for: selectedDate)?.start else {
            return nil
        }
        
        // 月の最初の週の開始日を取得
        let firstWeekday = calendar.component(.weekday, from: firstDayOfMonth)
        let dayOfMonth = calendar.component(.day, from: date)
        let selectedMonthComponent = calendar.component(.month, from: selectedDate)
        let dateMonthComponent = calendar.component(.month, from: date)
        
        // 同じ月でない場合はスキップ
        guard selectedMonthComponent == dateMonthComponent else { return nil }
        
        // カレンダーグリッドの推定位置（7列×6行のグリッド想定）
        let calendarWidth = geometry.size.width
        let calendarHeight = geometry.size.height * 0.7 // DatePickerの高さを推定
        
        let cellWidth = calendarWidth / 7
        let cellHeight = calendarHeight / 8 // ヘッダー分を考慮
        
        // 日付の位置を計算
        let totalDays = dayOfMonth + firstWeekday - 2 // 調整
        let row = totalDays / 7
        let col = totalDays % 7
        
        let x = CGFloat(col) * cellWidth + cellWidth / 2
        let y = CGFloat(row + 2) * cellHeight + cellHeight / 2 // ヘッダー分のオフセット
        
        // 画面範囲内かチェック
        if x >= 0 && x <= calendarWidth && y >= 0 && y <= calendarHeight {
            return CGPoint(x: x, y: y)
        }
        
        return nil
    }
}

// MARK: - インジケーター付きメモ行
struct CalendarMemoRowWithIndicators: View {
    let memo: Memo
    let selectedDate: Date
    
    private let calendar = Calendar.current
    
    var body: some View {
        HStack(spacing: 12) {
            // メモ情報
            VStack(alignment: .leading, spacing: 4) {
                Text(memo.title.isEmpty ? "無題のメモ" : memo.title)
                    .font(.headline)
                    .lineLimit(1)
                
                Text(memo.content)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                
                // 日付種別表示
                memoDateTypes
            }
            
            Spacer()
            
            // インジケーター
            VStack(spacing: 2) {
                ForEach(Array(dateIndicators.enumerated()), id: \.offset) { index, indicator in
                    HStack(spacing: 2) {
                        Circle()
                            .fill(indicator.color)
                            .frame(width: 6, height: 6)
                        
                        Text(indicator.label)
                            .font(.caption2)
                            .foregroundColor(indicator.color)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    // MARK: - メモの日付種別
    private var memoDateTypes: some View {
        HStack(spacing: 8) {
            if calendar.isDate(memo.createdAt, inSameDayAs: selectedDate) {
                dateTypeLabel(color: .blue, text: "作成", time: memo.createdAt)
            }
            
            if calendar.isDate(memo.updatedAt, inSameDayAs: selectedDate) &&
               !calendar.isDate(memo.createdAt, inSameDayAs: memo.updatedAt) {
                dateTypeLabel(color: .green, text: "更新", time: memo.updatedAt)
            }
            
            if let dueDate = memo.dueDate,
               calendar.isDate(dueDate, inSameDayAs: selectedDate) {
                dateTypeLabel(color: .red, text: "期日", time: dueDate)
            }
        }
    }
    
    private func dateTypeLabel(color: Color, text: String, time: Date) -> some View {
        HStack(spacing: 2) {
            Circle()
                .fill(color)
                .frame(width: 4, height: 4)
            
            Text("\(text): \(time.formatted(.dateTime.hour().minute()))")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - インジケーター情報
    private var dateIndicators: [(color: Color, label: String)] {
        var indicators: [(Color, String)] = []
        
        if calendar.isDate(memo.createdAt, inSameDayAs: selectedDate) {
            indicators.append((.blue, "作成"))
        }
        
        if calendar.isDate(memo.updatedAt, inSameDayAs: selectedDate) &&
           !calendar.isDate(memo.createdAt, inSameDayAs: memo.updatedAt) {
            indicators.append((.green, "更新"))
        }
        
        if let dueDate = memo.dueDate,
           calendar.isDate(dueDate, inSameDayAs: selectedDate) {
            indicators.append((.red, "期日"))
        }
        
        return indicators
    }
}

// MARK: - より実用的なアプローチ: CustomCalendarView
/// GraphicalDatePickerStyleの制約を回避するための独自カレンダー実装
struct CustomCalendarWithIndicators: View {
    let memos: [Memo]
    let onMemoSelected: (Memo) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var currentDate = Date()
    @State private var selectedDate = Date()
    @State private var memosForSelectedDate: [Memo] = []
    @StateObject private var indicatorManager = CalendarDateIndicatorManager()
    
    private let calendar = Calendar.current
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy年MM月"
        return formatter
    }()
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // カレンダーヘッダー
                calendarHeader
                
                // 曜日ヘッダー
                weekdayHeader
                
                // カレンダーグリッド（インジケーター付き）
                calendarGrid
                
                Divider()
                    .padding(.vertical, 16)
                
                // 選択日のメモリスト
                selectedDateSection
            }
            .navigationTitle("カレンダー")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            indicatorManager.updateIndicators(from: memos)
            updateMemosForDate(selectedDate)
        }
        .onChange(of: memos) { _, newMemos in
            indicatorManager.updateIndicators(from: newMemos)
            updateMemosForDate(selectedDate)
        }
    }
    
    // MARK: - カレンダーヘッダー
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
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
    
    // MARK: - 曜日ヘッダー
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
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
    
    // MARK: - カレンダーグリッド
    private var calendarGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 4) {
            ForEach(monthDates, id: \.self) { date in
                CalendarDateCellWithIndicators(
                    date: date,
                    isSelected: calendar.isDate(date, inSameDayAs: selectedDate),
                    isToday: calendar.isDateInToday(date),
                    isCurrentMonth: calendar.isDate(date, equalTo: currentDate, toGranularity: .month),
                    indicatorManager: indicatorManager,
                    onDateTapped: { selectedDate in
                        self.selectedDate = selectedDate
                        updateMemosForDate(selectedDate)
                        
                        // ハプティックフィードバック
                        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                        impactFeedback.impactOccurred()
                    }
                )
            }
        }
        .padding(.horizontal)
    }
    
    // MARK: - 選択日セクション
    private var selectedDateSection: some View {
        Group {
            if !memosForSelectedDate.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(DateFormatter.dayFormatter.string(from: selectedDate))のメモ (\(memosForSelectedDate.count)件)")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    List(memosForSelectedDate, id: \.id) { memo in
                        CalendarMemoRowWithIndicators(memo: memo, selectedDate: selectedDate)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                onMemoSelected(memo)
                            }
                    }
                    .listStyle(.plain)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "calendar")
                        .font(.largeTitle)
                        .foregroundColor(.gray)
                    
                    Text("この日にはメモがありません")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    
    // MARK: - 月データ計算
    private var monthDates: [Date] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: currentDate),
              let monthFirstWeek = calendar.dateInterval(of: .weekOfYear, for: monthInterval.start),
              let monthLastWeek = calendar.dateInterval(of: .weekOfYear, for: monthInterval.end) else {
            return []
        }
        
        var dates: [Date] = []
        var currentDateIterator = monthFirstWeek.start
        
        while currentDateIterator < monthLastWeek.end {
            dates.append(currentDateIterator)
            currentDateIterator = calendar.date(byAdding: .day, value: 1, to: currentDateIterator) ?? currentDateIterator
        }
        
        return dates
    }
    
    // MARK: - Methods
    private func previousMonth() {
        withAnimation(.easeInOut(duration: 0.3)) {
            currentDate = calendar.date(byAdding: .month, value: -1, to: currentDate) ?? currentDate
        }
    }
    
    private func nextMonth() {
        withAnimation(.easeInOut(duration: 0.3)) {
            currentDate = calendar.date(byAdding: .month, value: 1, to: currentDate) ?? currentDate
        }
    }
    
    private func updateMemosForDate(_ date: Date) {
        memosForSelectedDate = memos.filter { memo in
            calendar.isDate(memo.createdAt, inSameDayAs: date) ||
            calendar.isDate(memo.updatedAt, inSameDayAs: date) ||
            (memo.dueDate != nil && calendar.isDate(memo.dueDate!, inSameDayAs: date))
        }
    }
}

// MARK: - インジケーター付きカレンダーセル
struct CalendarDateCellWithIndicators: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let isCurrentMonth: Bool
    @ObservedObject var indicatorManager: CalendarDateIndicatorManager
    let onDateTapped: (Date) -> Void
    
    private let calendar = Calendar.current
    
    var body: some View {
        VStack(spacing: 3) {
            // 日付数字
            Text("\(calendar.component(.day, from: date))")
                .font(.system(size: 16, weight: isToday ? .semibold : .regular))
                .foregroundColor(dateTextColor)
                .frame(width: 32, height: 32)
                .background(dateBackground)
                .clipShape(Circle())
            
            // インジケーター（これが重要！）
            HStack(spacing: 1) {
                if let indicatorData = indicatorManager.indicatorData(for: date) {
                    ForEach(Array(indicatorData.indicatorColors.enumerated()), id: \.offset) { index, color in
                        Circle()
                            .fill(color)
                            .frame(width: 4, height: 4)
                            .shadow(color: color.opacity(0.3), radius: 0.5, x: 0, y: 0.5)
                    }
                }
            }
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

// MARK: - DateFormatter拡張
extension DateFormatter {
    static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "M月d日（E）"
        return formatter
    }()
}

// MARK: - Preview
struct CalendarWithIndicators_Previews: PreviewProvider {
    static var previews: some View {
        let sampleMemos = [
            Memo(title: "今日のタスク", content: "今日作成されたメモ"),
            Memo(title: "明日の会議", content: "期日が設定されたメモ", dueDate: Calendar.current.date(byAdding: .day, value: 1, to: Date())),
            Memo(title: "更新されたメモ", content: "昨日更新されたメモ")
        ]
        
        Group {
            // 既存スタイル拡張版
            CalendarViewWithIndicators(memos: sampleMemos) { memo in
                print("Selected: \(memo.title)")
            }
            .previewDisplayName("既存スタイル拡張")
            
            // カスタムカレンダー版
            CustomCalendarWithIndicators(memos: sampleMemos) { memo in
                print("Selected: \(memo.title)")
            }
            .previewDisplayName("カスタムカレンダー")
        }
    }
}