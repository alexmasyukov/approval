# Рефакторинг

Документ — план чистки и реструктуризации `approval` после быстрого MVP. Группировано по приоритету. Каждый пункт: **что не так / почему / что сделать**.

Все пункты — **без изменения внешнего поведения** (фичи в отдельной секции «Не рефакторинг»).

---

## P0 — критично, мешает дальше работать

### 1. ApprovalServer: смесь @MainActor и nonisolated через статические функции

**Что:** `acceptLoop` и `handleClient` вынесены в `static nonisolated`, потому что выполняются на background thread, но им нужен доступ к main-actor стейту (`RulesStore`, `PendingStore`, `ApprovalCoordinator`, `LogStore`). Сейчас это решено через `Task { @MainActor in ... }` внутри static-функции. Жёстко связано через `Self.shared` и сложно тестировать.

**Почему плохо:** singleton sprawl, скрытые зависимости, сложно подменить storage в тестах.

**Что сделать:**
- Вынести зависимости (RulesStore, PendingStore, LogStore, ApprovalCoordinator) в инициализатор как протоколы.
- `acceptLoop` сделать `private func` на инстансе, передавать слабую ссылку в Thread.
- Заменить static методы на инстанс-методы.
- Подмена в тестах: `ApprovalServer(rules: MockRules(), pending: MockPending(), ...)`.

### 2. Singletons everywhere

**Что:** `ApprovalServer.shared`, `RulesStore.shared`, `LogStore.shared`, `PendingStore.shared`, `ApprovalCoordinator.shared`. Все читают `.shared` напрямую.

**Почему плохо:** невозможно изолированно тестировать, неявные зависимости, цикл жизни не контролируется.

**Что сделать:**
- Создать `AppContainer` (DI-контейнер) с одним инстансом каждого; собрать его в `AppDelegate.applicationDidFinishLaunching`.
- Передавать через `EnvironmentObject` (это уже делается для UI) и инжектить в нон-UI типы через инициализатор.
- Удалить `static let shared` отовсюду.

### 3. Магические строки

**Что:** ID нотификационной категории `"COMMAND_APPROVAL"`, ключи UserDefaults `"verboseNotifications"`, `"serverPort"` (последний остался от старого API но в коде уже не используется — стоит удалить), action-id `"APPROVE"`, имена файлов `"rules.json"`, `"log.json"`, `"port"`, `"approval.sock"`.

**Почему плохо:** опечатка в одном месте — silent break. Сложно реindex.

**Что сделать:**
- Завести `enum Constants` (или несколько по доменам: `NotificationConstants`, `StorageConstants`, `IPCConstants`).
- Заменить все литералы на enum.

---

## P1 — важно, лучше до релиза

### 4. ContentView.swift распух

**Что:** в одном файле `AppSection`, `ContentView` и `StatusView` — последний на ~150 строк с своей собственной логикой `fireLocal`.

**Что сделать:**
- Вынести `StatusView` в `StatusView.swift`.
- `AppSection` перенести в отдельный `AppSection.swift` или `Models.swift`.
- ContentView оставить только как корень `NavigationSplitView`.

### 5. Локализация — частично

**Что:** `install_ru.md` лежит как ресурс с подготовкой под локализацию (`InstallView.resourceName` имеет TODO). Но все остальные строки в коде — захардкожены русские (заголовки секций, кнопки, labels, плейсхолдеры).

**Что сделать:**
- Завести `Localizable.xcstrings` (новый формат строковых каталогов Xcode 15+).
- Заменить все `Text("Статус")` на `Text("status.title")` и т.п. (или просто оставить русский ключ — SwiftUI поддерживает любой LocalizedStringKey).
- Добавить `en.lproj` и `ru.lproj` для `install_*.md`.
- Свитч локали в `InstallView.resourceName` через `Locale.current.language.languageCode`.

### 6. Error handling — `try?` везде

**Что:** `try? Data(contentsOf:)`, `try? JSONDecoder().decode(...)`, `try? regex.match(...)` — ошибки молча проглатываются. RulesStore при corrupt JSON просто упадёт обратно на дефолт, не сказав об этом.

**Что сделать:**
- Где можно молча игнорировать (read-only стартап) — оставить `try?`, но логировать ошибку (хотя бы print).
- Где важно (write rules.json, write log.json) — пробрасывать ошибку, показывать пользователю в UI.
- `RulesStore.evaluate` — если regex невалидный (хотя при добавлении мы валидируем, но JSON могут поправить руками) — логировать и пропускать правило, не падать.

### 7. LogStore синхронные I/O на main thread

**Что:** `LogStore.save()` пишет JSON через `try? data.write(to:)` синхронно. Каждый `append` или `updateDecision` блокирует main thread на запись.

**Почему плохо:** При большом логе (десятки KB) это уже заметные миллисекунды на хоп. Если диск медленный — UI freeze.

**Что сделать:**
- Вынести `save()` в `Task.detached(priority: .utility)` или на dedicated DispatchQueue.
- Или: писать только при выходе и периодически (debounced на 1с).

### 8. PendingStore + onResolve closure → утечка ресурсов

**Что:** В `PendingStore` хранится `onResolve: (Bool) -> Void`. Если запрос «застрял» (юзер не реагирует), closure живёт до перезапуска приложения. В closure захватывается `fd` (файловый дескриптор сокета) — он тоже не закрывается, пока closure не вызовут.

