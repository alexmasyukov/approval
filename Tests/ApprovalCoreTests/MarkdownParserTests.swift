import XCTest
@testable import ApprovalCore

final class MarkdownParserTests: XCTestCase {
    func test_emptyString_givesSingleBlankBlock() {
        // "".components(separatedBy: "\n") даёт [""] — одну пустую строку,
        // парсер интерпретирует её как .blank. Считаем это контрактом.
        XCTAssertEqual(MarkdownParser.parse(""), [.blank])
    }

    func test_singleH1() {
        XCTAssertEqual(
            MarkdownParser.parse("# Hello"),
            [.heading(level: 1, text: "Hello")]
        )
    }

    func test_h1_h2_h3_distinguishedByPrefix() {
        let blocks = MarkdownParser.parse("""
        # Big
        ## Medium
        ### Small
        """)
        XCTAssertEqual(blocks, [
            .heading(level: 1, text: "Big"),
            .heading(level: 2, text: "Medium"),
            .heading(level: 3, text: "Small"),
        ])
    }

    func test_paragraphCollectsConsecutiveLines() {
        let blocks = MarkdownParser.parse("""
        Line one
        Line two

        Line three
        """)
        XCTAssertEqual(blocks, [
            .paragraph("Line one Line two"),
            .blank,
            .paragraph("Line three"),
        ])
    }

    func test_codeBlockExtractsContentAndLanguage() {
        let input = """
        Before
        ```swift
        let x = 1
        let y = 2
        ```
        After
        """
        let blocks = MarkdownParser.parse(input)
        XCTAssertEqual(blocks, [
            .paragraph("Before"),
            .codeBlock(language: "swift", content: "let x = 1\nlet y = 2"),
            .paragraph("After"),
        ])
    }

    func test_codeBlockWithoutLanguage() {
        let blocks = MarkdownParser.parse("""
        ```
        plain text
        ```
        """)
        XCTAssertEqual(blocks, [
            .codeBlock(language: nil, content: "plain text"),
        ])
    }

    func test_listItems() {
        let blocks = MarkdownParser.parse("""
        - alpha
        - beta
        - gamma
        """)
        XCTAssertEqual(blocks, [
            .listItem("alpha"),
            .listItem("beta"),
            .listItem("gamma"),
        ])
    }

    func test_mixedRealisticDocument() {
        let input = """
        # Heading

        First paragraph.

        ## Subsection

        - item one
        - item two

        ```bash
        echo hi
        ```
        """
        let blocks = MarkdownParser.parse(input)
        XCTAssertEqual(blocks, [
            .heading(level: 1, text: "Heading"),
            .blank,
            .paragraph("First paragraph."),
            .blank,
            .heading(level: 2, text: "Subsection"),
            .blank,
            .listItem("item one"),
            .listItem("item two"),
            .blank,
            .codeBlock(language: "bash", content: "echo hi"),
        ])
    }

    func test_headingPrefixOrder_h3BeforeH2BeforeH1() {
        // Если бы `# ` матчился раньше `### `, всё стало бы H1.
        // Этот тест ловит ошибку приоритета в parser'е.
        let blocks = MarkdownParser.parse("### Three")
        XCTAssertEqual(blocks, [.heading(level: 3, text: "Three")])
    }

    func test_unclosedCodeBlockTakesEverything() {
        let input = """
        ```
        line a
        line b
        """
        let blocks = MarkdownParser.parse(input)
        XCTAssertEqual(blocks, [
            .codeBlock(language: nil, content: "line a\nline b"),
        ])
    }
}
