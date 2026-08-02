import Foundation

/// Одна удачная расшифровка. Состав полей заморожен: история и расходы
/// считают по нему, поэтому добавлять поля «под себя» нельзя —
/// иначе на диске окажутся записи разных форматов.
struct TranscriptionRecord: Codable, Identifiable, Equatable {
    let id: UUID
    /// Момент, когда текст был готов.
    let date: Date
    let text: String
    /// Длительность самой записи, секунды.
    let audioDuration: TimeInterval
    /// Сколько ждали ответа от OpenAI, секунды.
    let latency: TimeInterval
    /// Идентификатор модели, которой расшифровывали (`Settings.model.rawValue`).
    let modelID: String
    /// Код языка или "" для автоопределения.
    let language: String
    /// Прогоняли ли текст через чистку.
    let cleanupUsed: Bool

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        text: String,
        audioDuration: TimeInterval,
        latency: TimeInterval,
        modelID: String,
        language: String,
        cleanupUsed: Bool
    ) {
        self.id = id
        self.date = date
        self.text = text
        self.audioDuration = audioDuration
        self.latency = latency
        self.modelID = modelID
        self.language = language
        self.cleanupUsed = cleanupUsed
    }

    var wordCount: Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    var characterCount: Int { text.count }
}

/// Кто хочет знать о новых расшифровках: история, расходы и всё, что появится дальше.
protocol TranscriptionObserver: AnyObject {
    func transcriptionDidFinish(_ record: TranscriptionRecord)
}

/// Шина событий. Одно направление: оркестровка записи публикует, хранилища слушают.
/// Обратной связи нет намеренно — так хранилища не могут повлиять на запись.
enum TranscriptionBus {
    /// Слабые ссылки: шина не продлевает жизнь подписчикам.
    private final class Box {
        weak var observer: TranscriptionObserver?
        init(_ observer: TranscriptionObserver) { self.observer = observer }
    }

    private static var boxes: [Box] = []

    static func register(_ observer: TranscriptionObserver) {
        boxes.removeAll { $0.observer == nil || $0.observer === observer }
        boxes.append(Box(observer))
    }

    static func unregister(_ observer: TranscriptionObserver) {
        boxes.removeAll { $0.observer == nil || $0.observer === observer }
    }

    /// Всегда доставляет на главном потоке: подписчики держат состояние для интерфейса.
    static func publish(_ record: TranscriptionRecord) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { publish(record) }
            return
        }

        boxes.removeAll { $0.observer == nil }
        for box in boxes {
            box.observer?.transcriptionDidFinish(record)
        }
    }
}
