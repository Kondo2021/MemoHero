import Foundation
import UIKit
import WebKit
import PDFKit
import ObjectiveC
import SwiftUI

// MARK: - MarkdownRenderer
/// マークダウンテキストをHTMLに変換し、PDFを生成するクラス
class MarkdownRenderer: NSObject {
    
    // MARK: - HTML Conversion
    /// マークダウンテキストをHTMLに変換
    /// - Parameter markdown: マークダウンテキスト
    /// - Returns: HTMLテキスト
    static func convertToHTML(markdown: String) -> String {
        var html = markdown
        
        // エスケープ処理
        html = html.replacingOccurrences(of: "&", with: "&amp;")
        html = html.replacingOccurrences(of: "<", with: "&lt;")
        html = html.replacingOccurrences(of: ">", with: "&gt;")
        
        // コードブロック（```で囲まれた部分）を保護
        let codeBlockPattern = #"```([\s\S]*?)```"#
        var codeBlocks: [String] = []
        do {
            let codeBlockRegex = try NSRegularExpression(pattern: codeBlockPattern)
            let codeBlockMatches = codeBlockRegex.matches(in: html, range: NSRange(html.startIndex..., in: html))
            
            // コードブロックを一時的に置換
            for (index, match) in codeBlockMatches.enumerated().reversed() {
                let range = Range(match.range, in: html)!
                let codeContent = String(html[range])
                codeBlocks.insert(codeContent, at: 0)
                html.replaceSubrange(range, with: "CODE_BLOCK_\(index)")
            }
        } catch {
            print("コードブロック変換エラー: \(error)")
        }
        
        // インラインコード（`で囲まれた部分）を保護
        let inlineCodePattern = #"`([^`]+)`"#
        var inlineCodes: [String] = []
        do {
            let inlineCodeRegex = try NSRegularExpression(pattern: inlineCodePattern)
            let inlineCodeMatches = inlineCodeRegex.matches(in: html, range: NSRange(html.startIndex..., in: html))
            
            for (index, match) in inlineCodeMatches.enumerated().reversed() {
                let range = Range(match.range, in: html)!
                let codeContent = String(html[range])
                inlineCodes.insert(codeContent, at: 0)
                html.replaceSubrange(range, with: "INLINE_CODE_\(index)")
            }
        } catch {
            print("インラインコード変換エラー: \(error)")
        }
        
        // 見出し変換
        html = convertHeadings(html)
        
        // 太字・斜体・取り消し線変換
        html = convertBoldItalicStrikethrough(html)
        
        // リスト変換
        html = convertLists(html)
        
        // 引用変換
        html = convertBlockquotes(html)
        
        // 表変換
        html = convertTables(html)
        
        // リンク変換
        html = convertLinks(html)
        
        // 画像変換
        html = convertImages(html)
        
        // 改行変換
        html = html.replacingOccurrences(of: "\n", with: "<br>")
        
        // コードブロックを復元
        for (index, codeBlock) in codeBlocks.enumerated() {
            let codeContent = codeBlock.replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            html = html.replacingOccurrences(of: "CODE_BLOCK_\(index)", 
                                           with: "<pre><code>\(codeContent)</code></pre>")
        }
        
        // インラインコードを復元
        for (index, inlineCode) in inlineCodes.enumerated() {
            let codeContent = inlineCode.replacingOccurrences(of: "`", with: "")
            html = html.replacingOccurrences(of: "INLINE_CODE_\(index)", 
                                           with: "<code>\(codeContent)</code>")
        }
        
        return wrapInHTMLDocument(html)
    }
    
    // MARK: - Private Helper Methods
    private static func convertHeadings(_ text: String) -> String {
        var result = text
        
        // H1-H6の変換
        for level in 1...6 {
            let hashSymbols = String(repeating: "#", count: level)
            let pattern = "^" + NSRegularExpression.escapedPattern(for: hashSymbols) + "\\s+(.+)$"
            do {
                let regex = try NSRegularExpression(pattern: pattern, options: .anchorsMatchLines)
                result = regex.stringByReplacingMatches(in: result, 
                                                      options: [], 
                                                      range: NSRange(result.startIndex..., in: result), 
                                                      withTemplate: "<h\(level)>$1</h\(level)>")
            } catch {
                print("見出し変換エラー (レベル\(level)): \(error)")
            }
        }
        
        return result
    }
    
    private static func convertBoldItalicStrikethrough(_ text: String) -> String {
        var result = text
        
        // 取り消し線変換 ~~text~~
        let strikethroughPattern = #"~~([^~]+)~~"#
        do {
            let strikethroughRegex = try NSRegularExpression(pattern: strikethroughPattern)
            result = strikethroughRegex.stringByReplacingMatches(in: result, 
                                                              options: [], 
                                                              range: NSRange(result.startIndex..., in: result), 
                                                              withTemplate: "<del>$1</del>")
        } catch {
            print("取り消し線変換エラー: \(error)")
        }
        
        // 太字変換 **text**
        let boldPattern = #"\*\*([^\*]+)\*\*"#
        do {
            let boldRegex = try NSRegularExpression(pattern: boldPattern)
            result = boldRegex.stringByReplacingMatches(in: result, 
                                                      options: [], 
                                                      range: NSRange(result.startIndex..., in: result), 
                                                      withTemplate: "<strong>$1</strong>")
        } catch {
            print("太字変換エラー: \(error)")
        }
        
        // 斜体変換 *text*
        let italicPattern = #"\*([^\*]+)\*"#
        do {
            let italicRegex = try NSRegularExpression(pattern: italicPattern)
            result = italicRegex.stringByReplacingMatches(in: result, 
                                                        options: [], 
                                                        range: NSRange(result.startIndex..., in: result), 
                                                        withTemplate: "<em>$1</em>")
        } catch {
            print("斜体変換エラー: \(error)")
        }
        
        return result
    }
    
