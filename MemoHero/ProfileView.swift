import SwiftUI

// MARK: - Profile View

/// プロフィール画面
struct ProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var profileManager = ProfileManager.shared
    @State private var originalProfile: UserProfile = UserProfile()
    
    var body: some View {
        NavigationView {
            Form {
                // 1. 基本プロフィール
                BasicProfileSection(profile: $profileManager.profile)
                
                // 2. 挑戦・スキル
                ChallengeSkillSection(profile: $profileManager.profile)
                
                // 3. キャラクター性（ヒーロー性）
                CharacterSection(profile: $profileManager.profile)
                
                // 4. ビジョン・志向
                VisionSection(profile: $profileManager.profile)
                
                // 5. 挑戦ログ
                ChallengeLogSection(profile: $profileManager.profile)
                
                // 6. リソース
                ResourceSection(profile: $profileManager.profile)
            }
            .navigationTitle("プロフィール")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("キャンセル") {
                        // 元のプロフィールに戻す
                        profileManager.profile = originalProfile
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") {
                        profileManager.saveProfile()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .onAppear {
            // 編集開始時に現在のプロフィールをディープコピーでバックアップ
            originalProfile = profileManager.profile.copy()
        }
    }
}

// MARK: - Basic Profile Section

struct BasicProfileSection: View {
    @Binding var profile: UserProfile
    
    var body: some View {
        Section(header: Text("基本プロフィール")) {
            HStack {
                Text("年齢")
                Spacer()
                Picker("を選択", selection: $profile.age) {
                    Text("選択してください").tag(nil as Int?)
                    ForEach(Array(1...99), id: \.self) { age in
                        Text("\(age)歳").tag(age as Int?)
                    }
                }
                .pickerStyle(MenuPickerStyle())
            }
            
            HStack {
                Text("学年")
                Spacer()
                Picker("を選択", selection: $profile.grade) {
                    Text("選択してください").tag("")
                    // 小学校
                    Text("小学1年").tag("小学1年")
                    Text("小学2年").tag("小学2年")
                    Text("小学3年").tag("小学3年")
                    Text("小学4年").tag("小学4年")
                    Text("小学5年").tag("小学5年")
                    Text("小学6年").tag("小学6年")
                    // 中学校
                    Text("中学1年").tag("中学1年")
                    Text("中学2年").tag("中学2年")
                    Text("中学3年").tag("中学3年")
                    // 高校
                    Text("高校1年").tag("高校1年")
                    Text("高校2年").tag("高校2年")
                    Text("高校3年").tag("高校3年")
                    // 大学・専門学校
                    Text("大学1年").tag("大学1年")
                    Text("大学2年").tag("大学2年")
                    Text("大学3年").tag("大学3年")
                    Text("大学4年").tag("大学4年")
                    Text("専門学校1年").tag("専門学校1年")
                    Text("専門学校2年").tag("専門学校2年")
                    Text("専門学校3年").tag("専門学校3年")
                    // その他
                    Text("社会人").tag("社会人")
                    Text("その他").tag("その他")
                }
                .pickerStyle(MenuPickerStyle())
            }
            
            HStack {
                Text("居住地域")
                Spacer()
                Picker("を選択", selection: $profile.location) {
                    Text("選択してください").tag("")
                    Text("北海道").tag("北海道")
                    Text("青森県").tag("青森県")
                    Text("岩手県").tag("岩手県")
                    Text("宮城県").tag("宮城県")
                    Text("秋田県").tag("秋田県")
                    Text("山形県").tag("山形県")
                    Text("福島県").tag("福島県")
                    Text("茨城県").tag("茨城県")
                    Text("栃木県").tag("栃木県")
                    Text("群馬県").tag("群馬県")
                    Text("埼玉県").tag("埼玉県")
                    Text("千葉県").tag("千葉県")
                    Text("東京都").tag("東京都")
                    Text("神奈川県").tag("神奈川県")
                    Text("新潟県").tag("新潟県")
                    Text("富山県").tag("富山県")
                    Text("石川県").tag("石川県")
                    Text("福井県").tag("福井県")
                    Text("山梨県").tag("山梨県")
                    Text("長野県").tag("長野県")
                    Text("岐阜県").tag("岐阜県")
                    Text("静岡県").tag("静岡県")
                    Text("愛知県").tag("愛知県")
                    Text("三重県").tag("三重県")
                    Text("滋賀県").tag("滋賀県")
                    Text("京都府").tag("京都府")
                    Text("大阪府").tag("大阪府")
                    Text("兵庫県").tag("兵庫県")
                    Text("奈良県").tag("奈良県")
                    Text("和歌山県").tag("和歌山県")
                    Text("鳥取県").tag("鳥取県")
                    Text("島根県").tag("島根県")
                    Text("岡山県").tag("岡山県")
                    Text("広島県").tag("広島県")
                    Text("山口県").tag("山口県")
                    Text("徳島県").tag("徳島県")
                    Text("香川県").tag("香川県")
                    Text("愛媛県").tag("愛媛県")
                    Text("高知県").tag("高知県")
                    Text("福岡県").tag("福岡県")
                    Text("佐賀県").tag("佐賀県")
                    Text("長崎県").tag("長崎県")
                    Text("熊本県").tag("熊本県")
                    Text("大分県").tag("大分県")
                    Text("宮崎県").tag("宮崎県")
                    Text("鹿児島県").tag("鹿児島県")
                    Text("沖縄県").tag("沖縄県")
                    Text("海外").tag("海外")
                }
                .pickerStyle(MenuPickerStyle())
            }
            
            
            HStack {
                Text("部活動")
                TextField("例: 科学部", text: $profile.club)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("興味・関心分野")
                InterestInputView(interests: $profile.interests)
            }
        }
    }
}

// MARK: - Challenge & Skill Section

struct ChallengeSkillSection: View {
    @Binding var profile: UserProfile
    
    var body: some View {
        Section(header: Text("挑戦・スキル")) {
            VStack(alignment: .leading, spacing: 8) {
                Text("これまでの挑戦経験")
                TextField("例: プログラミング、部活動での大会出場", text: $profile.challengeExperiences, axis: .vertical)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .lineLimit(3...5)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("得意なスキル")
                TextField("例: 数学、英語、プレゼンテーション", text: $profile.strongSkills, axis: .vertical)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .lineLimit(3...5)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("挑戦したいスキル")
                TextField("例: AI・機械学習、デザイン、起業", text: $profile.improvementSkills, axis: .vertical)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .lineLimit(3...5)
            }
        }
    }
}

// MARK: - Character Section

struct CharacterSection: View {
    @Binding var profile: UserProfile
    
    var body: some View {
        Section(header: Text("キャラクター性")) {
            VStack(alignment: .leading, spacing: 8) {
                Text("ヒーロータイプ")
                Picker("ヒーロータイプ", selection: $profile.heroType) {
                    Text("選択してください").tag(nil as HeroType?)
                    ForEach(HeroType.allCases) { type in
                        Text(type.displayName).tag(type as HeroType?)
                    }
                }
                .pickerStyle(MenuPickerStyle())
            }
            
            VStack(alignment: .leading, spacing: 12) {
                Text("性格特性")
                
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("外向的 ←→ 内向的")
                            .font(.caption)
                        Picker("外向的・内向的", selection: $profile.personalityTraits.isExtroverted) {
                            Text("選択してください").tag(nil as Bool?)
                            Text("外向的").tag(true as Bool?)
                            Text("内向的").tag(false as Bool?)
                        }
                        .pickerStyle(SegmentedPickerStyle())
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("リスクを取る ←→ 安全志向")
                            .font(.caption)
                        Picker("リスク・安全", selection: $profile.personalityTraits.isRiskTaker) {
                            Text("選択してください").tag(nil as Bool?)
                            Text("リスクを取る").tag(true as Bool?)
                            Text("安全志向").tag(false as Bool?)
                        }
                        .pickerStyle(SegmentedPickerStyle())
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("細部重視 ←→ 全体重視")
                            .font(.caption)
                        Picker("細部・全体", selection: $profile.personalityTraits.isDetailOriented) {
                            Text("選択してください").tag(nil as Bool?)
                            Text("細部重視").tag(true as Bool?)
                            Text("全体重視").tag(false as Bool?)
                        }
                        .pickerStyle(SegmentedPickerStyle())
                    }
                }
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("モチベーション源")
                MotivationInputView(motivations: $profile.motivationSources)
            }
        }
    }
}

