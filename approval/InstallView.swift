//
//  InstallView.swift
//  approval
//

import SwiftUI
import AppKit

struct InstallView: View {
    @EnvironmentObject var server: ApprovalServer

    @State private var rawMarkdown: String = ""
    @State private var loadError: String = ""
    @State private var copyFeedback: String = ""

    private var resourceName: String {
        // Заглушка под будущую локализацию.
        // Когда добавим .lproj — переключай по Locale.current здесь.
        return "install_ru"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Spacer()
                    Button {
                        copyAll()
                    } label: {
                        Label(copyFeedback.isEmpty ? "Скопировать всё" : copyFeedback,
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
        .navigationTitle("Установка")
        .onAppear { load() }
        .onChange(of: server.port) { _, _ in load() }
    }

    private func load() {
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "md") else {
            loadError = "Ресурс \(resourceName).md не найден в bundle"
            return
        }
        do {
            let template = try String(contentsOf: url, encoding: .utf8)
            rawMarkdown = substitute(template)
            loadError = ""
        } catch {
            loadError = "Ошибка чтения: \(error.localizedDescription)"
        }
    }

    private func substitute(_ template: String) -> String {
        let appPath = Bundle.main.bundlePath
        let appBin = Bundle.main.executablePath ?? "\(appPath)/Contents/MacOS/approval"
        let port = "\(server.port)"
        let appSupport = (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.path ?? "~/Library/Application Support")
        let portFile = "\(appSupport)/approval/port"

        return template
            .replacingOccurrences(of: "{{APP_PATH}}", with: appPath)
            .replacingOccurrences(of: "{{APP_BIN}}", with: appBin)
            .replacingOccurrences(of: "{{PORT}}", with: port)
            .replacingOccurrences(of: "{{PORT_FILE}}", with: portFile)
    }

    private func copyAll() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(rawMarkdown, forType: .string)
        copyFeedback = "Скопировано ✓"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            copyFeedback = ""
        }
    }
}
