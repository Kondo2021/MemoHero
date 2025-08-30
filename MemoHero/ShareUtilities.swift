import UIKit
import SwiftUI

// MARK: - Share Utility Classes

/// テキストファイル用のアクティビティアイテムソース
class TextFileActivityItemSource: NSObject, UIActivityItemSource {
    private let memo: Memo
    
    init(memo: Memo) {
        self.memo = memo
        super.init()
    }
    
    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        return memo.content
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        let fileName = memo.title.isEmpty ? "無題のメモ" : memo.title
        let content = memo.content
        
        if let activityType = activityType,
           activityType == .mail || activityType == .message {
            return content
        }
        
        return content
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
        return memo.title.isEmpty ? "無題のメモ" : memo.title
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?) -> String {
        return "public.plain-text"
    }
}

/// マークダウンエクスポートアクティビティ
class MarkdownExportActivity: UIActivity {
    private let memo: Memo
    
    init(memo: Memo) {
        self.memo = memo
        super.init()
    }
    
    override var activityType: UIActivity.ActivityType? {
        return UIActivity.ActivityType("jp.edfusion.localmemo.markdownexport")
    }
    
    override var activityTitle: String? {
        return "Markdownファイル"
    }
    
    override var activityImage: UIImage? {
        return UIImage(systemName: "doc.text")
    }
    
    override func canPerform(withActivityItems activityItems: [Any]) -> Bool {
        return !memo.content.isEmpty
    }
    
    override func perform() {
        let fileName = memo.title.isEmpty ? "無題のメモ" : memo.title
        let cleanFileName = fileName.replacingOccurrences(of: "[^\\w\\s-]", with: "", options: .regularExpression)
        
        let markdownContent = memo.content
        
        if let data = markdownContent.data(using: .utf8) {
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(cleanFileName).md")
            
            do {
                try data.write(to: tempURL)
                
                DispatchQueue.main.async {
                    let documentPicker = UIDocumentPickerViewController(forExporting: [tempURL])
                    documentPicker.shouldShowFileExtensions = true
                    
                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let window = windowScene.windows.first,
                       let rootViewController = window.rootViewController {
                        rootViewController.present(documentPicker, animated: true)
                    }
                    
                    self.activityDidFinish(true)
                }
            } catch {
                print("Markdownファイルの書き込みに失敗: \(error)")
                self.activityDidFinish(false)
            }
        }
    }
}

/// PDFエクスポートアクティビティ
class PDFExportActivity: UIActivity {
    private let memo: Memo
    
    init(memo: Memo) {
        self.memo = memo
        super.init()
    }
    
    override var activityType: UIActivity.ActivityType? {
        return UIActivity.ActivityType("jp.edfusion.localmemo.pdfexport")
    }
    
    override var activityTitle: String? {
        return "PDFファイル"
    }
    
    override var activityImage: UIImage? {
        return UIImage(systemName: "doc.richtext")
    }
    
    override func canPerform(withActivityItems activityItems: [Any]) -> Bool {
        return !memo.content.isEmpty
    }
    
    override func perform() {
        let enableChapterNumbering = AppSettings.shared.isChapterNumberingEnabled
        MarkdownRenderer.generatePDF(from: memo, enableChapterNumbering: enableChapterNumbering) { [weak self] data in
            DispatchQueue.main.async {
                guard let self = self, let pdfData = data else {
                    self?.activityDidFinish(false)
                    return
                }
                
                let fileName = self.memo.title.isEmpty ? "無題のメモ" : self.memo.title
                let cleanFileName = fileName.replacingOccurrences(of: "[^\\w\\s-]", with: "", options: .regularExpression)
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(cleanFileName).pdf")
                
                do {
                    try pdfData.write(to: tempURL)
                    
                    let documentPicker = UIDocumentPickerViewController(forExporting: [tempURL])
                    documentPicker.shouldShowFileExtensions = true
                    
                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let window = windowScene.windows.first,
                       let rootViewController = window.rootViewController {
                        rootViewController.present(documentPicker, animated: true)
                    }
                    
                    self.activityDidFinish(true)
                } catch {
                    print("PDFファイルの書き込みに失敗: \(error)")
                    self.activityDidFinish(false)
                }
            }
        }
    }
}