// MARK: - Vision Section

struct VisionSection: View {
    @Binding var profile: UserProfile
    
    var body: some View {
        Section(header: Text("ビジョン・志向")) {
            VStack(alignment: .leading, spacing: 8) {
                Text("将来やりたいこと")
                TextField("例: 起業してAIで社会問題を解決したい", text: $profile.futureGoals, axis: .vertical)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .lineLimit(3...5)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("尊敬する人・ロールモデル")
                TextField("例: スティーブ・ジョブズ、その理由や影響を受けた点も含めて", text: $profile.roleModel, axis: .vertical)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .lineLimit(3...5)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("解決したい課題")
                TextField("例: 地域の環境問題を解決したい", text: $profile.problemsToSolve, axis: .vertical)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .lineLimit(3...5)
            }
        }
    }
}

// MARK: - Challenge Log Section

struct ChallengeLogSection: View {
    @Binding var profile: UserProfile
    
    var body: some View {
        Section(header: Text("挑戦ログ")) {
            VStack(alignment: .leading, spacing: 8) {
                Text("現在取り組んでいる挑戦")
                TextField("例: 英検2級合格を目指している、新しいプログラミング言語の習得", text: $profile.currentChallenges, axis: .vertical)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .lineLimit(3...5)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("最近の成長")
                TextField("例: チームでのコミュニケーションが上達した、新しい技術を習得できた", text: $profile.recentGrowth, axis: .vertical)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .lineLimit(3...5)
            }
        }
    }
}

