import SwiftUI
import UIKit

// MARK: - MarkdownKeyboardAccessory
/// マークダウン書式挿入用のキーボードアクセサリービュー
struct MarkdownKeyboardAccessory: View {
    /// マークダウン書式挿入のコールバック
    let onInsertSyntax: (String, Int) -> Void
    /// 見出し書式挿入のコールバック
    let onInsertHeading: (String) -> Void
    /// 表挿入のコールバック
    let onInsertTable: () -> Void
    /// 画像挿入のコールバック
    let onInsertImage: () -> Void
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                // 見出し
                formatButton(icon: "h1.square", title: "H1") {
                    onInsertHeading("#")
                }
                
                formatButton(icon: "h2.square", title: "H2") {
                    onInsertHeading("##")
                }
                
                formatButton(icon: "h3.square", title: "H3") {
                    onInsertHeading("###")
                }
                
                Divider()
                    .frame(height: 30)
                
                // テキスト装飾
                formatButton(icon: "bold", title: "太字") {
                    onInsertSyntax("****", 2)
                }
                
                formatButton(icon: "strikethrough", title: "取消線") {
                    onInsertSyntax("~~~~", 2)
                }
                
                Divider()
                    .frame(height: 30)
                
                // リスト
                formatButton(icon: "list.bullet", title: "リスト") {
                    onInsertSyntax("- ", 0)
                }
                
                formatButton(icon: "list.number", title: "番号") {
                    onInsertSyntax("1. ", 0)
                }
                
                formatButton(icon: "checklist", title: "チェック") {
                    onInsertSyntax("- [ ] ", 0)
                }
                
                Divider()
                    .frame(height: 30)
                
                // コードと引用
                formatButton(icon: "quote.bubble", title: "引用") {
                    onInsertSyntax("> ", 0)
                }
                
                formatButton(icon: "curlybraces.square", title: "コード") {
                    onInsertSyntax("```\n\n```", 4)
                }
                
                formatButton(icon: "chevron.left.forwardslash.chevron.right", title: "inline") {
                    onInsertSyntax("``", 1)
                }
                
                Divider()
                    .frame(height: 30)
                
                // その他
                formatButton(icon: "photo", title: "画像") {
                    onInsertImage()
                }
                
                formatButton(icon: "link", title: "リンク") {
                    onInsertSyntax("[]()", 1)
                }
                
                formatButton(icon: "minus", title: "区切り") {
                    onInsertSyntax("---\n", 0)
                }
                