/// プリントアクティビティ
class PrintActivity: UIActivity {
    private let memo: Memo
    
    init(memo: Memo) {
        self.memo = memo
        super.init()
    }
    
    override var activityType: UIActivity.ActivityType? {
        return UIActivity.ActivityType("jp.edfusion.localmemo.print")
    }
    
    override var activityTitle: String? {
        return "プリント"
    }
    
    override var activityImage: UIImage? {
        return UIImage(systemName: "printer")
    }
    
    override func canPerform(withActivityItems activityItems: [Any]) -> Bool {
        return !memo.content.isEmpty && UIPrintInteractionController.isPrintingAvailable
    }
    
    override func perform() {
        let enableChapterNumbering = AppSettings.shared.isChapterNumberingEnabled
        MarkdownRenderer.generatePDF(from: memo, enableChapterNumbering: enableChapterNumbering) { [weak self] data in
            DispatchQueue.main.async {
                guard let self = self, let pdfData = data else {
                    self?.activityDidFinish(false)
                    return
                }
                
                let printController = UIPrintInteractionController.shared
                printController.printingItem = pdfData
                
                let printInfo = UIPrintInfo(dictionary: nil)
                printInfo.jobName = self.memo.title.isEmpty ? "無題のメモ" : self.memo.title
                printInfo.outputType = .general
                printController.printInfo = printInfo
                
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let window = windowScene.windows.first {
                    printController.present(from: CGRect(x: window.bounds.midX, y: window.bounds.midY, width: 0, height: 0), in: window, animated: true) { (controller, completed, error) in
                        self.activityDidFinish(completed)
                    }
                } else {
                    self.activityDidFinish(false)
                }
            }
        }
    }
}

// MARK: - ShareSheet SwiftUI Wrapper
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    let applicationActivities: [UIActivity]?
    
    init(activityItems: [Any], applicationActivities: [UIActivity]? = nil) {
        self.activityItems = activityItems
        self.applicationActivities = applicationActivities
    }
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let activityViewController = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: applicationActivities
        )
        
        activityViewController.excludedActivityTypes = [.saveToCameraRoll, .addToReadingList]
        return activityViewController
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // No update needed
    }
}

// MARK: - Share Utilities
class ShareUtilities {
    /// 共有オプションを表示（共通関数）
    static func showShareOptions(for memo: Memo) {
        // txtファイル用のアクティビティアイテムソースを作成
        let textFileSource = TextFileActivityItemSource(memo: memo)
        
        // カスタムアクティビティを作成
        let markdownExportActivity = MarkdownExportActivity(memo: memo)
        let pdfExportActivity = PDFExportActivity(memo: memo)
        let printActivity = PrintActivity(memo: memo)
        
        // アクティビティアイテムを準備
        let activityItems: [Any] = [textFileSource]
        let applicationActivities = [markdownExportActivity, pdfExportActivity, printActivity]
        
        let activityViewController = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: applicationActivities
        )
        
        // 不要なアクティビティを除外
        activityViewController.excludedActivityTypes = [.saveToCameraRoll, .addToReadingList]
        
        // iPadの場合はポップオーバーとして表示
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootViewController = window.rootViewController {
            
            if UIDevice.current.userInterfaceIdiom == .pad {
                activityViewController.popoverPresentationController?.sourceView = window
                activityViewController.popoverPresentationController?.sourceRect = CGRect(x: window.bounds.midX, y: window.bounds.midY, width: 0, height: 0)
                activityViewController.popoverPresentationController?.permittedArrowDirections = []
            }
            
            rootViewController.present(activityViewController, animated: true)
        }
    }
}