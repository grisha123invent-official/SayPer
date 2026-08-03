import Foundation

/// Помощник по приложению: спрашиваешь словами — отвечает про SayPer.
///
/// Работает на том же ключе OpenAI, что и расшифровка: своего сервера
/// у приложения нет и заводить его ради справки незачем. Значит и деньги
/// за ответы платит владелец ключа — об этом сказано прямо в разделе.
///
/// Знания о приложении зашиты в системную подсказку ниже, а не берутся
/// из головы модели: без этого она отвечает правдоподобно, но неверно —
/// придумывает пункты меню, которых нет.
@MainActor
final class HelpChat: ObservableObject {
    struct Message: Identifiable, Equatable {
        enum Role { case user, assistant }
        let id = UUID()
        let role: Role
        var text: String
        /// Идентификаторы предложенных действий из `HelpAction.catalog`.
        var actions: [String] = []
    }

    @Published private(set) var messages: [Message] = []
    @Published private(set) var isThinking = false
    @Published private(set) var failure: String?

    /// Сколько вопросов помещается в один разговор.
    ///
    /// Дальше помощник начинает путаться в собственных ответах: он видит
    /// всю переписку целиком, и чем она длиннее, тем охотнее цепляется
    /// за сказанное десять реплик назад вместо последнего вопроса.
    /// Честнее оборвать и начать заново, чем медленно врать.
    static let maxQuestions = 10

    var asked: Int { messages.count { $0.role == .user } }
    var remaining: Int { max(0, Self.maxQuestions - asked) }
    var isFull: Bool { remaining == 0 }

    var hasKey: Bool { Settings.shared.apiKey != nil }

    /// Заполнить переписку заранее. Нужно стенду проверки интерфейса:
    /// иначе вид ленты не посмотреть, не потратив чужой ключ на запросы.
    func seed(_ prepared: [Message]) {
        messages = prepared
    }

    func reset() {
        messages = []
        failure = nil
    }

    func ask(_ question: String) {
        let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isThinking, !isFull else { return }

        messages.append(Message(role: .user, text: text))
        failure = nil
        isThinking = true

        Task { @MainActor in
            defer { isThinking = false }
            do {
                let answer = try await send()
                let parsed = Self.parse(answer)
                messages.append(Message(role: .assistant,
                                        text: parsed.text, actions: parsed.actions))
            } catch {
                failure = error.localizedDescription
            }
        }
    }

    /// Отделяет предложенные действия от текста ответа.
    ///
    /// Модель дописывает в конец строки вида `ДЕЙСТВИЕ: mic.builtin`. Отдельным
    /// полем в ответе это сделать нельзя без tool calling, а он на разговорной
    /// переписке лишний: строка проще, а незнакомый идентификатор всё равно
    /// отсеется здесь и до кнопки не дойдёт.
    static func parse(_ answer: String) -> (text: String, actions: [String]) {
        var text: [String] = []
        var actions: [String] = []

        for line in answer.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.uppercased().hasPrefix("ДЕЙСТВИЕ:") else {
                text.append(line)
                continue
            }
            let id = trimmed.dropFirst("ДЕЙСТВИЕ:".count)
                .trimmingCharacters(in: .whitespaces)
            // Выдуманный идентификатор — не кнопка. Из закрытого списка
            // берётся и подпись, и объяснение, и само действие.
            guard let action = HelpAction.named(id), action.isRelevant(),
                  !actions.contains(id), actions.count < 2 else { continue }
            actions.append(id)
        }

