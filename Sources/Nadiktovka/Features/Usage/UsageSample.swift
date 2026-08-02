import Foundation

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
/// Тип живёт рядом с расходами, а не в общем `AppEvents.swift`: за его пределы
/// он не выходит, а общий файл — подготовительный контракт, который слайсы
/// не правят. Состав полей заморожен так же, как у `TranscriptionRecord`:
/// на диске лежат записи, которые должны читаться будущими версиями.
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
