import Foundation
import FirebaseFirestore

// MARK: - Event Model
/// イベント情報を管理するFirebaseモデル
struct Event: Identifiable, Codable, Equatable {
    @DocumentID var id: String?
    let title: String
    let content: String
    let deadline_date: Date? // 応募締切日
    let event_date: Date?    // 開催日
    let application_form_url: String? // 応募フォームURL
    let analysis_template: String?   // 自己分析用テンプレート
    let venue: String?       // 会場
    let capacity: String?    // 定員
    let target: String?      // 対象
    
    init(title: String, content: String, deadline_date: Date? = nil, event_date: Date? = nil, application_form_url: String? = nil, analysis_template: String? = nil, venue: String? = nil, capacity: String? = nil, target: String? = nil) {
        self.title = title
        self.content = content
        self.deadline_date = deadline_date
        self.event_date = event_date
        self.application_form_url = application_form_url
        self.analysis_template = analysis_template
        self.venue = venue
        self.capacity = capacity
        self.target = target
    }
    
    // 文字列から日付を作成する便利なイニシャライザー
    init(title: String, content: String, deadline_dateString: String?, event_dateString: String?, application_form_url: String? = nil, analysis_template: String? = nil, venue: String? = nil, capacity: String? = nil, target: String? = nil) {
        self.title = title
        self.content = content
        self.application_form_url = application_form_url
        self.analysis_template = analysis_template
        self.venue = venue
        self.capacity = capacity
        self.target = target
        
        let formatter = DateFormatter()
        // 時間情報が含まれているかチェック
        if let deadlineString = deadline_dateString {
            if deadlineString.contains(":") {
                formatter.dateFormat = "yyyy-MM-dd HH:mm"
            } else {
                formatter.dateFormat = "yyyy-MM-dd"
            }
            self.deadline_date = formatter.date(from: deadlineString)
        } else {
            self.deadline_date = nil
        }
        
        if let eventString = event_dateString {
            if eventString.contains(":") {
                formatter.dateFormat = "yyyy-MM-dd HH:mm"
            } else {
                formatter.dateFormat = "yyyy-MM-dd"
            }
            self.event_date = formatter.date(from: eventString)
        } else {
            self.event_date = nil
        }
    }
    
    // 日付を文字列としてフォーマットする計算プロパティ
    var formattedDeadlineDate: String? {
        guard let deadline_date = deadline_date else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd HH:mm"
        return formatter.string(from: deadline_date)
    }
    
    var formattedEventDate: String? {
        guard let event_date = event_date else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd HH:mm"
        return formatter.string(from: event_date)
    }
    
    // Equatable implementation for comparison in real-time updates
    static func == (lhs: Event, rhs: Event) -> Bool {
        return lhs.id == rhs.id && 
               lhs.title == rhs.title && 
               lhs.content == rhs.content &&
               lhs.deadline_date == rhs.deadline_date &&
               lhs.event_date == rhs.event_date &&
               lhs.application_form_url == rhs.application_form_url &&
               lhs.analysis_template == rhs.analysis_template &&
               lhs.venue == rhs.venue &&
               lhs.capacity == rhs.capacity &&
               lhs.target == rhs.target
    }
}