        return (text.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines),
                actions)
    }

    // MARK: - Запрос

    private func send() async throws -> String {
        guard let key = Settings.shared.apiKey else {
            throw HelpError.noKey
        }

        var payload: [[String: String]] = [
            ["role": "system", "content": Self.knowledge],
            ["role": "system", "content": Self.currentState()]
        ]
        // Переписка уходит целиком: разговор и так оборван на десятом вопросе,
        // а без предыдущих реплик «а если наоборот?» не с чем соотнести.
        payload += messages.map {
            ["role": $0.role == .user ? "user" : "assistant", "content": $0.text]
        }

        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "temperature": 0.2,
            "messages": payload
        ]

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let session = URLSession(configuration: .default)
        defer { session.finishTasksAndInvalidate() }

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            var message = "код \(http.statusCode)"
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = json["error"] as? [String: Any],
               let text = error["message"] as? String {
                message = text
            }
            throw HelpError.server(message)
        }

        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any],
            let content = message["content"] as? String
        else { throw HelpError.server("ответ не разобрался") }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    enum HelpError: LocalizedError {
        case noKey
        case server(String)

        var errorDescription: String? {
            switch self {
            case .noKey:
                return "Сначала нужен ключ OpenAI — он задаётся в разделе «Ключ и расходы»."
            case .server(let message):
                return "OpenAI не ответил: \(message)"
            }
        }
    }

    /// Что настроено у этого человека прямо сейчас.
    ///
    /// Собирается заново перед каждым вопросом и уходит вторым системным
    /// сообщением. Без этого помощник знает, *где* меняется сочетание,
    /// но не знает, *какое* оно у тебя, — а спрашивают ровно об этом.
    /// Снимок читает настройки, но не меняет их: помощник отвечает словами,
    /// переключатели остаются за человеком.
    ///
    /// Личного здесь нет намеренно. Расшифровки не отдаются вовсе, словарь —
    /// только признаком «задан», ключ — только признаком «есть». Всё это
    /// ушло бы в OpenAI вместе с вопросом, а вопрос был про настройки.
    static func currentState() -> String {
        let settings = Settings.shared
        var lines: [String] = []

        lines.append("Сочетание: \(settings.hotkey.displayString), "
                     + "режим «\(settings.hotkeyActivation.title)»"
                     + (settings.hotkeyActivation == .toggle
                        ? ", авто-стоп через \(settings.autoStopLimit.title)" : ""))

        switch settings.micRouting {
        case .panel:
            lines.append("Выбор микрофона: в панели, сейчас выбран "
                         + micName(settings.microphone))
        case .perHotkey:
            let routes = settings.hotkeyRoutes.map {
                "\($0.binding.displayString) → \(micName($0.device))"
            }
            lines.append("Выбор микрофона: на клавише — " + routes.joined(separator: "; "))
        }

        lines.append("Модель: \(settings.model.rawValue)")
        lines.append("Язык речи: "
                     + (settings.language.isEmpty ? "определяется автоматически"
                                                  : settings.language))
        lines.append("Способ вставки: \(settings.insertMode.title)")

        let duck = settings.duckMode == .dim
            ? "убавить до \(Int(settings.duckLevel * 100))%"
            : settings.duckMode.title.lowercased()
        lines.append("Звук компьютера на время записи: \(duck)")

        lines.append("Причёсывать текст: \(settings.cleanup ? "включено" : "выключено")")
        lines.append("Индикатор записи: \(settings.showIndicator ? "показывается" : "скрыт")")
        lines.append("Звуковые сигналы: \(settings.playSounds ? "включены" : "выключены")")
        lines.append("Словарь: "
                     + (settings.vocabulary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? "пуст" : "задан"))
        lines.append("История: "
                     + (settings.historyEnabled
                        ? "хранится, последние \(settings.historyLimit)" : "выключена"))
        lines.append("Автозапуск при входе: "
                     + (LaunchAtLogin.isEnabled ? "включён" : "выключен"))
        lines.append("Ключ OpenAI: \(settings.apiKey == nil ? "НЕ задан" : "задан")")
        lines.append("Универсальный доступ: "
                     + (HotkeyMonitor.isTrusted ? "выдан" : "НЕ выдан"))
        lines.append("Мониторинг ввода: \(HotkeyMonitor.inputMonitoringStatus)")
        lines.append("Подробный журнал: \(settings.verboseLog ? "включён" : "выключен")")
        lines.append("Версия: \(AppInfo.versionLine)")

        return """
        ТЕКУЩИЕ НАСТРОЙКИ ЭТОГО ЧЕЛОВЕКА. Отвечая «какая у меня клавиша»,
        «что у меня выбрано», «почему у меня так» — бери значения отсюда,
        а не из общего описания. Менять настройки ты не умеешь: говори,
        куда пойти и что нажать.

        \(lines.joined(separator: "\n"))
        """
    }

    /// Название микрофона так, как его видит человек в списке.
    private static func micName(_ choice: MicrophoneChoice) -> String {
        switch choice {
        case .auto:
            return "автоматически"
        case .builtIn:
            return AudioDevices.builtInInput()?.name ?? "встроенный микрофон"
        case .device(let uid):
            // Устройство могло отключиться — тогда честнее сказать об этом,
            // чем назвать UID, который человеку ничего не говорит.
            return AudioDevices.inputs().first { $0.uid == uid }?.name
                ?? "выбранное устройство сейчас не подключено"
        }
    }

    /// Что помощник знает о приложении.
    ///
    /// Пишется вручную и обновляется вместе с функциями. Модель без этого
    /// уверенно выдумывает: у неё в голове тысяча похожих приложений,
    /// и она честно расскажет про пункт меню, которого у нас нет.
    private static let knowledge = """
    Ты — встроенный помощник приложения SayPer для macOS. Отвечай коротко,
    по-русски, обычными словами, 2-5 предложений. Веди человека по шагам:
    какой раздел открыть, что там нажать. Если ответа нет в справке ниже —
    прямо скажи «этого я не знаю» и предложи написать разработчику
    в телеграм @\(About.telegram). Ничего не выдумывай: пунктов меню
    и настроек, кроме описанных здесь, в приложении нет.

    КАК ВЕСТИ РАЗГОВОР. Это переписка, а не набор отдельных ответов.
    Помни, о чём шла речь выше: «а если наоборот?», «а это где?»,
    «а второй способ?» относятся к твоей прошлой реплике — отвечай по ней,
    не переспрашивай заново. Если вопрос можно понять двояко, не угадывай:
    задай один короткий уточняющий вопрос. Не повторяй уже сказанное,
    добавляй новое. Советовать, что поменять, можно и нужно — но переключать
    сам ты ничего не умеешь, поэтому говори «зайди туда-то и включи то-то»
    и никогда не пиши, будто уже что-то сделал.

    КНОПКИ. Когда ответ сводится к «поменяй такую-то настройку», ты можешь
    предложить это кнопкой: допиши в самый конец ответа отдельную строку
    ДЕЙСТВИЕ: идентификатор
    Не больше двух таких строк, и только из списка ниже — выдуманный
    идентификатор просто пропадёт. Кнопку человек нажмёт сам, подпись
    и объяснение к ней приложение подставит своё, поэтому в тексте
    не пересказывай кнопку и не пиши «я переключил» — ты не переключал.
    Сначала объясни словами, потом строку. Если человек просто спрашивает,
    как устроено, кнопка не нужна.

    Список идентификаторов:
    \(HelpAction.promptList)

    Настройки этого человека приходят отдельным сообщением ниже — если
    спрашивают «а какая у меня клавиша», «что у меня выбрано», отвечай
    оттуда конкретным значением, а не общими словами. Сам ты ничего
    переключить не можешь: объясняй, куда зайти и что нажать.

    ЧТО ЭТО. SayPer — диктовка голосом. Зажал сочетание клавиш, сказал,
    отпустил — текст появился там, где стоит курсор. Живёт в строке меню,
    своего окна нет, в Dock не висит. Расшифровка идёт через OpenAI по ключу
    самого пользователя, порядка $0.006 за минуту речи.

    ПАНЕЛЬ. Клик по значку в строке меню: последние расшифровки (клик копирует),
    выбор микрофона, кнопки «Настройки» и «Выйти».

    НАСТРОЙКИ — пять разделов, переключаются ⌘1…⌘5:
    Диктовка, История, Кастомизация, Ключ и расходы, О программе.

    ДИКТОВКА (⌘1). Наверху «Активация»:
    - Сочетание: кликнуть по полю и зажать нужные клавиши. Левые и правые
      различаются: правый ⌥ и левый ⌥ — разные сочетания.
    - Режим: «Удержание» — держишь клавишу, пока говоришь. «Нажал-нажал» —
      первое нажатие начинает, второе заканчивает; забытая запись сама
      остановится через пять минут и положит текст в буфер.
    - Esc прерывает и запись, и ожидание ответа.
    - Выбор микрофона — два режима. «В панели»: одно сочетание, микрофон
      выбирается заранее в панели строки меню. «На клавише»: у каждого
      микрофона своё сочетание, и оно же выбирает устройство — например
      ⌃Space пишет встроенным, а ⌃⌥Space гарнитурой. Сочетания задаются
      в таблице тут же, под переключателем.

    Ниже «Запись и текст»:
    - Показывать индикатор — пилюля на экране во время записи.
    - Модель: whisper-1 (классический), gpt-4o-transcribe (точнее),
      gpt-4o-mini-transcribe (дешевле).
    - Язык речи: конкретный язык или «определять автоматически». Указанный
      язык распознаётся точнее.
    - Способ вставки: «Вставить» через ⌘V с восстановлением буфера (обычный
      случай), «Напечатать посимвольно» (для окон, где ⌘V не работает),
      «Только скопировать в буфер» (ничего никуда не вставляем).

    Редкое свёрнуто под «Ещё»:
    - Звук компьютера на время записи: «Не трогать», «Убавить» (глубина
      задаётся ползунком «Насколько убавлять»), «Выключить».
    - Словарь: имена, термины и названия, которые Whisper путает.
    - Причёсывать текст: убрать «э-э», расставить знаки. Стоит ещё немного
      денег — это второй запрос к модели.

    МИКРОФОН. Выбирается из двух видов: беспроводная гарнитура или встроенный
    микрофон мака. Выбор становится системным микрофоном macOS. Правила
    приглушения: выбрана гарнитура — звук приглушается на время записи
    и возвращается после. Выбран встроенный, а рядом есть гарнитура — ничего
    не приглушается: человек слушает в наушниках, и в микрофон оттуда ничего
    не попадает. Гарнитуры нет вовсе — приглушается.

    ВАЖНО ПРО BLUETOOTH. У беспроводных наушников два режима — музыкальный
    и гарнитурный, одновременно они не работают. Поэтому запись микрофоном
    самих наушников обрывает в них музыку, а если наушники подключены ещё
    и к телефону, перетягивает их на мак. Это ограничение Bluetooth, а не
    приложения. Хочешь, чтобы музыка не прерывалась, — пиши встроенным
    микрофоном.

    ИСТОРИЯ (⌘2). Последние расшифровки, хранятся только на маке. Хранение
    можно выключить и историю очистить.

    КАСТОМИЗАЦИЯ (⌘3). Шесть акцентных цветов; тема светлая, тёмная или
    системная; звуковые сигналы на начало и конец записи с общей громкостью.

    КЛЮЧ И РАСХОДЫ (⌘4). Ключ OpenAI (хранится в связке ключей мака),
    оценка расходов по моделям за период, доступ к клавиатуре, автозапуск
    при входе в систему.

    О ПРОГРАММЕ (⌘5). Версия, «Скопировать сведения» для обращения, телеграм
    и почта разработчика, этот помощник, диагностика.

    РАЗРЕШЕНИЯ. Нужны три: микрофон, «Универсальный доступ» (вставлять текст
    в чужие окна) и «Мониторинг ввода» (видеть горячую клавишу). Выдаются
    в Системных настройках → Конфиденциальность и безопасность. Приложение
    замечает выдачу само, перезапускать не нужно.

    ЕСЛИ НЕ РАБОТАЕТ:
    - Клавиша не срабатывает — «Мониторинг ввода» не выдан, либо сочетание
      уже занято другой программой. Проверить: «О программе» → «Состояние».
    - Текст не вставляется, но лежит в буфере — не выдан «Универсальный
      доступ». Как временный обход подойдёт «Напечатать посимвольно».
    - «Whisper вернул пустой текст» — в записи не было речи: не тот микрофон
      или слишком тихо.
    - Плавающая ошибка — включить «Подробный журнал» в разделе «О программе»,
      повторить, нажать «Сохранить копию…» и приложить файл к письму.

    ПРИВАТНОСТЬ. Звук уходит только в OpenAI и только на время расшифровки,
    на диске не остаётся. Ключ хранится на маке, в связке ключей. Своего
    сервера у приложения нет, телеметрии нет.
    """
}