                formatButton(icon: "tablecells", title: "表") {
                    onInsertTable()
                }
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 44)
        .background(Color(.systemGray6))
    }
    
    private func formatButton(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                Text(title)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(.primary)
            .frame(minWidth: 44, minHeight: 40)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - HighlightableTextEditor
/// 検索結果のハイライト表示に対応したテキストエディタ
/// UITextViewをSwiftUIでラップし、日本語入力の問題を解決したカスタムエディタ
struct HighlightableTextEditor: UIViewRepresentable {
    // MARK: - Properties
    /// 編集中のテキスト（バインディング）
    @Binding var text: String
    /// 検索結果の範囲配列
    let searchResults: [NSRange]
    /// 現在選択中の検索結果インデックス
    let currentIndex: Int
    /// テキスト変更時のコールバック
    let onTextChange: (String) -> Void
    /// 選択範囲（カーソル位置）のバインディング
    @Binding var selectedRange: NSRange?
    /// マークダウン書式挿入のコールバック
    let onInsertSyntax: ((String, Int) -> Void)?
    /// 見出し書式挿入のコールバック
    let onInsertHeading: ((String) -> Void)?
    /// 表挿入のコールバック
    let onInsertTable: (() -> Void)?
    /// 画像挿入のコールバック
    let onInsertImage: (() -> Void)?
    
    // MARK: - UIViewRepresentable Methods
    /// UITextViewのインスタンスを作成
    func makeUIView(context: Context) -> CustomTextView {
        let textView = CustomTextView()
        textView.delegate = context.coordinator
        textView.font = UIFont.monospacedSystemFont(ofSize: 16, weight: .regular)
        textView.backgroundColor = UIColor.systemBackground
        textView.isScrollEnabled = true
        textView.isEditable = true
        textView.isUserInteractionEnabled = true
        
        // キーボードアクセサリービューを設定
        if onInsertSyntax != nil || onInsertHeading != nil || onInsertTable != nil || onInsertImage != nil {
            let accessoryView = MarkdownKeyboardAccessoryHostingController(
                onInsertSyntax: onInsertSyntax ?? { _, _ in },
                onInsertHeading: onInsertHeading ?? { _ in },
                onInsertTable: onInsertTable ?? { },
                onInsertImage: onInsertImage ?? { }
            )
            textView.inputAccessoryView = accessoryView.view
        }
        
        return textView
    }
    
    /// UITextViewの状態を更新
    /// - Parameters:
    ///   - textView: 更新するUITextView
    ///   - context: UIViewRepresentableのコンテキスト
    func updateUIView(_ textView: CustomTextView, context: Context) {
        // 日本語入力中（marked text）の場合は更新をスキップ
        if textView.markedTextRange != nil {
            return
        }
        
        // テキストが異なる場合のみ更新
        if textView.text != text {
            // 現在のカーソル位置を保存
            let currentRange = textView.selectedRange
            
            // テキストを更新
            textView.text = text
            
            // バインディングから来たカーソル位置があればそれを使用、なければ現在位置を維持
            let targetRange: NSRange
            if let bindingRange = selectedRange {
                targetRange = NSRange(location: min(bindingRange.location, text.count), length: 0)
            } else {
                targetRange = NSRange(location: min(currentRange.location, text.count), length: 0)
            }
            
            // カーソル位置を設定
            textView.selectedRange = targetRange
        }
        
        updateHighlights(textView)
    }
    
    // MARK: - Private Methods
    /// 検索結果のハイライトを更新
    /// - Parameter textView: ハイライトを適用するUITextView
    private func updateHighlights(_ textView: UITextView) {
        // 日本語入力中（marked text）の場合はハイライト更新をスキップ
        if textView.markedTextRange != nil {
            return
        }
        
        // カーソル位置とスクロール位置を保存
        let currentRange = textView.selectedRange
        let currentContentOffset = textView.contentOffset
        
        let attributedString = NSMutableAttributedString(string: textView.text)
        
        // デフォルトの属性を設定
        attributedString.addAttribute(.font, value: UIFont.monospacedSystemFont(ofSize: 16, weight: .regular), range: NSRange(location: 0, length: attributedString.length))
        attributedString.addAttribute(.foregroundColor, value: UIColor.label, range: NSRange(location: 0, length: attributedString.length))
        
        // 検索結果をハイライト
        for (index, range) in searchResults.enumerated() {
            if range.location + range.length <= attributedString.length {
                if index == currentIndex {
                    // 現在選択中の項目は青色
                    attributedString.addAttribute(.backgroundColor, value: UIColor.systemBlue.withAlphaComponent(0.7), range: range)
                    attributedString.addAttribute(.foregroundColor, value: UIColor.white, range: range)
                } else {
                    // その他の項目は黄色
                    attributedString.addAttribute(.backgroundColor, value: UIColor.systemYellow.withAlphaComponent(0.8), range: range)
                    attributedString.addAttribute(.foregroundColor, value: UIColor.black, range: range)
                }
            }
        }
        
        textView.attributedText = attributedString
        
        // カーソル位置を復元
        textView.selectedRange = currentRange
        
        // スクロール位置を復元（検索モードでない場合）
        if searchResults.isEmpty {
            // UIの更新後に確実にスクロール位置を復元
            DispatchQueue.main.async {
                textView.contentOffset = currentContentOffset
            }
        } else if currentIndex < searchResults.count && currentIndex >= 0 {
            // 検索モードの場合のみ選択項目にスクロール
            let range = searchResults[currentIndex]
            if range.location + range.length <= textView.text.count {
                textView.scrollRangeToVisible(range)
            }
        }
    }
    
    /// Coordinatorを作成
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    // MARK: - Coordinator
    /// UITextViewDelegateの実装とSwiftUIとの橋渡しを行うクラス
    class Coordinator: NSObject, UITextViewDelegate {
        /// 親のHighlightableTextEditor
        let parent: HighlightableTextEditor
        
        /// 初期化
        /// - Parameter parent: 親のHighlightableTextEditor
        init(_ parent: HighlightableTextEditor) {
            self.parent = parent
        }
        
        /// テキストが変更された時の処理
        /// 日本語入力の問題を解決するための特別な処理を含む
        func textViewDidChange(_ textView: UITextView) {
            let timestamp = DateFormatter.debugFormatter.string(from: Date())
            print("⌨️ HighlightableTextEditor.textViewDidChange() 呼び出し [\(timestamp)]")
            print("   テキスト長: \(textView.text.count)")
            print("   markedTextRange: \(textView.markedTextRange != nil)")
            
            // 日本語入力中（marked text）の場合は最小限の処理のみ
            if textView.markedTextRange != nil {
                print("   日本語入力中のため最小限処理")
                // テキスト変更を親に通知のみ
                parent.text = textView.text
                return
            }
            
            // カーソル位置とスクロール位置を保存
            let currentRange = textView.selectedRange
            let currentContentOffset = textView.contentOffset
            print("   カーソル位置: \(currentRange.location)")
            
            // テキスト変更を親に通知
            parent.text = textView.text
            
            // カーソル位置を即座に復元（非同期前に）
            textView.selectedRange = currentRange
            parent.selectedRange = currentRange
            
            // onTextChange呼び出し（これがsaveMemoDebounced等を呼ぶ）
            print("   onTextChange呼び出し開始")
            parent.onTextChange(textView.text)
            print("   onTextChange呼び出し完了")
            
            // 念のため非同期でも復元
            DispatchQueue.main.async {
                if textView.selectedRange != currentRange {
                    textView.selectedRange = currentRange
                }
                // スクロール位置も復元（より確実に）
                textView.contentOffset = currentContentOffset
            }
            
            print("✅ HighlightableTextEditor.textViewDidChange() 完了")
        }
        
        /// 選択範囲が変更された時の処理
        func textViewDidChangeSelection(_ textView: UITextView) {
            // カーソル位置を更新（バインディングと同期）
            DispatchQueue.main.async { [self] in
                if parent.selectedRange != textView.selectedRange {
                    parent.selectedRange = textView.selectedRange
                }
            }
        }
    }
}

// MARK: - CustomTextView
/// 日本語入力とスクロール制御を改善したカスタムUITextView
/// 検索結果ハイライト時の不正なスクロールを防ぐための特別な制御を含む
class CustomTextView: UITextView {
    // MARK: - Context Menu Methods
    /// コンテキストメニューのアクション可否を判定
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        switch action {
        case #selector(copy(_:)):
            return selectedRange.length > 0
        case #selector(paste(_:)):
            return UIPasteboard.general.hasStrings
        case #selector(cut(_:)):
            return selectedRange.length > 0
        case #selector(selectAll(_:)):
            return text.count > 0
        default:
            return super.canPerformAction(action, withSender: sender)
        }
    }
    
    /// コピーアクション
    override func copy(_ sender: Any?) {
        super.copy(sender)
    }
    
    /// ペーストアクション
    override func paste(_ sender: Any?) {
        super.paste(sender)
    }
    
    /// カットアクション
    override func cut(_ sender: Any?) {
        super.cut(sender)
    }
    
    /// 全選択アクション
    override func selectAll(_ sender: Any?) {
        super.selectAll(sender)
    }
    
    // MARK: - iOS 16+ Edit Menu
    /// iOS 16以降でのコンテキストメニューカスタマイズ
    @available(iOS 16.0, *)
    override func editMenu(for textRange: UITextRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
        var customActions: [UIMenuElement] = []
        
        // 選択範囲がある場合のアクション
        if selectedRange.length > 0 {
            customActions.append(UIAction(title: "コピー", image: UIImage(systemName: "doc.on.doc")) { _ in
                self.copy(nil)
            })
            customActions.append(UIAction(title: "カット", image: UIImage(systemName: "scissors")) { _ in
                self.cut(nil)
            })
        }
        
        // ペーストボードにテキストがある場合
        if UIPasteboard.general.hasStrings {
            customActions.append(UIAction(title: "ペースト", image: UIImage(systemName: "doc.on.clipboard")) { _ in
                self.paste(nil)
            })
        }
        
        // 全選択
        if text.count > 0 {
            customActions.append(UIAction(title: "すべてを選択", image: UIImage(systemName: "selection.pin.in.out")) { _ in
                self.selectAll(nil)
            })
        }
        
        return UIMenu(children: customActions)
    }
    
    // MARK: - Scroll Control Methods
    /// 自動スクロールの制御
    /// 検索以外での不要なスクロールを防止
    override func scrollRectToVisible(_ rect: CGRect, animated: Bool) {
        // 日本語入力中（marked text）の場合は通常のスクロールを許可
        if markedTextRange != nil {
            super.scrollRectToVisible(rect, animated: animated)
            return
        }
        
        // 検索以外の自動スクロールを抑制
        // 通常の編集時はスクロール位置を維持
        return
    }
    
    /// 選択範囲変更時のカーソル可視化制御
    override var selectedRange: NSRange {
        didSet {
            // 日本語入力中の場合は自動スクロールを許可
            if markedTextRange != nil {
                return
            }
            
            // カーソル位置変更時の自動スクロールを最小限に
            if selectedRange.length == 0 {
                let cursorRect = caretRect(for: position(from: beginningOfDocument, offset: selectedRange.location) ?? beginningOfDocument)
                if !bounds.contains(cursorRect) {
                    super.scrollRectToVisible(cursorRect, animated: false)
                }
            }
        }
    }
}

// MARK: - MarkdownKeyboardAccessoryHostingController
/// SwiftUIのMarkdownKeyboardAccessoryをUIKitで使用するためのホスティングコントローラー
class MarkdownKeyboardAccessoryHostingController: UIViewController {
    private let onInsertSyntax: (String, Int) -> Void
    private let onInsertHeading: (String) -> Void
    private let onInsertTable: () -> Void
    private let onInsertImage: () -> Void
    
    init(onInsertSyntax: @escaping (String, Int) -> Void, onInsertHeading: @escaping (String) -> Void, onInsertTable: @escaping () -> Void, onInsertImage: @escaping () -> Void) {
        self.onInsertSyntax = onInsertSyntax
        self.onInsertHeading = onInsertHeading
        self.onInsertTable = onInsertTable
        self.onInsertImage = onInsertImage
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let accessoryView = MarkdownKeyboardAccessory(
            onInsertSyntax: onInsertSyntax,
            onInsertHeading: onInsertHeading,
            onInsertTable: onInsertTable,
            onInsertImage: onInsertImage
        )
        
        let hostingController = UIHostingController(rootView: accessoryView)
        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.didMove(toParent: self)
        
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            view.heightAnchor.constraint(equalToConstant: 44)
        ])
    }
}