//
//  InstallView.swift
//  approval
//

import SwiftUI
import AppKit

struct InstallView: View {
    @EnvironmentObject var server: ApprovalServer
    @EnvironmentObject var l10n: L10n

    @State private var rawMarkdown: String = ""
    @State private var loadError: String = ""
    @State private var copyFeedback: String = ""

    private var resourceName: String {
        switch l10n.language {
        case .en: return "install_en"
        case .ru: return "install_ru"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Spacer()
                    Button {
                        copyAll()
                    } label: {
                        Label(copyFeedback.isEmpty ? l10n.tr("common.copy_all") : copyFeedback,
                              systemImage: "doc.on.doc")
                    }
                    .controlSize(.regular)
                    .disabled(rawMarkdown.isEmpty)
                }

                if !loadError.isEmpty {
                    Text(loadError)
                        .foregroundStyle(.red)
                } else {
                    MarkdownView(markdown: rawMarkdown)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(l10n.tr("sidebar.install"))
        .onAppear { load() }
        .onChange(of: l10n.language) { _, _ in load() }
    }

    private func load() {
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "md") else {
            loadError = "Resource \(resourceName).md not found in bundle"
            return
        }
        do {
            let template = try String(contentsOf: url, encoding: .utf8)
            rawMarkdown = substitute(template)
            loadError = ""
        } catch {
            loadError = "Read error: \(error.localizedDescription)"
        }
    }

    private func substitute(_ template: String) -> String {
        let appPath = Bundle.main.bundlePath
        let appBin = Bundle.main.executablePath ?? "\(appPath)/Contents/MacOS/approval"

        return template
            .replacingOccurrences(of: "{{APP_PATH}}", with: appPath)
            .replacingOccurrences(of: "{{APP_BIN}}", with: appBin)
    }

    private func copyAll() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(rawMarkdown, forType: .string)
        copyFeedback = l10n.tr("common.copied")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            copyFeedback = ""
        }
    }
}
