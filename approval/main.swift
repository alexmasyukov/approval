//
//  main.swift
//  approval
//
//  Точка входа: если запущены с `--hook`, отдаём управление HookHandler
//  и сразу выходим (никакого GUI). Иначе — обычный запуск SwiftUI App.
//

import Foundation
import SwiftUI

if CommandLine.arguments.contains("--hook") {
    HookHandler.run()
} else {
    approvalApp.main()
}