    private static func convertLists(_ text: String) -> String {
        let result = text
        let lines = result.components(separatedBy: .newlines)
        var processedLines: [String] = []
        var inUnorderedList = false
        var inOrderedList = false
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            
            // 順序なしリスト
            if trimmedLine.hasPrefix("- ") || trimmedLine.hasPrefix("* ") {
                if !inUnorderedList {
                    processedLines.append("<ul>")
                    inUnorderedList = true
                }
                if inOrderedList {
                    processedLines.append("</ol>")
                    inOrderedList = false
                }
                let content = String(trimmedLine.dropFirst(2))
                processedLines.append("<li>\(content)</li>")
            }
            // 順序ありリスト
            else if trimmedLine.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil {
                if !inOrderedList {
                    processedLines.append("<ol>")
                    inOrderedList = true
                }
                if inUnorderedList {
                    processedLines.append("</ul>")
                    inUnorderedList = false
                }
                do {
                    let regex = try NSRegularExpression(pattern: #"^\d+\.\s(.+)$"#)
                    let range = NSRange(trimmedLine.startIndex..., in: trimmedLine)
                    if let match = regex.firstMatch(in: trimmedLine, range: range) {
                        let contentRange = Range(match.range(at: 1), in: trimmedLine)!
                        let content = String(trimmedLine[contentRange])
                        processedLines.append("<li>\(content)</li>")
                    }
                } catch {
                    print("順序ありリスト変換エラー: \(error)")
                    // フォールバック: 単純な文字列処理
                    if let dotIndex = trimmedLine.firstIndex(of: ".") {
                        let content = String(trimmedLine[trimmedLine.index(after: dotIndex)...].trimmingCharacters(in: .whitespaces))
                        processedLines.append("<li>\(content)</li>")
                    }
                }
            }
            // リストの終了
            else {
                if inUnorderedList {
                    processedLines.append("</ul>")
                    inUnorderedList = false
                }
                if inOrderedList {
                    processedLines.append("</ol>")
                    inOrderedList = false
                }
                processedLines.append(line)
            }
        }
        
        // 最後にリストが開いている場合は閉じる
        if inUnorderedList {
            processedLines.append("</ul>")
        }
        if inOrderedList {
            processedLines.append("</ol>")
        }
        
        return processedLines.joined(separator: "\n")
    }
    
    private static func convertBlockquotes(_ text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
        var processedLines: [String] = []
        var inBlockquote = false
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            
            if trimmedLine.hasPrefix("> ") {
                if !inBlockquote {
                    processedLines.append("<blockquote>")
                    inBlockquote = true
                }
                let content = String(trimmedLine.dropFirst(2))
                processedLines.append(content)
            } else {
                if inBlockquote {
                    processedLines.append("</blockquote>")
                    inBlockquote = false
                }
                processedLines.append(line)
            }
        }
        
        if inBlockquote {
            processedLines.append("</blockquote>")
        }
        
