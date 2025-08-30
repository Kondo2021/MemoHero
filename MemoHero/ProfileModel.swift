import Foundation
import SwiftUI

// MARK: - Profile Data Models

/// ヒーロータイプ診断結果
enum HeroType: String, CaseIterable, Identifiable, Codable {
    case leader = "leader"
    case idea = "idea"
    case support = "support"
    case specialist = "specialist"
    case explorer = "explorer"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .leader: return "リーダー型"
        case .idea: return "アイデア型"
        case .support: return "サポート型"
        case .specialist: return "スペシャリスト型"
        case .explorer: return "探求型"
        }
    }
    
    var description: String {
        switch self {
        case .leader: return "チームを率いて目標達成に向かう"
        case .idea: return "創造的なアイデアで新しい価値を生む"
        case .support: return "仲間を支えてチーム全体を強くする"
        case .specialist: return "専門性を深めて課題を解決する"
        case .explorer: return "未知の分野を探求し続ける"
        }
    }
}

/// 性格特性
struct PersonalityTraits: Codable {
    var isExtroverted: Bool? // 外向的/内向的
    var isRiskTaker: Bool? // リスクを取る/安全志向
    var isDetailOriented: Bool? // 細部重視/全体重視
    
    init() {
        self.isExtroverted = nil
        self.isRiskTaker = nil
        self.isDetailOriented = nil
    }
}

/// モチベーション源
enum MotivationSource: String, CaseIterable, Identifiable, Codable {
    case recognition = "recognition"
    case socialContribution = "socialContribution"
    case skillImprovement = "skillImprovement"
    case achievement = "achievement"
    case creativity = "creativity"
    case teamwork = "teamwork"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .recognition: return "仲間からの評価"
        case .socialContribution: return "社会貢献"
        case .skillImprovement: return "スキル向上"
        case .achievement: return "目標達成"
        case .creativity: return "創造性の発揮"
        case .teamwork: return "チームワーク"
        }
    }
}

/// 挑戦ログエントリ
struct ChallengeLogEntry: Codable, Identifiable {
    var id = UUID()
    var title: String
    var description: String
    var date: Date
    var category: String // 成長/挑戦/プロジェクト等
    
    init(title: String = "", description: String = "", date: Date = Date(), category: String = "") {
        self.title = title
        self.description = description
        self.date = date
        self.category = category
    }
}

/// ユーザープロフィール
struct UserProfile: Codable {
    // 1. 基本プロフィール
    var age: Int? = nil
    var grade: String = ""
    var location: String = ""
    var club: String = ""
    var interests: [String] = [] // タグ形式
    
    // 2. 挑戦・スキル
    var challengeExperiences: [String] = []
    var strongSkills: [String] = []
    var improvementSkills: [String] = []
    
    // 3. キャラクター性（ヒーロー性）
    var heroType: HeroType?
    var personalityTraits: PersonalityTraits = PersonalityTraits()
    var motivationSources: [MotivationSource] = []
    
    // 4. ビジョン・志向
    var futureGoals: String = ""
    var roleModel: String = ""
    var problemsToSolve: String = ""
    
    // 5. 挑戦ログ
    var currentChallenges: [String] = []
    var recentGrowth: [String] = []
    var challengeHistory: [ChallengeLogEntry] = []
    
    // 6. リソース
    var equipment: [String] = [] // PC、スマホ、ネット環境等
    var supportingAdults: String = ""
    var communities: [String] = []
    
    init() {}
}

// MARK: - Profile Manager

/// プロフィール管理クラス
class ProfileManager: ObservableObject {
    static let shared = ProfileManager()
    
    @Published var profile = UserProfile()
    
    private let userDefaults = UserDefaults.standard
    private let profileKey = "user_profile"
    
    init() {
        loadProfile()
    }
    
    /// プロフィールをロード
    func loadProfile() {
        if let data = userDefaults.data(forKey: profileKey),
           let decodedProfile = try? JSONDecoder().decode(UserProfile.self, from: data) {
            profile = decodedProfile
        }
    }
    
    /// プロフィールを保存
    func saveProfile() {
        if let data = try? JSONEncoder().encode(profile) {
            userDefaults.set(data, forKey: profileKey)
            userDefaults.synchronize()
        }
    }
    
