//
//  MarkdownView.swift
//  approval
//
//  Минимальный SwiftUI-рендерер markdown под наши нужды:
//  заголовки H1/H2/H3, code blocks с per-block копированием,
//  списки с bullet, параграфы с инлайн-форматированием через
//  AttributedString.
//

import SwiftUI
import AppKit

struct MarkdownView: View {
    let markdown: String

    var body: some View {
        let blocks = MarkdownParser.parse(markdown)
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                renderBlock(block)
            }
        }
    }

    @ViewBuilder
    private func renderBlock(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(text)
                .font(headingFont(level))
                .bold()
                .padding(.top, level == 1 ? 4 : 8)
                .padding(.bottom, 2)
        case .paragraph(let text):
            inlineText(text)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .codeBlock(let language, let content):
            CodeBlockView(content: content, language: language)
        case .listItem(let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•").foregroundStyle(.secondary)
                inlineText(text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, 4)
        case .blank:
            Spacer().frame(height: 4)
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .largeTitle
        case 2: return .title2
        case 3: return .title3
        default: return .body
        }
    }

    @ViewBuilder
    private func inlineText(_ text: String) -> some View {
        let opts = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        if let attr = try? AttributedString(markdown: text, options: opts) {
            Text(attr).textSelection(.enabled)
        } else {
            Text(text).textSelection(.enabled)
        }
    }
}

// MARK: - Parser

enum MarkdownBlock {
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

            // Headings
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

// MARK: - Code block

struct CodeBlockView: View {
    let content: String
    let language: String?

    @State private var copied: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                if let lang = language, !lang.isEmpty {
                    Text(lang)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    copy()
                } label: {
                    Label(copied ? "Скопировано ✓" : "Скопировать",
                          systemImage: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            Text(content)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
        .background(Color(NSColor.textBackgroundColor).opacity(0.6))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
        .cornerRadius(8)
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
    }
}
