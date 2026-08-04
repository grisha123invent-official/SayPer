import Foundation

/// Клиент OpenAI: расшифровка через /v1/audio/transcriptions и необязательная
/// чистка результата через /v1/chat/completions.
enum Transcriber {
    /// Долгая сессия для мелких запросов: проверка ключа.
    ///
    /// Расшифровка ею не пользуется намеренно — см. `upload(_:body:)`.
    private static let session: URLSession = makeSession()

    private static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.default
        // У сессии по умолчанию 60 секунд, и на медленной сети отправка записи
        // в них не укладывается.
        config.timeoutIntervalForRequest = 90
        config.timeoutIntervalForResource = 240
        config.waitsForConnectivity = true
        return URLSession(configuration: config)
    }

    /// Сколько ждём ответа, если по соединению не идёт ни байта.
    ///
    /// Меньше умолчания URLRequest в 60 секунд, но с запасом на долгую запись:
    /// пока сервер расшифровывает, данные не идут вообще. Собственный таймаут
    /// запроса обязателен — он перекрывает настройку сессии, и без него
    /// та девяностосекундная настройка не значит ничего.
    private static let requestTimeout: TimeInterval = 45

    enum TranscribeError: LocalizedError {
        case noAPIKey
        case tooShort
        case http(Int, String)
        case empty

        var errorDescription: String? {
            switch self {
            case .noAPIKey:
                return "Не задан API-ключ OpenAI. Открой «Настройки…» в меню приложения."
            case .tooShort:
                return "Запись слишком короткая."
            case .http(let code, let message):
                return "OpenAI ответил \(code): \(message)"
            case .empty:
                return "Whisper вернул пустой текст — похоже, в записи не было речи."
            }
        }
    }

    /// Проверка ключа лёгким запросом. nil — всё в порядке, иначе текст ошибки.
    static func validateKey(_ key: String) async -> String? {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Ключ пустой" }

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
        request.setValue("Bearer \(trimmed)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 20

        do {
            let (data, response) = try await session.data(for: request)
            try check(response: response, data: data)
            return nil
        } catch let error as TranscribeError {
            if case .http(401, _) = error { return "Ключ не принят (401)" }
            return error.localizedDescription
        } catch {
            return "Нет связи: \(error.localizedDescription)"
        }
    }

    /// `onRetry` дёргается перед повторной попыткой отправки — по нему панель
    /// показывает «связь подвела, повторяю». Молчаливый повтор выглядит
    /// как зависание, и человек начинает диктовать заново поверх работающего.
    static func transcribe(fileURL: URL,
                           onRetry: ((Int) -> Void)? = nil) async throws -> String {
        let settings = Settings.shared
        guard let apiKey = settings.apiKey else { throw TranscribeError.noAPIKey }

        let audio = try Data(contentsOf: fileURL)
        // Пустой файл — это только заголовок в пару сотен байт.
        guard audio.count > 1_000 else { throw TranscribeError.tooShort }

        var fields: [String: String] = ["model": settings.model.rawValue]
        if !settings.language.isEmpty {
            fields["language"] = settings.language
        }
        let vocabulary = settings.vocabulary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !vocabulary.isEmpty {
            fields["prompt"] = vocabulary
        }
        // gpt-4o-*-transcribe не поддерживает verbose_json, а text умеют все.
        fields["response_format"] = "text"

        let isM4A = fileURL.pathExtension.lowercased() == "m4a"
        let filename = isM4A ? "audio.m4a" : "audio.wav"
        let mime = isM4A ? "audio/m4a" : "audio/wav"

        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        for (name, value) in fields {
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            body.append("\(value)\r\n")
        }
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
        body.append("Content-Type: \(mime)\r\n\r\n")
        body.append(audio)
        body.append("\r\n--\(boundary)--\r\n")

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = requestTimeout
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await upload(request, body: body, onRetry: onRetry)
        try check(response: response, data: data)

        let text = (String(data: data, encoding: .utf8) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw TranscribeError.empty }

        guard Settings.shared.cleanup else { return text }
        return (try? await cleanup(text: text, apiKey: apiKey)) ?? text
    }

    /// Лёгкая правка: пунктуация и слова-паразиты, смысл и формулировки не трогаем.
    private static func cleanup(text: String, apiKey: String) async throws -> String {
        let payload: [String: Any] = [
            "model": "gpt-4o-mini",
            "temperature": 0,
            "messages": [
                [
                    "role": "system",
                    "content": """
                    Ты редактор расшифровок речи. Расставь пунктуацию и заглавные буквы, \
                    убери слова-паразиты, оговорки и повторы. Не переписывай текст, \
                    не добавляй ничего от себя, сохрани язык оригинала. \
                    В ответе верни только исправленный текст.
                    """
                ],
                ["role": "user", "content": text]
            ]
        ]

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = requestTimeout
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        // Своя сессия по той же причине, что и у отправки записи.
        let clean = makeSession()
        defer { clean.finishTasksAndInvalidate() }
        let (data, response) = try await clean.data(for: request)
        try check(response: response, data: data)

        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any],
            let content = message["content"] as? String
        else { return text }

        let cleaned = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? text : cleaned
    }

    /// Отправка с повторными попытками. Обрыв связи или таймаут — обычное дело,
    /// терять из-за них готовую запись обидно.
    ///
    /// Каждая попытка идёт по своей сессии, то есть по своему соединению,
    /// и сессия сразу закрывается.
    ///
    /// Иначе вторая расшифровка подряд зависала ровно на минуту. В журнале
    /// картина была однозначная: первая отправка после запуска или после
    /// долгого простоя — полторы секунды, следующая через 20-40 секунд —
    /// 60 секунд тишины, обрыв по таймауту и мгновенный успех на повторе.
    /// Виновато переиспользование соединения: приложение живёт в фоне,
    /// система его придерживает, и сокет из пула к моменту второй отправки
    /// уже мёртв — а URLSession об этом не знает и пишет в пустоту до таймаута.
    /// Ценой лишнего рукопожатия TLS, то есть четверти секунды, снимается
    /// минута ожидания.
    private static func upload(_ request: URLRequest, body: Data,
                               onRetry: ((Int) -> Void)? = nil) async throws -> (Data, URLResponse) {
        var lastError: Error?

        for attempt in 1...3 {
            let session = makeSession()
            defer { session.finishTasksAndInvalidate() }

            let startedAt = Date()
            do {
                let result = try await session.upload(for: request, from: body)
                Log.debug("Отправка \(body.count) байт, попытка \(attempt)")
                if attempt > 1 {
                    Log.write("Попытка \(attempt) удалась за "
                              + String(format: "%.1f", Date().timeIntervalSince(startedAt)) + " с")
                }
                return result
            } catch let error as URLError where isWorthRetrying(error) && attempt < 3 {
                lastError = error
                Log.write("Попытка \(attempt): сеть подвела (\(error.code.rawValue)) через "
                          + String(format: "%.1f", Date().timeIntervalSince(startedAt))
                          + " с, пробую заново")
                onRetry?(attempt + 1)
            }
        }

        throw lastError ?? URLError(.unknown)
    }

    private static func isWorthRetrying(_ error: URLError) -> Bool {
        switch error.code {
        case .timedOut, .networkConnectionLost, .notConnectedToInternet,
             .cannotConnectToHost, .dnsLookupFailed:
            return true
        default:
            return false
        }
    }

    private static func check(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard !(200..<300).contains(http.statusCode) else { return }

        var message = String(data: data, encoding: .utf8) ?? ""
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = json["error"] as? [String: Any],
           let text = error["message"] as? String {
            message = text
        }
        throw TranscribeError.http(http.statusCode, message)
    }
}

private extension Data {
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }
}