// MARK: - Resource Section

struct ResourceSection: View {
    @Binding var profile: UserProfile
    
    var body: some View {
        Section(header: Text("リソース")) {
            VStack(alignment: .leading, spacing: 8) {
                Text("利用可能機器・環境")
                TextField("例: PC、スマホ、高速インターネット、静かな勉強スペース", text: $profile.equipment, axis: .vertical)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .lineLimit(3...5)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("協力してくれる大人")
                TextField("例: 両親、先生、メンター、先輩", text: $profile.supportingAdults, axis: .vertical)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .lineLimit(3...5)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("所属コミュニティ")
                TextField("例: プログラミングサークル、ボランティア団体、学習グループ", text: $profile.communities, axis: .vertical)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .lineLimit(3...5)
            }
        }
    }
}

// MARK: - Helper Views

/// 興味関心入力ビュー（プリセットボタン付き）
struct InterestInputView: View {
    @Binding var interests: [String]
    @State private var interestText = ""
    
    private let presetOptions = [
        "防災", "AI・テクノロジー", "環境", "スポーツ", "音楽",
        "アート・デザイン", "起業", "プログラミング", "国際交流", "ボランティア",
        "科学・研究", "料理", "旅行", "写真", "読書"
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // テキストフィールド
            TextField("例: 音楽, プログラミング, 環境", text: $interestText, axis: .vertical)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .lineLimit(3...5)
                .onAppear {
                    // 初期化時に既存の興味関心を文字列として設定
                    interestText = interests.joined(separator: ", ")
                }
                .onChange(of: interestText) {
                    // テキストが変更されたら配列に反映
                    let trimmedItems = interestText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    interests = trimmedItems.filter { !$0.isEmpty }
                }
            
            // プリセットボタン
            Text("選択肢:")
                .font(.caption)
                .foregroundColor(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 8) {
                ForEach(presetOptions, id: \.self) { preset in
                    Button(preset) {
                        addPreset(preset)
                    }
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(isPresetSelected(preset) ? Color.blue.opacity(0.3) : Color.gray.opacity(0.2))
                    .foregroundColor(isPresetSelected(preset) ? .blue : .primary)
                    .cornerRadius(8)
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.top, 4)
        }
    }
    
    private func addPreset(_ preset: String) {
        if !isPresetSelected(preset) {
            if !interestText.isEmpty {
                interestText += ", \(preset)"
            } else {
                interestText = preset
            }
        }
    }
    
    private func isPresetSelected(_ preset: String) -> Bool {
        return interestText.contains(preset)
    }
}

/// モチベーション入力ビュー（プリセットボタン付き）
struct MotivationInputView: View {
    @Binding var motivations: [MotivationSource]
    @State private var motivationText = ""
    
