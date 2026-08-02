# План работ: редизайн и три новые функции

> Навигационная модель — **горизонтальные вкладки** (решение дизайн-фазы,
> `design/ia.md`). Планировщик предлагал боковой список; при расхождении
> побеждает дизайн. Везде ниже `SettingsRootView` строит вкладки, а не
> `NavigationSplitView`.

## 0. Что мешает параллельной работе сейчас

- `build.sh` компилирует `Sources/Nadiktovka/*.swift` плоским глобом — подпапки не соберутся.
- `Settings.swift` — один общий `defaults.register(defaults:)`, куда полезли бы все слайсы.
- `AppDelegate.swift` — 484 строки: меню, оркестровка записи, последний текст, диагностика.
- `SettingsWindow.swift` — модель, все секции и окно в одном файле.

## 1. Подготовительный коммит (один, до ветвления)

Задача — чтобы после него ни один слайс не трогал `Settings.swift`, `AppDelegate.swift`,
`SettingsSections.swift` и `build.sh`.

### 1.1 build.sh — рекурсивный поиск исходников

```bash
SOURCES=()
while IFS= read -r file; do SOURCES+=("$file"); done \
    < <(find Sources/Nadiktovka -name '*.swift' | sort)
swiftc -swift-version 5 -O -target "$TARGET" -o "$BIN" "${SOURCES[@]}"
```

### 1.2 Раскладка по папкам (`git mv`, без правки кода)

```
Core/      AppDelegate  main  Settings  Keychain  Log  LaunchAtLogin  AppEvents*  AppPaths*
Audio/     AudioRecorder  Transcriber  TextInserter
Hotkey/    Hotkey  HotkeyMonitor  HotkeyRecorder
UI/        DesignSystem*  SettingsModel*  SettingsRootView*  SettingsWindowController*
           SettingsSections*  RecordingIndicator
UI/Sections/          SettingsSection_{General,Dictation,History,Usage,System}*
Features/StatusMenu/  StatusMenuBuilder*
Features/History/     HistoryStore*
Features/Usage/       UsageStore*
Features/Recording/   RecordingGate*  RecordingModeCard*
```

`*` — новые файлы, заводятся стабами. `SettingsWindow.swift` разбирается на
`SettingsModel` + `SettingsWindowController` + `SettingsRootView` и удаляется.

### 1.3 Settings.swift — типизированные хелперы вместо общего словаря

`defaults` становится internal, добавляются `flag/text/number/decimal/set/decoded/encode`.
Каждый слайс объявляет свои настройки в отдельном `Settings+<Слайс>.swift`.
Префиксы ключей: `ui.*` — A, `menu.*` — B, `history.*` — C, `usage.*` — D, `record.*` — E.

### 1.4 Core/AppPaths.swift

`supportDirectory` → `~/Library/Application Support/Надиктовка`, `supportFile(_:)`.

### 1.5 Core/AppEvents.swift — шина событий

```swift
struct TranscriptionRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let date: Date
    let text: String
    let audioDuration: TimeInterval
    let latency: TimeInterval
    let modelID: String
    let language: String
    let cleanupUsed: Bool
    var wordCount: Int { get }
    var characterCount: Int { get }
}

protocol TranscriptionObserver: AnyObject {
    func transcriptionDidFinish(_ record: TranscriptionRecord)
}

enum TranscriptionBus {
    static func register(_ observer: TranscriptionObserver)
    static func publish(_ record: TranscriptionRecord)   // всегда на главном потоке
}
```

Поля фиксируются здесь и не расширяются слайсами.

### 1.6 Features/Recording/RecordingGate.swift — шлюз режима записи

Реализует сегодняшнее удержание. Слайс E добавляет к нему `.toggle`.

```swift
enum HotkeyActivation: String, CaseIterable, Identifiable { case hold, toggle }

final class RecordingGate {
    enum Command { case begin, finish, abort }
    var onCommand: ((Command) -> Void)?
    private(set) var currentHint: String?
    func hotkeyPressed(); func hotkeyReleased(); func hotkeyCancelled()
    func escapePressed() -> Bool
    func recordingDidStop(); func reload(); func reset()
}
```

### 1.7 Features/StatusMenu/StatusMenuBuilder.swift

Текущий `AppDelegate.buildMenu()` переезжает дословно. Протокол фиксируется целиком
и полностью реализуется в подготовке — слайс B его не расширяет.

```swift
protocol StatusMenuActions: AnyObject {
    var menuStatusTitle: String { get }
    var isHotkeyActive: Bool { get }
    func menuOpenSettings(_ section: SettingsSection)
    func menuCopy(_ text: String)
    func menuInsertAgain(_ text: String)
    func menuShowDiagnostics()
    func menuRequestKeyboardAccess()
    func menuToggleSounds()
    func menuQuit()
}
```