        return processedLines.joined(separator: "\n")
    }
    
    private static func convertTables(_ text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
        var processedLines: [String] = []
        var inTable = false
        var tableRows: [String] = []
        
        for (_, line) in lines.enumerated() {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            
            // 表の行かどうかを判定（|で始まり|で終わる）
            if trimmedLine.hasPrefix("|") && trimmedLine.hasSuffix("|") {
                if !inTable {
                    inTable = true
                    tableRows = []
                }
                tableRows.append(trimmedLine)
            } else {
                // 表の終了処理
                if inTable {
                    let tableHTML = generateTableHTML(from: tableRows)
                    processedLines.append(tableHTML)
                    inTable = false
                    tableRows = []
                }
                processedLines.append(line)
            }
        }
        
        // 最後に表が開いている場合は閉じる
        if inTable {
            let tableHTML = generateTableHTML(from: tableRows)
            processedLines.append(tableHTML)
        }
        
        return processedLines.joined(separator: "\n")
    }
    
    private static func generateTableHTML(from rows: [String]) -> String {
        guard !rows.isEmpty else { return "" }
        
        var html = "<table>\n"
        
        for (index, row) in rows.enumerated() {
            // セパレーター行をスキップ（2行目で全て-と|の組み合わせ）
            if index == 1 && row.trimmingCharacters(in: .whitespaces).allSatisfy({ $0 == "|" || $0 == "-" || $0 == ":" || $0.isWhitespace }) {
                continue
            }
            
            // セルを解析
            let cells = parseCells(from: row)
            let isHeader = index == 0
            let cellTag = isHeader ? "th" : "td"
            
            html += "  <tr>\n"
            for cell in cells {
                let cellContent = cell.trimmingCharacters(in: .whitespacesAndNewlines)
                html += "    <\(cellTag)>\(cellContent)</\(cellTag)>\n"
            }
            html += "  </tr>\n"
        }
        
        html += "</table>"
        return html
    }
    
    private static func parseCells(from row: String) -> [String] {
        // |で区切ってセルを抽出
        var cells = row.components(separatedBy: "|")
        
        // 最初と最後の空要素を削除
        if cells.first?.trimmingCharacters(in: .whitespaces).isEmpty == true {
            cells.removeFirst()
        }
        if cells.last?.trimmingCharacters(in: .whitespaces).isEmpty == true {
            cells.removeLast()
        }
        
        return cells
    }
    
    private static func convertLinks(_ text: String) -> String {
        let linkPattern = #"\[([^\]]+)\]\(([^)]+)\)"#
        do {
            let linkRegex = try NSRegularExpression(pattern: linkPattern)
            var result = text
            let matches = linkRegex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            
            // 逆順で処理してインデックスのずれを防ぐ
            for match in matches.reversed() {
                guard let linkTextRange = Range(match.range(at: 1), in: text),
                      let linkURLRange = Range(match.range(at: 2), in: text),
                      let fullRange = Range(match.range, in: text) else { continue }
                
                let linkText = String(text[linkTextRange])
                let linkURL = String(text[linkURLRange])
                
                // リンクの種類を判定
                let isExternalLink = linkURL.hasPrefix("http://") || linkURL.hasPrefix("https://")
                let isInternalLink = linkURL.hasPrefix("#")
                
                var replacement: String
                if isExternalLink {
                    // 外部リンクはテキストのみ表示、URLは非表示でクリック可能
                    replacement = "<a href=\"\(linkURL)\" target=\"_blank\" rel=\"noopener noreferrer\" style=\"color: #007aff; text-decoration: underline;\">\(linkText)</a>"
                } else if isInternalLink {
                    // 内部リンクは紫色で表示
                    replacement = "<a href=\"\(linkURL)\" style=\"color: #9932cc; text-decoration: underline;\">\(linkText)</a> <span style=\"color: #666; font-size: 0.9em;\">→ \(linkURL)</span>"
                } else {
                    // その他のリンクはテキストのみ表示
                    replacement = "<a href=\"\(linkURL)\" style=\"color: #007aff; text-decoration: underline;\">\(linkText)</a>"
                }
                
                result.replaceSubrange(fullRange, with: replacement)
            }
            
            return result
        } catch {
            print("リンク変換エラー: \(error)")
            return text
        }
    }
    
    private static func convertImages(_ text: String) -> String {
        let imagePattern = #"!\[([^\]]*)\]\(([^)]+)\)"#
        do {
            let imageRegex = try NSRegularExpression(pattern: imagePattern)
            var result = text
            let matches = imageRegex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            
            // 逆順で処理してインデックスのずれを防ぐ
            for match in matches.reversed() {
                guard let altRange = Range(match.range(at: 1), in: text),
                      let urlRange = Range(match.range(at: 2), in: text),
                      let fullRange = Range(match.range, in: text) else { continue }
                
                let altText = String(text[altRange])
                let imageURL = String(text[urlRange])
                
                let replacement: String
                if imageURL.hasPrefix("http://") || imageURL.hasPrefix("https://") {
                    // URL画像の場合は直接URLを使用し、プリロードして確実に表示
                    replacement = "<img src=\"\(imageURL)\" alt=\"\(altText)\" style=\"max-width: 100%; height: auto; border-radius: 8px; margin: 10px 0; display: block;\" crossorigin=\"anonymous\" loading=\"eager\" onload=\"this.style.display='block'\" onerror=\"this.style.display='none'; this.insertAdjacentHTML('afterend', '<div style=\\\"padding: 20px; background-color: #f5f5f5; border: 1px dashed #ccc; text-align: center; margin: 10px 0;\\\">画像の読み込みに失敗しました: \(altText.isEmpty ? imageURL : altText)</div>')\" />"
                } else {
                    // ローカル画像の場合はBase64エンコード
                    let imageBase64 = getImageBase64(imageURL: imageURL)
                    if !imageBase64.isEmpty {
                        let mimeType = determineMimeType(from: imageURL)
                        replacement = "<img src=\"data:\(mimeType);base64,\(imageBase64)\" alt=\"\(altText)\" style=\"max-width: 100%; height: auto; border-radius: 8px; margin: 10px 0; display: block;\" />"
                    } else {
                        replacement = "<div style=\"padding: 20px; background-color: #f5f5f5; border: 1px dashed #ccc; text-align: center; margin: 10px 0;\">画像が見つかりません: \(altText.isEmpty ? imageURL : altText)</div>"
                    }
                }
                
                result.replaceSubrange(fullRange, with: replacement)
            }
            
            return result
        } catch {
            print("画像変換エラー: \(error)")
            return text
        }
    }
    
    private static func getImageBase64(imageURL: String) -> String {
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("❌ Documents directory取得失敗")
            return ""
        }
        
        let imagesDirectory = documentsDirectory.appendingPathComponent("images")
        let imageFileURL = imagesDirectory.appendingPathComponent(imageURL)
        
        do {
            let imageData = try Data(contentsOf: imageFileURL)
            return imageData.base64EncodedString()
        } catch {
            print("❌ 画像ファイルの読み込みに失敗: \(imageFileURL.path) - \(error)")
            return ""
        }
    }
    
    /// URLの拡張子からMIMEタイプを判定
    private static func determineMimeType(from url: String) -> String {
        let lowercaseURL = url.lowercased()
        
        if lowercaseURL.contains(".png") {
            return "image/png"
        } else if lowercaseURL.contains(".gif") {
            return "image/gif"
        } else if lowercaseURL.contains(".webp") {
            return "image/webp"
        } else if lowercaseURL.contains(".svg") {
            return "image/svg+xml"
        } else if lowercaseURL.contains(".bmp") {
            return "image/bmp"
        } else {
            // デフォルトはJPEG
            return "image/jpeg"
        }
    }
    
    private static func wrapInHTMLDocument(_ body: String) -> String {
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <meta http-equiv="Content-Security-Policy" content="default-src 'self'; img-src 'self' data: https: http:; style-src 'self' 'unsafe-inline';">
            <title>Memo</title>
            <style>
                .markdown-preview {
                  font-family: -apple-system, BlinkMacSystemFont, 'Helvetica Neue', Helvetica, 'Segoe UI', Arial, sans-serif;
                  font-size: 16px;
                  line-height: 1.4;
                  word-wrap: break-word;
                  box-sizing: border-box;
                  counter-reset: h1;
                  padding: 2rem;
                }
                
                /* ライトモード用のベース色 */
                @media (prefers-color-scheme: light) {
                  .markdown-preview {
                    color: #1a1a1a;
                    background-color: #ffffff;
                  }
                }
                
                /* ダークモード用のベース色 */
                @media (prefers-color-scheme: dark) {
                  .markdown-preview {
                    color: #ffffff !important;
                    background-color: #1a1a1a !important;
                  }
                }

                /* 各種見出し */
                .markdown-preview h1,
                .markdown-preview h2,
                .markdown-preview h3,
                .markdown-preview h4,
                .markdown-preview h5,
                .markdown-preview h6 {
                  font-weight: 600;
                  margin-top: 0.1em;
                  margin-bottom: 0.05em;
                  line-height: 1.05;
                }
                
                /* ライトモード用の見出し色 */
                @media (prefers-color-scheme: light) {
                  body.markdown-preview h1,
                  body.markdown-preview h2,
                  body.markdown-preview h3,
                  body.markdown-preview h4,
                  body.markdown-preview h5,
                  body.markdown-preview h6,
                  .markdown-preview h1,
                  .markdown-preview h2,
                  .markdown-preview h3,
                  .markdown-preview h4,
                  .markdown-preview h5,
                  .markdown-preview h6 {
                    color: #000000 !important;
                  }
                }
                
                /* ダークモード用の見出し色 - 最優先設定 */
                @media (prefers-color-scheme: dark) {
                  body.markdown-preview h1,
                  body.markdown-preview h2,
                  body.markdown-preview h3,
                  body.markdown-preview h4,
                  body.markdown-preview h5,
                  body.markdown-preview h6,
                  .markdown-preview h1,
                  .markdown-preview h2,
                  .markdown-preview h3,
                  .markdown-preview h4,
                  .markdown-preview h5,
                  .markdown-preview h6 {
                    color: #ffffff !important;
                  }
                }

                .markdown-preview h1 {
                  font-size: 2.2em;
                  text-align: center;
                  padding-bottom: 0.3em;
                  counter-reset: h2;
                  width: 100%;
                  display: block;
                }

                .markdown-preview h2 {
                  font-size: 1.8em;
                  padding: 5px;
                  counter-reset: h3;
                  width: 100%;
                  display: block;
                }
                
                /* ライトモード用の境界線 */
                @media (prefers-color-scheme: light) {
                  .markdown-preview h1 {
                    border-bottom: 2px solid #000;
                  }
                  .markdown-preview h2 {
                    border-bottom: 4px solid #000;
                  }
                }
                
                /* ダークモード用の境界線 */
                @media (prefers-color-scheme: dark) {
                  .markdown-preview h1 {
                    border-bottom: 2px solid #fff !important;
                  }
                  .markdown-preview h2 {
                    border-bottom: 4px solid #fff !important;
                  }
                }

                .markdown-preview h2::before {
                  counter-increment: h2;
                  content: counter(h2) ". ";
                }

                .markdown-preview h3 {
                  font-size: 1.5em;
                  padding: 5px 10px;
                  counter-reset: h4;
                  width: 100%;
                  display: block;
                }
                
                /* ライトモード用のh3境界線 */
                @media (prefers-color-scheme: light) {
                  .markdown-preview h3 {
                    border-left: 8px solid #000;
                    border-bottom: 2px solid #000;
                  }
                }
                
                /* ダークモード用のh3境界線 */
                @media (prefers-color-scheme: dark) {
                  .markdown-preview h3 {
                    border-left: 8px solid #fff !important;
                    border-bottom: 2px solid #fff !important;
                  }
                }

                .markdown-preview h3::before {
                  counter-increment: h3;
                  content: counter(h2) ". " counter(h3) ". ";
                }

                .markdown-preview h4 {
                  font-size: 1.25em;
                  padding: 5px 15px;
                  counter-reset: h5;
                }
                
                /* ライトモード用のh4境界線 */
                @media (prefers-color-scheme: light) {
                  .markdown-preview h4 {
                    border-left: 4px solid #000;
                  }
                }
                
                /* ダークモード用のh4境界線 */
                @media (prefers-color-scheme: dark) {
                  .markdown-preview h4 {
                    border-left: 4px solid #fff !important;
                  }
                }

                .markdown-preview h4::before {
                  counter-increment: h4;
                  content: counter(h2) ". " counter(h3) ". " counter(h4) ". ";
                }

                .markdown-preview h5,
                .markdown-preview h6 {
                  font-size: 1.1em;
                  padding: 5px 15px;
                }
                
                /* ライトモード用のh5, h6境界線 */
                @media (prefers-color-scheme: light) {
                  .markdown-preview h5,
                  .markdown-preview h6 {
                    border-left: 3px solid #000;
                  }
                }
                
                /* ダークモード用のh5, h6境界線 */
                @media (prefers-color-scheme: dark) {
                  .markdown-preview h5,
                  .markdown-preview h6 {
                    border-left: 3px solid #fff !important;
                  }
                }

                .markdown-preview h5::before {
                  counter-increment: h5;
                  content: counter(h2) ". " counter(h3) ". " counter(h4) ". " counter(h5) ". ";
                }

                .markdown-preview h6::before {
                  counter-increment: h6;
                  content: counter(h2) ". " counter(h3) ". " counter(h4) ". " counter(h5) ". " counter(h6) ". ";
                }

                .markdown-preview p,
                .markdown-preview li,
                .markdown-preview blockquote,
                .markdown-preview code {
                  font-size: 1em;
                }

                /* 段落・リスト */
                .markdown-preview p {
                  margin-bottom: 0.05em;
                }

                .markdown-preview ul,
                .markdown-preview ol {
                  margin-bottom: 0.05em;
                  padding-left: 2em;
                }
                
                /* リストマーカーの色を強制的に文字色と同じに設定 */
                .markdown-preview ul,
                .markdown-preview ol {
                  list-style-position: outside;
                }
                
                .markdown-preview ul li,
                .markdown-preview ol li {
                  position: relative;
                  line-height: 1.4;
                }
                
                /* ライトモード用のリストマーカー色 */
                @media (prefers-color-scheme: light) {
                  .markdown-preview ul,
                  .markdown-preview ol,
                  body.markdown-preview ul,
                  body.markdown-preview ol {
                    color: #1a1a1a !important;
                  }
                  
                  .markdown-preview ul li::marker,
                  .markdown-preview ol li::marker,
                  body.markdown-preview ul li::marker,
                  body.markdown-preview ol li::marker,
                  .markdown-preview ul li::before,
                  .markdown-preview ol li::before,
                  body.markdown-preview ul li::before,
                  body.markdown-preview ol li::before {
                    color: #1a1a1a !important;
                  }
                  
                  .markdown-preview ul li,
                  .markdown-preview ol li,
                  body.markdown-preview ul li,
                  body.markdown-preview ol li {
                    color: #1a1a1a !important;
                  }
                }
                
                /* ダークモード用のリストマーカー色 */
                @media (prefers-color-scheme: dark) {
                  .markdown-preview ul,
                  .markdown-preview ol,
                  body.markdown-preview ul,
                  body.markdown-preview ol {
                    color: #ffffff !important;
                  }
                  
                  .markdown-preview ul li::marker,
                  .markdown-preview ol li::marker,
                  body.markdown-preview ul li::marker,
                  body.markdown-preview ol li::marker,
                  .markdown-preview ul li::before,
                  .markdown-preview ol li::before,
                  body.markdown-preview ul li::before,
                  body.markdown-preview ol li::before {
                    color: #ffffff !important;
                  }
                  
                  .markdown-preview ul li,
                  .markdown-preview ol li,
                  body.markdown-preview ul li,
                  body.markdown-preview ol li {
                    color: #ffffff !important;
                  }
                }

                .markdown-preview li.task-list-item {
                  list-style: none;
                }

                .markdown-preview .task-list-item-checkbox {
                  margin-right: 0.5em;
                  transform: scale(1.2);
                }

                /* リンク */
                .markdown-preview a {
                  color: #007aff;
                  text-decoration: none;
                }

                .markdown-preview a:hover {
                  text-decoration: underline;
                }

                /* 引用 */
                .markdown-preview blockquote {
                  background-color: #f8f8f8;
                  border-left: 4px solid #ccc;
                  padding: 0.1em 1em;
                  color: #555;
                  margin: 0.05em 0;
                  line-height: 1.4;
                }

                /* コード */
                .markdown-preview code {
                  background-color: #f2f2f2;
                  font-family: SFMono-Regular, Menlo, Monaco, Consolas, "Courier New", monospace;
                  font-size: 0.95em;
                  padding: 0.2em 0.4em;
                  border-radius: 4px;
                }

                .markdown-preview pre code {
                  background: none;
                  padding: 0;
                }

                .markdown-preview pre {
                  background-color: #f2f2f2;
                  padding: 1em;
                  overflow: auto;
                  border-radius: 4px;
                  line-height: 1.5;
                }

                /* テーブル */
                .markdown-preview table {
                  border-collapse: collapse;
                  width: 100%;
                  margin: 0.1em 0;
                  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Arial, sans-serif;
                  border: 1px solid #ddd;
                }

                .markdown-preview th,
                .markdown-preview td {
                  border: 1px solid #ddd;
                  padding: 6px 8px;
                  text-align: left;
                  vertical-align: top;
                  word-wrap: break-word;
                  white-space: pre-wrap;
                  line-height: 1.3;
                }

                .markdown-preview th {
                  background-color: #f5f5f5;
                  color: #333;
                  font-weight: bold;
                  text-align: left;
                }

                .markdown-preview tr:nth-child(even) td {
                  background-color: #fafafa;
                }

                .markdown-preview tr:nth-child(odd) td {
                  background-color: #ffffff;
                }

                /* その他 */
                .markdown-preview hr {
                  border: none;
                  border-top: 3px solid #ccc;
                  margin: 0.1em 0;
                }

                .markdown-preview kbd {
                  background-color: #eee;
                  border: 1px solid #ccc;
                  padding: 2px 6px;
                  border-radius: 3px;
                  font-family: SFMono-Regular, monospace;
                }

                /* ルートスタイル */
                body {
                  font-family: -apple-system, BlinkMacSystemFont, 'Helvetica Neue', Helvetica, 'Segoe UI', Arial, sans-serif;
                  font-size: 16px;
                  line-height: 1.4;
                  word-wrap: break-word;
                  box-sizing: border-box;
                }
                
                /* ライトモード用のボディ */
                @media (prefers-color-scheme: light) {
                  body {
                    color: #1a1a1a;
                    background-color: #ffffff;
                  }
                }
                
                /* ダークモード用のボディ */
                @media (prefers-color-scheme: dark) {
                  body {
                    color: #ffffff;
                    background-color: #1a1a1a;
                  }
                }

                /* 各種見出し */
                h1,
                h2,
                h3,
                h4,
                h5,
                h6 {
                  font-weight: 600;
                  margin-top: 0.1em;
                  margin-bottom: 0.05em;
                  line-height: 1.05;
                }
                
                /* ライトモード用の見出し色 */
                @media (prefers-color-scheme: light) {
                  h1,
                  h2,
                  h3,
                  h4,
                  h5,
                  h6 {
                    color: #000000 !important;
                  }
                }
                
                /* ダークモード用の見出し色 */
                @media (prefers-color-scheme: dark) {
                  h1,
                  h2,
                  h3,
                  h4,
                  h5,
                  h6 {
                    color: #ffffff !important;
                  }
                }

                h1 {
                  font-size: 2.2em;
                  text-align: center;
                  padding-bottom: 0.3em;
                  counter-reset: h2;
                  width: 100%;
                  display: block;
                }
                
                /* ライトモード用の境界線 */
                @media (prefers-color-scheme: light) {
                  h1 {
                    border-bottom: 2px solid #000;
                  }
                  h2 {
                    border-bottom: 4px solid #000;
                  }
                }
                
                /* ダークモード用の境界線 */
                @media (prefers-color-scheme: dark) {
                  h1 {
                    border-bottom: 2px solid #fff;
                  }
                  h2 {
                    border-bottom: 4px solid #fff;
                  }
                }

                h2 {
                  font-size: 1.8em;
                  padding: 5px;
                  counter-reset: h3;
                  width: 100%;
                  display: block;
                }

                h2::before {
                  counter-increment: h2;
                  content: counter(h2) ". ";
                }

                h3 {
                  font-size: 1.5em;
                  padding: 5px 10px;
                  counter-reset: h4;
                  width: 100%;
                  display: block;
                }
                
                /* ライトモード用のh3境界線 */
                @media (prefers-color-scheme: light) {
                  h3 {
                    border-left: 8px solid #000;
                    border-bottom: 2px solid #000;
                  }
                }
                
                /* ダークモード用のh3境界線 */
                @media (prefers-color-scheme: dark) {
                  h3 {
                    border-left: 8px solid #fff;
                    border-bottom: 2px solid #fff;
                  }
                }

                h3::before {
                  counter-increment: h3;
                  content: counter(h2) ". " counter(h3) ". ";
                }

                h4 {
                  font-size: 1.25em;
                  padding: 5px 15px;
                  counter-reset: h5;
                }
                
                /* ライトモード用のh4境界線 */
                @media (prefers-color-scheme: light) {
                  h4 {
                    border-left: 4px solid #000;
                  }
                }
                
                /* ダークモード用のh4境界線 */
                @media (prefers-color-scheme: dark) {
                  h4 {
                    border-left: 4px solid #fff;
                  }
                }

                h4::before {
                  counter-increment: h4;
                  content: counter(h2) ". " counter(h3) ". " counter(h4) ". ";
                }

                h5,
                h6 {
                  font-size: 1.1em;
                  padding: 5px 15px;
                }
                
                /* ライトモード用のh5, h6境界線 */
                @media (prefers-color-scheme: light) {
                  h5,
                  h6 {
                    border-left: 3px solid #000;
                  }
                }
                
                /* ダークモード用のh5, h6境界線 */
                @media (prefers-color-scheme: dark) {
                  h5,
                  h6 {
                    border-left: 3px solid #fff;
                  }
                }

                h5::before {
                  counter-increment: h5;
                  content: counter(h2) ". " counter(h3) ". " counter(h4) ". " counter(h5) ". ";
                }

                h6::before {
                  counter-increment: h6;
                  content: counter(h2) ". " counter(h3) ". " counter(h4) ". " counter(h5) ". " counter(h6) ". ";
                }

                p,
                li,
                blockquote,
                code {
                  font-size: 1em;
                }

                /* 段落・リスト */
                p {
                  margin-bottom: 0.05em;
                }

                ul,
                ol {
                  margin-bottom: 0.05em;
                  padding-left: 2em;
                }
                
                /* リストマーカーの色を強制的に文字色と同じに設定 */
                ul,
                ol {
                  list-style-position: outside;
                }
                
                ul li,
                ol li {
                  position: relative;
                  line-height: 1.4;
                }
                
                /* ライトモード用のリストマーカー色 */
                @media (prefers-color-scheme: light) {
                  ul,
                  ol,
                  body ul,
                  body ol {
                    color: #1a1a1a !important;
                  }
                  
                  ul li::marker,
                  ol li::marker,
                  body ul li::marker,
                  body ol li::marker,
                  ul li::before,
                  ol li::before,
                  body ul li::before,
                  body ol li::before {
                    color: #1a1a1a !important;
                  }
                  
                  ul li,
                  ol li,
                  body ul li,
                  body ol li {
                    color: #1a1a1a !important;
                  }
                }
                
                /* ダークモード用のリストマーカー色 */
                @media (prefers-color-scheme: dark) {
                  ul,
                  ol,
                  body ul,
                  body ol {
                    color: #ffffff !important;
                  }
                  
                  ul li::marker,
                  ol li::marker,
                  body ul li::marker,
                  body ol li::marker,
                  ul li::before,
                  ol li::before,
                  body ul li::before,
                  body ol li::before {
                    color: #ffffff !important;
                  }
                  
                  ul li,
                  ol li,
                  body ul li,
                  body ol li {
                    color: #ffffff !important;
                  }
                }

                li.task-list-item {
                  list-style: none;
                }

                .task-list-item-checkbox {
                  margin-right: 0.5em;
                  transform: scale(1.2);
                }

                /* リンク */
                a {
                  color: #007aff;
                  text-decoration: none;
                }

                a:hover {
                  text-decoration: underline;
                }

                /* 引用 */
                blockquote {
                  background-color: #f8f8f8;
                  border-left: 4px solid #ccc;
                  padding: 0.1em 1em;
                  color: #555;
                  margin: 0.05em 0;
                  line-height: 1.4;
                }

                /* コード */
                code {
                  background-color: #f2f2f2;
                  font-family: SFMono-Regular, Menlo, Monaco, Consolas, "Courier New", monospace;
                  font-size: 0.95em;
                  padding: 0.2em 0.4em;
                  border-radius: 4px;
                }

                pre code {
                  background: none;
                  padding: 0;
                }

                pre {
                  background-color: #f2f2f2;
                  padding: 1em;
                  overflow: auto;
                  border-radius: 4px;
                  line-height: 1.5;
                }

                /* テーブル */
                table {
                  border-collapse: collapse;
                  width: 100%;
                  margin: 0.1em 0;
                  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Arial, sans-serif;
                  border: 1px solid #ddd;
                }

                th,
                td {
                  border: 1px solid #ddd;
                  padding: 6px 8px;
                  text-align: left;
                  vertical-align: top;
                  word-wrap: break-word;
                  white-space: pre-wrap;
                  line-height: 1.3;
                }

                th {
                  background-color: #f5f5f5;
                  color: #333;
                  font-weight: bold;
                  text-align: left;
                }

                tr:nth-child(even) td {
                  background-color: #fafafa;
                }

                tr:nth-child(odd) td {
                  background-color: #ffffff;
                }

                /* その他 */
                hr {
                  border: none;
                  border-top: 3px solid #ccc;
                  margin: 0.1em 0;
                }

                kbd {
                  background-color: #eee;
                  border: 1px solid #ccc;
                  padding: 2px 6px;
                  border-radius: 3px;
                  font-family: SFMono-Regular, monospace;
                }

                /* 取り消し線 */
                del {
                  text-decoration: line-through;
                  color: #888;
                }

                /* 見出し色の最終保険設定 - ライトモード */
                @media (prefers-color-scheme: light) {
                  * h1, * h2, * h3, * h4, * h5, * h6 {
                    color: #000000 !important;
                  }
                  
                  body * h1, body * h2, body * h3 {
                    color: #000000 !important;
                  }
                }

                /* 見出し色の最終保険設定 - ダークモード */
                @media (prefers-color-scheme: dark) {
                  * h1, * h2, * h3, * h4, * h5, * h6 {
                    color: #ffffff !important;
                  }
                  
                  body * h1, body * h2, body * h3 {
                    color: #ffffff !important;
                  }
                }

                /* 【絶対確実】リストマーカーの色の最終保険設定 - 最高優先度 */
                ul::marker, ol::marker { color: inherit !important; }
                ul li::marker, ol li::marker { color: inherit !important; }
                .markdown-preview ul::marker, .markdown-preview ol::marker { color: inherit !important; }
                .markdown-preview ul li::marker, .markdown-preview ol li::marker { color: inherit !important; }
                body.markdown-preview ul::marker, body.markdown-preview ol::marker { color: inherit !important; }
                body.markdown-preview ul li::marker, body.markdown-preview ol li::marker { color: inherit !important; }
                html body.markdown-preview ul::marker, html body.markdown-preview ol::marker { color: inherit !important; }
                html body.markdown-preview ul li::marker, html body.markdown-preview ol li::marker { color: inherit !important; }
                
                @media (prefers-color-scheme: light) {
                  ul, ol, ul li, ol li { color: #1a1a1a !important; }
                  ul::marker, ol::marker { color: #1a1a1a !important; }
                  ul li::marker, ol li::marker { color: #1a1a1a !important; }
                  .markdown-preview ul, .markdown-preview ol, .markdown-preview ul li, .markdown-preview ol li { color: #1a1a1a !important; }
                  .markdown-preview ul::marker, .markdown-preview ol::marker { color: #1a1a1a !important; }
                  .markdown-preview ul li::marker, .markdown-preview ol li::marker { color: #1a1a1a !important; }
                  body.markdown-preview ul, body.markdown-preview ol, body.markdown-preview ul li, body.markdown-preview ol li { color: #1a1a1a !important; }
                  body.markdown-preview ul::marker, body.markdown-preview ol::marker { color: #1a1a1a !important; }
                  body.markdown-preview ul li::marker, body.markdown-preview ol li::marker { color: #1a1a1a !important; }
                  html body.markdown-preview ul, html body.markdown-preview ol, html body.markdown-preview ul li, html body.markdown-preview ol li { color: #1a1a1a !important; }
                  html body.markdown-preview ul::marker, html body.markdown-preview ol::marker { color: #1a1a1a !important; }
                  html body.markdown-preview ul li::marker, html body.markdown-preview ol li::marker { color: #1a1a1a !important; }
                  * ul, * ol, * ul li, * ol li { color: #1a1a1a !important; }
                  * ul::marker, * ol::marker { color: #1a1a1a !important; }
                  * ul li::marker, * ol li::marker { color: #1a1a1a !important; }
                }

                @media (prefers-color-scheme: dark) {
                  ul, ol, ul li, ol li { color: #ffffff !important; }
                  ul::marker, ol::marker { color: #ffffff !important; }
                  ul li::marker, ol li::marker { color: #ffffff !important; }
                  .markdown-preview ul, .markdown-preview ol, .markdown-preview ul li, .markdown-preview ol li { color: #ffffff !important; }
                  .markdown-preview ul::marker, .markdown-preview ol::marker { color: #ffffff !important; }
                  .markdown-preview ul li::marker, .markdown-preview ol li::marker { color: #ffffff !important; }
                  body.markdown-preview ul, body.markdown-preview ol, body.markdown-preview ul li, body.markdown-preview ol li { color: #ffffff !important; }
                  body.markdown-preview ul::marker, body.markdown-preview ol::marker { color: #ffffff !important; }
                  body.markdown-preview ul li::marker, body.markdown-preview ol li::marker { color: #ffffff !important; }
                  html body.markdown-preview ul, html body.markdown-preview ol, html body.markdown-preview ul li, html body.markdown-preview ol li { color: #ffffff !important; }
                  html body.markdown-preview ul::marker, html body.markdown-preview ol::marker { color: #ffffff !important; }
                  html body.markdown-preview ul li::marker, html body.markdown-preview ol li::marker { color: #ffffff !important; }
                  * ul, * ol, * ul li, * ol li { color: #ffffff !important; }
                  * ul::marker, * ol::marker { color: #ffffff !important; }
                  * ul li::marker, * ol li::marker { color: #ffffff !important; }
                }
                
                /* 【緊急措置】どうしても効かない場合の最終手段 */
                ul li { list-style-color: currentColor !important; }
                ol li { list-style-color: currentColor !important; }
                .markdown-preview ul li { list-style-color: currentColor !important; }
                .markdown-preview ol li { list-style-color: currentColor !important; }
                body.markdown-preview ul li { list-style-color: currentColor !important; }
                body.markdown-preview ol li { list-style-color: currentColor !important; }

                @media print {
                  body {
                    background-color: #fff;
                    color: #000;
                  }

                  h1,
                  h2,
                  h3,
                  h4 {
                    page-break-after: avoid;
                  }

                  pre,
                  blockquote {
                    page-break-inside: avoid;
                  }
                }
            </style>
        </head>
        <body class="markdown-preview">
            \(body)
        </body>
        </html>
        """
    }
}

// MARK: - PDF Generation
extension MarkdownRenderer {
    
    /// HTMLからPDFを生成（非推奨 - SwiftUI MarkdownText方式を使用）
    /// - Parameters:
    ///   - html: HTMLテキスト
    ///   - completion: 完了時のコールバック（PDFData or nil）
    @available(*, deprecated, message: "Use generatePDF(from memo:) instead")
    static func generatePDF(from html: String, completion: @escaping (Data?) -> Void) {
        print("⚠️ 非推奨のHTML-PDF生成が呼び出されました。SwiftUI方式を推奨します。")
        // フォールバック機能のみ提供
        generateFallbackPDF(from: html, completion: completion)
    }
    
    /// フォールバック用の高品質PDF生成
    /// - Parameters:
    ///   - html: HTMLテキスト
    ///   - completion: 完了時のコールバック
    private static func generateFallbackPDF(from html: String, completion: @escaping (Data?) -> Void) {
        print("フォールバック PDF生成を実行")
        
        // UIWebViewを使った代替案（iOS 12以降非推奨だが、PDFRendererとして利用）
        DispatchQueue.main.async {
            generateStyledPDFFromHTML(html: html, completion: completion)
        }
    }
    
    /// スタイル付きPDF生成（UIKitベース）
    private static func generateStyledPDFFromHTML(html: String, completion: @escaping (Data?) -> Void) {
        // NSAttributedStringでHTMLを解析
        guard let htmlData = html.data(using: .utf8) else {
            print("HTML データ変換エラー")
            generateManualStyledPDF(from: html, completion: completion)
            return
        }
        
        do {
            let attributedString = try NSAttributedString(
                data: htmlData,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue
                ],
                documentAttributes: nil
            )
            
            // PDFコンテキストを作成
            let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842) // A4サイズ
            let printableRect = CGRect(x: 30, y: 40, width: 535, height: 762)
            let pdfData = NSMutableData()
            
            UIGraphicsBeginPDFContextToData(pdfData, pageRect, nil)
            UIGraphicsBeginPDFPage()
            
            // シンプルにAttributedStringを描画
            attributedString.draw(in: printableRect)
            
            UIGraphicsEndPDFContext()
            print("NSAttributedString PDF生成成功: \(pdfData.length) bytes")
            completion(pdfData as Data)
            
        } catch {
            print("NSAttributedString HTML解析エラー: \(error)")
            // 最終フォールバック：マークダウンを手動でスタイル付けして描画
            generateManualStyledPDF(from: html, completion: completion)
        }
    }
    
    /// 手動スタイル付きPDF生成
    private static func generateManualStyledPDF(from html: String, completion: @escaping (Data?) -> Void) {
        print("手動スタイル付きPDF生成を実行")
        
        // HTMLからマークダウン要素を抽出してスタイル付け
        let content = parseHTMLForStyling(html)
        
        let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842)
        let printableRect = CGRect(x: 30, y: 40, width: 535, height: 762)
        let pdfData = NSMutableData()
        
        UIGraphicsBeginPDFContextToData(pdfData, pageRect, nil)
        UIGraphicsBeginPDFPage()
        
        var yOffset: CGFloat = printableRect.minY
        
        for element in content {
            let textHeight = element.boundingRect(with: CGSize(width: printableRect.width, height: CGFloat.greatestFiniteMagnitude), options: .usesLineFragmentOrigin, context: nil).height
            
            element.draw(in: CGRect(x: printableRect.minX, y: yOffset, width: printableRect.width, height: textHeight))
            yOffset += textHeight + 8
            
            // ページ境界チェック
            if yOffset > printableRect.maxY - 50 {
                UIGraphicsBeginPDFPage()
                yOffset = printableRect.minY
            }
        }
        
        UIGraphicsEndPDFContext()
        completion(pdfData as Data)
    }
    
    /// HTMLからスタイル付きNSAttributedStringの配列を生成
    private static func parseHTMLForStyling(_ html: String) -> [NSAttributedString] {
        var elements: [NSAttributedString] = []
        
        // 行ごとに分割して処理
        let lines = html.components(separatedBy: .newlines)
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedLine.isEmpty { continue }
            
            // 段落スタイルで余白を調整
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineSpacing = 0 // 行間を極めて狭く
            paragraphStyle.paragraphSpacing = 1 // 段落間も極めて狭く
            paragraphStyle.paragraphSpacingBefore = 0 // 段落前の余白も極めて狭く
            
            var attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12),
                .foregroundColor: UIColor.black,
                .paragraphStyle: paragraphStyle
            ]
            
            var text = trimmedLine
            
            // HTMLタグを解析してスタイルを適用
            if text.contains("<h1>") {
                attributes[.font] = UIFont.boldSystemFont(ofSize: 20)
                text = text.replacingOccurrences(of: "</?h1>", with: "", options: .regularExpression)
            } else if text.contains("<h2>") {
                attributes[.font] = UIFont.boldSystemFont(ofSize: 18)
                text = text.replacingOccurrences(of: "</?h2>", with: "", options: .regularExpression)
            } else if text.contains("<h3>") {
                attributes[.font] = UIFont.boldSystemFont(ofSize: 16)
                text = text.replacingOccurrences(of: "</?h3>", with: "", options: .regularExpression)
            } else if text.contains("<strong>") {
                attributes[.font] = UIFont.boldSystemFont(ofSize: 12)
                text = text.replacingOccurrences(of: "</?strong>", with: "", options: .regularExpression)
            } else if text.contains("<em>") {
                attributes[.font] = UIFont.italicSystemFont(ofSize: 12)
                text = text.replacingOccurrences(of: "</?em>", with: "", options: .regularExpression)
            } else if text.contains("<del>") {
                attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                attributes[.strikethroughColor] = UIColor.systemGray2
                attributes[.foregroundColor] = UIColor.systemGray2
                text = text.replacingOccurrences(of: "</?del>", with: "", options: .regularExpression)
            } else if text.contains("<code>") {
                attributes[.font] = UIFont.monospacedSystemFont(ofSize: 11, weight: .regular)
                attributes[.backgroundColor] = UIColor.systemGray3 // より濃いグレー
                // インラインコードの余白を調整
                let codeParagraphStyle = NSMutableParagraphStyle()
                codeParagraphStyle.lineSpacing = 1
                codeParagraphStyle.paragraphSpacing = 3
                codeParagraphStyle.paragraphSpacingBefore = 1
                attributes[.paragraphStyle] = codeParagraphStyle
                text = text.replacingOccurrences(of: "</?code>", with: "", options: .regularExpression)
            } else if text.contains("<pre>") {
                attributes[.font] = UIFont.monospacedSystemFont(ofSize: 10, weight: .regular)
                attributes[.backgroundColor] = UIColor.systemGray3 // より濃いグレー
                // コードブロックの余白を調整
                let preParagraphStyle = NSMutableParagraphStyle()
                preParagraphStyle.lineSpacing = 1
                preParagraphStyle.paragraphSpacing = 4
                preParagraphStyle.paragraphSpacingBefore = 2
                attributes[.paragraphStyle] = preParagraphStyle
                text = text.replacingOccurrences(of: "</?pre>", with: "", options: .regularExpression)
                text = text.replacingOccurrences(of: "</?code>", with: "", options: .regularExpression)
            } else if text.contains("<li>") {
                // リスト項目の余白を調整
                let listParagraphStyle = NSMutableParagraphStyle()
                listParagraphStyle.lineSpacing = -2 // 行間をマイナスにして密着させる
                listParagraphStyle.paragraphSpacing = 0 // リスト項目間の余白を0に
                listParagraphStyle.paragraphSpacingBefore = 0
                attributes[.paragraphStyle] = listParagraphStyle
                text = "• " + text.replacingOccurrences(of: "</?li>", with: "", options: .regularExpression)
            } else if text.contains("<blockquote>") {
                attributes[.foregroundColor] = UIColor.systemGray3
                text = text.replacingOccurrences(of: "</?blockquote>", with: "", options: .regularExpression)
            }
            
            // 残りのHTMLタグを削除
            text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            text = text.replacingOccurrences(of: "&amp;", with: "&")
            text = text.replacingOccurrences(of: "&lt;", with: "<")
            text = text.replacingOccurrences(of: "&gt;", with: ">")
            text = text.replacingOccurrences(of: "<br>", with: "\n")
            
            if !text.isEmpty {
                let attributedString = NSAttributedString(string: text, attributes: attributes)
                elements.append(attributedString)
            }
        }
        
        return elements
    }
    
    /// メモからPDFを生成（SwiftUIのMarkdownTextビューと同じスタイリング適用）
    /// - Parameters:
    ///   - memo: メモオブジェクト
    ///   - enableChapterNumbering: 章番号自動追加の有効/無効
    ///   - completion: 完了時のコールバック（PDFData or nil）
    static func generatePDF(from memo: Memo, enableChapterNumbering: Bool = true, completion: @escaping (Data?) -> Void) {
        print("🔄 SwiftUI MarkdownText同等スタイルPDF生成開始")
        DispatchQueue.main.async {
            generatePDFFromSwiftUIMarkdown(content: memo.content, title: memo.displayTitle, enableChapterNumbering: enableChapterNumbering, completion: completion)
        }
    }
    
    
    /// SwiftUIのMarkdownTextビューと同じスタイリングでPDF生成
    private static func generatePDFFromSwiftUIMarkdown(content: String, title: String, enableChapterNumbering: Bool = true, completion: @escaping (Data?) -> Void) {
        print("📝 PDF生成開始 - コンテンツ長: \(content.count)")
        print("📝 コンテンツプレビュー: \(content.prefix(100))...")
        
        let markdownText = MarkdownText(content)
        let elements = markdownText.parseMarkdownForPDF(enableChapterNumbering: enableChapterNumbering)
        
        print("📝 解析された要素数: \(elements.count)")
        for (index, element) in elements.prefix(5).enumerated() {
            print("📝 要素 \(index): \(element.string.prefix(50))...")
        }
        
        // PDFコンテキストを作成
        let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842) // A4サイズ
        let printableRect = CGRect(x: 20, y: 25, width: 555, height: 792)
        let pdfData = NSMutableData()
        
        UIGraphicsBeginPDFContextToData(pdfData, pageRect, nil)
        UIGraphicsBeginPDFPage()
        
        var yOffset: CGFloat = printableRect.minY
        
        // タイトルは本文内のH1として表示されるため、重複を避けるためここでは描画しない
        
        // マークダウン要素を描画
        for (index, element) in elements.enumerated() {
            let elementHeight = element.boundingRect(with: CGSize(width: printableRect.width, height: CGFloat.greatestFiniteMagnitude), options: .usesLineFragmentOrigin, context: nil).height
            
            // ページ境界チェック
            if yOffset + elementHeight > printableRect.maxY - 20 {
                UIGraphicsBeginPDFPage()
                yOffset = printableRect.minY
                print("📝 新しいページを作成")
            }
            
            let drawRect = CGRect(x: printableRect.minX, y: yOffset, width: printableRect.width, height: elementHeight)
            element.draw(in: drawRect)
            
            // リンク注釈を追加
            addLinkAnnotationsForElement(element: element, drawRect: drawRect)
            
            yOffset += elementHeight + 1
            
            print("📝 要素 \(index) 描画完了: \(element.string.prefix(30))...")
        }
        
        UIGraphicsEndPDFContext()
        print("✅ SwiftUI風 PDF生成成功: \(pdfData.length) bytes")
        completion(pdfData as Data)
    }
    
    /// 要素ごとにリンク注釈を追加
    private static func addLinkAnnotationsForElement(element: NSAttributedString, drawRect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        
        element.enumerateAttribute(.link, in: NSRange(location: 0, length: element.length)) { value, range, _ in
            guard let url = value as? URL else { return }
            
            let linkText = element.attributedSubstring(from: range).string
            print("🔗 リンク処理開始: '\(linkText)' -> \(url.absoluteString)")
            
            // シンプルな方法でリンク矩形を計算
            let substring = element.attributedSubstring(from: range)
            let font = substring.attribute(.font, at: 0, effectiveRange: nil) as? UIFont ?? UIFont.systemFont(ofSize: 12)
            let textSize = linkText.size(withAttributes: [.font: font])
            
            // リンクテキストの位置を文字列内で計算
            let beforeText = element.attributedSubstring(from: NSRange(location: 0, length: range.location)).string
            let beforeSize = beforeText.size(withAttributes: [.font: font])
            
            // 注釈矩形を設定（より広めに設定してクリック確率を上げる）
            let annotationRect = CGRect(
                x: drawRect.minX + beforeSize.width,
                y: drawRect.minY,
                width: max(textSize.width, 50), // 最小幅を確保
                height: max(drawRect.height, 20) // 十分な高さを確保
            )
            
            print("   注釈矩形: \(annotationRect)")
            
            // メイン方法：Core Graphics の setURL
            context.setURL(url as CFURL, for: annotationRect)
            
            // 可視化のためデバッグ矩形を描画（テスト用）
            context.setStrokeColor(UIColor.red.withAlphaComponent(0.3).cgColor)
            context.setLineWidth(1.0)
            context.stroke(annotationRect)
            
            print("   ✅ リンク注釈設定完了")
        }
    }
}

// MARK: - PDFGenerationDelegate
/// WKWebViewのナビゲーション完了を監視するデリゲート
class PDFGenerationDelegate: NSObject, WKNavigationDelegate {
    private let completion: (Bool) -> Void
    
    init(completion: @escaping (Bool) -> Void) {
        self.completion = completion
        super.init()
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // HTMLの読み込みが完了
        print("HTML読み込み完了")
        completion(true)
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("HTML読み込み失敗: \(error)")
        completion(false)
    }
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        print("HTML読み込み失敗 (provisional): \(error)")
        completion(false)
    }
}