    private let presetOptions = MotivationSource.allCases
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // テキストフィールド
            TextField("例: 仲間からの評価, 社会貢献, スキル向上", text: $motivationText, axis: .vertical)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .lineLimit(3...5)
                .onAppear {
                    // 初期化時に既存のモチベーション源を文字列として設定
                    motivationText = motivations.map { $0.displayName }.joined(separator: ", ")
                }
                .onChange(of: motivationText) {
                    // テキストが変更されたらMotivationSource配列に反映
                    let trimmedItems = motivationText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    motivations = []
                    for item in trimmedItems.filter({ !$0.isEmpty }) {
                        if let matchedSource = MotivationSource.allCases.first(where: { $0.displayName == item }) {
                            motivations.append(matchedSource)
                        } else {
                            // カスタムの場合は新しいケースが必要だが、enumなので既存のもののみ対応
                            // 部分一致で探す
                            if let partialMatch = MotivationSource.allCases.first(where: { $0.displayName.contains(item) || item.contains($0.displayName) }) {
                                if !motivations.contains(partialMatch) {
                                    motivations.append(partialMatch)
                                }
                            }
                        }
                    }
                }
            
            // プリセットボタン
            Text("選択肢:")
                .font(.caption)
                .foregroundColor(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 8) {
                ForEach(presetOptions, id: \.id) { preset in
                    Button(preset.displayName) {
                        addPreset(preset)
                    }
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(isPresetSelected(preset) ? Color.blue.opacity(0.3) : Color.gray.opacity(0.2))
                    .foregroundColor(isPresetSelected(preset) ? .blue : .primary)
                    .cornerRadius(8)
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.top, 4)
        }
    }
    
    private func addPreset(_ preset: MotivationSource) {
        if !isPresetSelected(preset) {
            if !motivationText.isEmpty {
                motivationText += ", \(preset.displayName)"
            } else {
                motivationText = preset.displayName
            }
        }
    }
    
    private func isPresetSelected(_ preset: MotivationSource) -> Bool {
        return motivationText.contains(preset.displayName)
    }
}

/// シンプルなリスト入力ビュー
struct SimpleListInputView: View {
    @Binding var items: [String]
    let placeholder: String
    @State private var newItem = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 既存アイテムのリスト表示
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack {
                    Text("• \(item)")
                    Spacer()
                    Button("削除") {
                        items.remove(at: index)
                    }
                    .foregroundColor(.red)
                    .font(.caption)
                }
            }
            
            // 新しいアイテムの入力
            HStack {
                TextField(placeholder, text: $newItem)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .onSubmit {
                        addItem()
                    }
                
                Button("追加") {
                    addItem()
                }
                .disabled(newItem.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
    
    private func addItem() {
        let trimmed = newItem.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            // カンマ区切りで複数の項目を分割
            let newItems = trimmed.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            
            for item in newItems {
                if !item.isEmpty && !items.contains(item) {
                    items.append(item)
                }
            }
            newItem = ""
        }
    }
}

/// 2択トグル（true/false/nil）- 左右切り替え可能
struct TriStateToggle: View {
    @Binding var value: Bool?
    let trueLabel: String
    let falseLabel: String
    
    var body: some View {
        HStack(spacing: 12) {
            Button(trueLabel) {
                // 既に選択済みなら解除、そうでなければ選択
                value = (value == true) ? nil : true
            }
            .foregroundColor(value == true ? .white : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(value == true ? Color.blue : Color.gray.opacity(0.2))
            .cornerRadius(16)
            
            Button(falseLabel) {
                // 既に選択済みなら解除、そうでなければ選択
                value = (value == false) ? nil : false
            }
            .foregroundColor(value == false ? .white : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(value == false ? Color.blue : Color.gray.opacity(0.2))
            .cornerRadius(16)
        }
    }
}

/// 複数選択ビュー
struct MultiSelectView<T: Identifiable & Hashable>: View {
    let options: [T]
    @Binding var selections: [T]
    let displayName: (T) -> String
    
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 8) {
            ForEach(options, id: \.id) { option in
                Button(action: {
                    if selections.contains(option) {
                        selections.removeAll { $0.id == option.id }
                    } else {
                        selections.append(option)
                    }
                }) {
                    Text(displayName(option))
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .foregroundColor(selections.contains(option) ? .white : .primary)
                        .background(selections.contains(option) ? Color.blue : Color.gray.opacity(0.2))
                        .cornerRadius(12)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ProfileView()
}