### 1.8 Хранилища — API замораживается сразу

`HistoryStore` (limit 20, `items`, `copy`, `insertAgain`, `remove`, `clear`) и
`UsageStore` (`Summary`, `DayBucket`, `today`, `allTime`, `last30Days`, `summary(since:)`,
`resetAll`) заводятся стабами: слайс B верстает меню поверх них, не дожидаясь C и D.

### 1.9 UI/SettingsSections.swift — заморожен после подготовки

Все пять разделов объявляются сразу: `general`, `dictation`, `history`, `usage`, `system`
(порядок из `design/ia.md`: «Запись» и «Текст» первыми как самые частые, ключ и доступы — в конец).

### 1.10 UI/DesignSystem.swift — сигнатуры заморожены, реализация наивная

`Palette`, `SectionScaffold`, `GlassCard`, `SettingRow`, `SwitchToggle`, `Hint`, `StatTile`.
Единственный писатель после подготовки — слайс A, остальные только вызывают.

### 1.11 AppDelegate — правки только здесь, дальше заморожен

1. Хуки хоткея уходят в `RecordingGate`.
2. После успешной расшифровки — `TranscriptionBus.publish(...)`.
3. При старте — регистрация `HistoryStore` и `UsageStore` в шине.
4. `buildMenu()` → `statusMenu.build()`, реализация `StatusMenuActions`.
5. `RecordingIndicator.setHint(_:)` для подсказки режима.

### 1.12 Критерий готовности

`./build.sh` собирается, приложение работает ровно как раньше, окно настроек
открывается с пятью вкладками, две из которых — заглушки.

## 2. Слайсы

| Слайс | Цель | Создаёт | Правит |
|---|---|---|---|
| **A** Оформление и каркас | Стекло, вкладки, переключатели, обе темы, разделы «Основное», «Диктовка», «Система» | `Settings+Appearance` | `DesignSystem`, `SettingsRootView`, `SettingsWindowController`, три секции, `RecordingIndicator` (читаемость в светлой теме) |
| **B** Меню статус-бара | Статус, последние расшифровки, быстрые действия, вход по разделам, служебное в подменю | `StatusMenuSections`, `Settings+Menu` | `StatusMenuBuilder` |
| **C** История | 20 записей на диске, список, копирование, повторная вставка | `HistoryArchive`, `Settings+History` | `HistoryStore`, секция «История» |
| **D** Расходы | Минуты, слова, оценка стоимости, плитки и график за 30 дней | `Pricing`, `UsageArchive`, `UsageChart`, `Settings+Usage` | `UsageStore`, секция «Расходы» |
| **E** Нажал-нажал | Второй режим активации плюс авто-стоп | `Settings+Recording` | `RecordingGate`, `RecordingModeCard` |

Границы: слайс правит только свои файлы. `DesignSystem` пишет исключительно A.
`AppDelegate`, `Settings`, `SettingsSections`, `build.sh`, `README` после подготовки не трогает никто.

## 3. Пересечения

| Файл | Пишет | Читают | Решение |
|---|---|---|---|
| `DesignSystem.swift` | A | C, D, E | Сигнатуры заморожены в подготовке |
| `_Dictation.swift` | A | — | Фиксированный вызов `RecordingModeCard()`, содержимое пишет E у себя |
| `HistoryStore` / `UsageStore` | C / D | B | API заморожен, B работает и на пустых стабах |
| `RecordingIndicator` | A | E через `gate.currentHint` | `setHint` заведён в подготовке |

## 4. Порядок сборки

Подготовка → **A** (от неё зависят визуально все) → **E** → **C** → **D** → **B** (последним,
чтобы пункты меню сразу наполнились реальными данными) → сшивка: README, версия `1.1`,
`./build.sh install`, ручной прогон обоих режимов записи в двух темах.

## 5. Риски

| Риск | Что делаем |
|---|---|
| Пять worktree одновременно ставят приложение и сбрасывают разрешения | Агентам разрешён только `./build.sh` без `install`; установка — в самом конце, вручную |
| `import Charts` может не слинковаться голым `swiftc` без Xcode | Слайс D первым делом проверяет минимальный импорт; при провале — столбики через `Canvas` |
| Стоимость только оценочная: при `response_format: text` API не возвращает usage | Подписать «оценка», тарифы держать в одной таблице `Pricing.swift` |
| Расшифровки на диске — приватность | Переключатель «Хранить историю» и «Очистить всё»; файл в Application Support |
| Залипшая запись в режиме toggle при потере фокуса | Авто-стоп по `record.maxToggleDuration`, `recordingDidStop()` при любой остановке |
