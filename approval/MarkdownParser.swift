//
//  MarkdownParser.swift
//  approval
//
//  Минимальный парсер markdown под нужды InstallView. Чисто Foundation,
//  без SwiftUI — чтобы было удобно юнит-тестировать.
//
//  Поддерживаются: # / ## / ### заголовки, ```code blocks```,
//  - списки, пустые строки, обычные параграфы (с инлайн-разметкой,
//  которую AttributedString потом разрулит сам).
//

import Foundation

enum MarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case codeBlock(language: String?, content: String)
    case listItem(String)
    case blank
}

enum MarkdownParser {
    static func parse(_ text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        let lines = text.components(separatedBy: "\n")
        var i = 0

        while i < lines.count {
            let line = lines[i]

            // Code fence
            if line.hasPrefix("```") {
                let lang = line.dropFirst(3).trimmingCharacters(in: .whitespaces)
                var content: [String] = []
                i += 1
                while i < lines.count, !lines[i].hasPrefix("```") {
                    content.append(lines[i])
                    i += 1
                }
                blocks.append(.codeBlock(
                    language: lang.isEmpty ? nil : lang,
                    content: content.joined(separator: "\n")
                ))
                if i < lines.count { i += 1 } // skip closing ```
                continue
            }

            // Headings (порядок: H3 раньше H2 раньше H1, иначе # заматчит всё).
            if line.hasPrefix("### ") {
                blocks.append(.heading(level: 3, text: String(line.dropFirst(4))))
                i += 1
                continue
            }
            if line.hasPrefix("## ") {
                blocks.append(.heading(level: 2, text: String(line.dropFirst(3))))
                i += 1
                continue
            }
            if line.hasPrefix("# ") {
                blocks.append(.heading(level: 1, text: String(line.dropFirst(2))))
                i += 1
                continue
            }

            // List item
            if line.hasPrefix("- ") {
                blocks.append(.listItem(String(line.dropFirst(2))))
                i += 1
                continue
            }

            // Blank line
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                blocks.append(.blank)
                i += 1
                continue
            }

            // Paragraph: collect consecutive non-special lines.
            var para = [line]
            i += 1
            while i < lines.count {
                let next = lines[i]
                if next.hasPrefix("```") ||
                    next.hasPrefix("#") ||
                    next.hasPrefix("- ") ||
                    next.trimmingCharacters(in: .whitespaces).isEmpty {
                    break
                }
                para.append(next)
                i += 1
            }
            blocks.append(.paragraph(para.joined(separator: " ")))
        }

        return blocks
    }
}
