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

/// Агрегат одной расшифровки — **без текста**.
///
/// Зачем отдельный тип. `TranscriptionRecord` несёт текст, и если бы его писали
/// на диск оба хранилища, расшифровки лежали бы в двух файлах сразу, а
/// переключатель «Хранить историю» гасил бы только один из них — то есть тексты
/// продолжали бы копиться за спиной у человека. Поэтому договорённость жёсткая:
///
/// - файл с текстами ровно один — архив истории, и им управляет «Хранить историю»;
/// - расходы считают по `UsageSample`: длительность, слова, символы, модель,
///   дата, латентность. Текста здесь нет и быть не должно;
/// - «Очистить историю» стирает тексты и не трогает статистику, «Сбросить
///   расходы» стирает статистику и не трогает тексты — потому что это разные файлы.
///
/// Состав полей заморожен так же, как у `TranscriptionRecord`: на диске лежат
/// записи, которые должны читаться будущими версиями.
struct UsageSample: Codable, Identifiable, Equatable {
    let id: UUID
    /// Момент, когда текст был готов.
    let date: Date
    /// Длительность самой записи, секунды.
    let audioDuration: TimeInterval
    /// Сколько ждали ответа от OpenAI, секунды.
    let latency: TimeInterval
    /// Идентификатор модели (`Settings.model.rawValue`) — по нему берётся тариф.
    let modelID: String
    /// Слов в расшифровке. Само слово не хранится, только счёт.
    let wordCount: Int
    /// Символов в расшифровке: по ним оценивается стоимость причёсывания.
    let characterCount: Int
    /// Прогоняли ли текст через чистку — у неё свой тариф.
    let cleanupUsed: Bool

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        audioDuration: TimeInterval,
        latency: TimeInterval,
        modelID: String,
        wordCount: Int,
        characterCount: Int,
        cleanupUsed: Bool
    ) {
        self.id = id
        self.date = date
        self.audioDuration = audioDuration
        self.latency = latency
        self.modelID = modelID
        self.wordCount = wordCount
        self.characterCount = characterCount
        self.cleanupUsed = cleanupUsed
    }

    /// Единственный законный путь из события в статистику: текст отбрасывается
    /// здесь, до всякой записи на диск.
    init(_ record: TranscriptionRecord) {
        self.init(
            id: record.id,
            date: record.date,
            audioDuration: record.audioDuration,
            latency: record.latency,
            modelID: record.modelID,
            wordCount: record.wordCount,
            characterCount: record.characterCount,
            cleanupUsed: record.cleanupUsed
        )
    }
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
