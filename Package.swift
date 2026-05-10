// swift-tools-version: 5.10
import PackageDescription

// SPM-пакет рядом с .xcodeproj. Используется ТОЛЬКО для запуска
// юнит-тестов через `swift test`. Production-сборка идёт через Xcode.
//
// ApprovalCore поднимает только Foundation-only типы (Models, Constants,
// Stores, MarkdownParser, UnixSocket). Всё что зависит от SwiftUI/AppKit/
// UserNotifications живёт в Xcode-таргете и сюда не включается.

let package = Package(
    name: "approval-tests",
    platforms: [.macOS(.v13)],
    products: [],
    targets: [
        .target(
            name: "ApprovalCore",
            path: "approval",
            exclude: [
                "approvalApp.swift",
                "main.swift",
                "ContentView.swift",
                "AppSection.swift",
                "StatusView.swift",
                "LogView.swift",
                "RulesView.swift",
                "InstallView.swift",
                "SettingsView.swift",
                "CommandDetailView.swift",
                "MarkdownView.swift",
                "ApprovalCoordinator.swift",
                "ApprovalServer.swift",
                "HookHandler.swift",
                "Resources",
                "Assets.xcassets",
            ],
            sources: [
                "Models.swift",
                "Constants.swift",
                "RulesStore.swift",
                "LogStore.swift",
                "PendingStore.swift",
                "MarkdownParser.swift",
                "UnixSocket.swift",
            ]
        ),
        .testTarget(
            name: "ApprovalCoreTests",
            dependencies: ["ApprovalCore"],
            path: "Tests/ApprovalCoreTests"
        ),
    ]
)