    /// テンプレート用のプロフィール文字列を生成
    func generateProfileText() -> String {
        var sections: [String] = []
        
        // 基本プロフィール
        var basicInfo: [String] = []
        if let age = profile.age { basicInfo.append("年齢: \(age)歳") }
        if !profile.grade.isEmpty { basicInfo.append("学年: \(profile.grade)") }
        if !profile.location.isEmpty { basicInfo.append("居住地: \(profile.location)") }
        if !profile.club.isEmpty { basicInfo.append("部活動: \(profile.club)") }
        if !profile.interests.isEmpty { 
            basicInfo.append("興味・関心: \(profile.interests.joined(separator: ", "))") 
        }
        
        if !basicInfo.isEmpty {
            sections.append("**基本情報**\n\(basicInfo.joined(separator: "\n"))")
        }
        
        // 挑戦・スキル
        var skillInfo: [String] = []
        if !profile.challengeExperiences.isEmpty {
            skillInfo.append("挑戦経験: \(profile.challengeExperiences.joined(separator: ", "))")
        }
        if !profile.strongSkills.isEmpty {
            skillInfo.append("得意スキル: \(profile.strongSkills.joined(separator: ", "))")
        }
        if !profile.improvementSkills.isEmpty {
            skillInfo.append("挑戦したいスキル: \(profile.improvementSkills.joined(separator: ", "))")
        }
        
        if !skillInfo.isEmpty {
            sections.append("**スキル・挑戦**\n\(skillInfo.joined(separator: "\n"))")
        }
        
        // キャラクター性
        var characterInfo: [String] = []
        if let heroType = profile.heroType {
            characterInfo.append("ヒーロータイプ: \(heroType.displayName)")
        }
        
        // 性格特性の追加
        var traitsText: [String] = []
        if let isExtroverted = profile.personalityTraits.isExtroverted {
            traitsText.append(isExtroverted ? "外向的" : "内向的")
        }
        if let isRiskTaker = profile.personalityTraits.isRiskTaker {
            traitsText.append(isRiskTaker ? "リスクを取る" : "安全志向")
        }
        if let isDetailOriented = profile.personalityTraits.isDetailOriented {
            traitsText.append(isDetailOriented ? "細部重視" : "全体重視")
        }
        if !traitsText.isEmpty {
            characterInfo.append("性格特性: \(traitsText.joined(separator: ", "))")
        }
        
        if !profile.motivationSources.isEmpty {
            let motivations = profile.motivationSources.map { $0.displayName }
            characterInfo.append("モチベーション: \(motivations.joined(separator: ", "))")
        }
        
        if !characterInfo.isEmpty {
            sections.append("**キャラクター**\n\(characterInfo.joined(separator: "\n"))")
        }
        
        // ビジョン・志向
        var visionInfo: [String] = []
        if !profile.futureGoals.isEmpty { visionInfo.append("将来の目標: \(profile.futureGoals)") }
        if !profile.roleModel.isEmpty { visionInfo.append("ロールモデル: \(profile.roleModel)") }
        if !profile.problemsToSolve.isEmpty { visionInfo.append("解決したい課題: \(profile.problemsToSolve)") }
        
        if !visionInfo.isEmpty {
            sections.append("**ビジョン**\n\(visionInfo.joined(separator: "\n"))")
        }
        
        // 現在の挑戦
        var currentInfo: [String] = []
        if !profile.currentChallenges.isEmpty {
            currentInfo.append("現在の挑戦: \(profile.currentChallenges.joined(separator: ", "))")
        }
        if !profile.recentGrowth.isEmpty {
            currentInfo.append("最近の成長: \(profile.recentGrowth.joined(separator: ", "))")
        }
        
        if !currentInfo.isEmpty {
            sections.append("**現在の取り組み**\n\(currentInfo.joined(separator: "\n"))")
        }
        
        // リソース
        var resourceInfo: [String] = []
        if !profile.equipment.isEmpty { resourceInfo.append("利用可能機器: \(profile.equipment.joined(separator: ", "))") }
        if !profile.supportingAdults.isEmpty { resourceInfo.append("サポート: \(profile.supportingAdults)") }
        if !profile.communities.isEmpty { resourceInfo.append("所属コミュニティ: \(profile.communities.joined(separator: ", "))") }
        
        if !resourceInfo.isEmpty {
            sections.append("**リソース**\n\(resourceInfo.joined(separator: "\n"))")
        }
        
        if sections.isEmpty {
            return ""
        }
        
        return "## 私のプロフィール\n\n\(sections.joined(separator: "\n\n"))"
    }
}