**Почему плохо:** утечка fd, заклинивание hook-процессов на read() (правда, у них есть SO_RCVTIMEO 600s — спасает).

**Что сделать:**
- Добавить таймаут на pending request: через 10 минут авто-резолв с denied + удаление из store.
- `Timer.scheduledTimer` или `DispatchQueue.main.asyncAfter` на каждую запись.

---

## P2 — приятно иметь, но не блокирует

### 9. ApprovalCoordinator: смешивает роли

**Что:** одновременно UNUserNotificationCenterDelegate, NSWindowDelegate, держит UI-state (`@Published var lastResult/lastError/authStatus`), управляет окнами `[String: NSWindow]`, имеет `setup()`, `requestApproval`, `resolve`, `openDetailWindow`. Слишком много.

**Что сделать:** разделить:
- `NotificationCenterClient` — оборачивает `UNUserNotificationCenter` (auth status, send, delegate).
- `WindowManager` — track NSWindow per request id.
- `ApprovalCoordinator` — глагол «координирует»: получает запрос, дёргает first two.

### 10. MarkdownView парсер примитивный

**Что:** Парсит `# / ## / ### / - / ```` ``` ```/ парагрфы. Не поддерживает: `>` цитаты, нумерованные списки, ссылки в блочном тексте, изображения, таблицы.

**Что сделать:** для нашего MD-контента (instruction page) этого достаточно. Если планируется куда-то ещё показывать MD — заменить на `swift-markdown` (Apple's library) + кастомный рендерер. Сейчас не приоритет.

### 11. Hardcoded test buttons на Status

**Что:** «Тест: DROP TABLE users», «Тест: rm -rf /tmp/foo», «Тест: SELECT» — для отладки, остаются у пользователя.

**Что сделать:**
- Спрятать за DEBUG-флагом: `#if DEBUG ... #endif`.
- Или перенести в отдельную «Отладка»-страницу, видимую только при включённом developer mode в настройках.

### 12. Унификация UI «карточек»

**Что:** В `Form .grouped` секции отображаются нативно. Но в `AddRuleSheet` ошибка показывается через `Color.red.opacity(0.1)` cornerRadius. В баннере pass-through — кастомный border. Стиль ошибочных/предупреждающих плашек разный.

**Что сделать:** общий `WarningBanner(level: .warning | .error)` view, использовать в трёх местах (add-rule sheet, pass-through banner, validation errors).

---

## P3 — long term

### 13. Тестов нет

**Что:** Полное отсутствие тестов. UI build падает только при синтаксической ошибке.

**Что сделать:**
- Юнит-тесты:
  - `RulesStore.evaluate` — таблица «команда → правило» (positive + negative cases).
  - `MarkdownParser.parse` — каждый тип блока отдельно.
  - `LogStore` — append/update/clear, ring-buffer на 100.
- Интеграционный тест:
  - Запустить ApprovalServer, законнектиться через Unix socket, послать JSON, проверить ответ. Мокнуть RulesStore и PendingStore.
- Snapshot-тесты SwiftUI views — опционально, через `swift-snapshot-testing`.

### 14. Concurrency cleanup

**Что:** Mix of `@MainActor`, `nonisolated`, `DispatchQueue.main.async`, `Task { @MainActor }`, `Thread`. Зоопарк.

**Что сделать:** придерживаться async/await + `@MainActor` для UI, `actor` для thread-safe storage. Заменить `DispatchQueue.main.async { ... }` на `Task { @MainActor in ... }` или прямую изоляцию. `Thread` для accept-loop оправдан (блокирующий syscall), но обернуть в `withTaskCancellationHandler` для async-friendly стопа.

### 15. Отсутствие проверки целостности при старте

**Что:** Сервер стартует молча. Если бинарник запустили без `--hook`, но старая копия `.app` ещё прицеплена через Launch Services к bundle ID — конфликт. Если сокет существует но недоступен — сервер падает молча.

**Что сделать:** при `start()` проверять:
- Не висит ли уже процесс с тем же bundle ID и сокетом (через `lsof` или попытку `connect()` к существующему сокету).
- Если висит — показать алерт «Уже запущена другая копия approval».

---

## Не-рефакторинг (новые фичи в отдельный план)

Это **не** часть рефакторинга, но в TODO:

- [ ] Кнопка «Install Hook» (вариант A из обсуждения) — UI копирует hook-команду в `~/.claude/settings.json` без ручного редактирования.
- [ ] Code signing + notarization для дистрибуции.
- [ ] DMG-сборка через `create-dmg`.
- [ ] GitHub Releases с подписанным DMG.
- [ ] Auto-update через [Sparkle](https://sparkle-project.org).
- [ ] Menu bar item — приложение всегда работает в фоне без иконки в Dock (LSUIElement).
- [ ] Auto-launch on login через [Launch at Login](https://github.com/sindresorhus/LaunchAtLogin-Modern).
- [ ] Локализация EN (после localizable.xcstrings из P1).
- [ ] About / Help / версия в About-окне.
- [ ] Cmd+, открывает Settings (Scene `Settings { ... }`).
- [ ] App icon (сейчас дефолтная Xcode-иконка).

---

## Метрики для приоритизации

- **P0 / P1** должны быть сделаны **до публичного релиза** v1.0.
- **P2** — желательно к v1.0, но не критично.
- **P3** — после релиза, в v1.1+.

Каждый пункт — самостоятельный PR.
