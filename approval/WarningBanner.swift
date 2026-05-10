//
//  WarningBanner.swift
//  approval
//
//  Унифицированная плашка-предупреждение с иконкой, заголовком и
//  опциональным описанием. Используется в pass-through режиме на
//  Статусе, в формах валидации, и т.п.
//

import SwiftUI

struct WarningBanner: View {
    enum Level {
        case warning
        case error

        var color: Color {
            switch self {
            case .warning: return .red
            case .error: return .red
            }
        }

        var defaultIcon: String {
            switch self {
            case .warning: return "exclamationmark.triangle.fill"
            case .error: return "xmark.octagon.fill"
            }
        }
    }

    let level: Level
    let title: String
    let message: String?
    let icon: String

    init(level: Level = .warning, title: String, message: String? = nil, icon: String? = nil) {
        self.level = level
        self.title = title
        self.message = message
        self.icon = icon ?? level.defaultIcon
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title)
                .foregroundStyle(level.color)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(level.color)
                if let message = message, !message.isEmpty {
                    Text(message)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

extension View {
    /// Подложка для WarningBanner в Form .grouped — красная рамка + светлый фон.
    func warningBackground(_ level: WarningBanner.Level = .warning) -> some View {
        self.listRowBackground(
            RoundedRectangle(cornerRadius: 10)
                .fill(level.color.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(level.color, lineWidth: 2)
                )
        )
    }
}
