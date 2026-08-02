import Foundation

/// Тарифы OpenAI и пересчёт их в деньги.
///
/// Почему всё в одном месте: цифра «потрачено» — единственное, что человек
/// в этом приложении не может проверить сам, поэтому источник у неё обязан быть
/// ровно один. Меняется тариф — правится эта таблица, и больше ничего.
///
/// **Стоимость здесь — всегда оценка, а не факт.** При `response_format: text`
/// ответ API не содержит блока `usage`, то есть реальное число токенов
/// приложению не сообщают. Аудио считается по длительности записи и тарифу
/// модели, причёсывание — по длине текста. Ошибка в пределах десятка процентов
/// здесь нормальна, и подписывать это как точную сумму нельзя.
enum Pricing {
    // MARK: - Аудио

    /// Доллары за минуту аудио, по идентификатору модели.
    /// Ключи совпадают с `TranscriptionModel.rawValue` — по нему тариф и ищется.
    private static let audioPerMinute: [String: Double] = [
        "whisper-1": 0.006,
        "gpt-4o-transcribe": 0.006,
        "gpt-4o-mini-transcribe": 0.003
    ]

    /// Тариф для неизвестной модели. Ноль здесь был бы хуже: расходы молча
    /// перестали бы расти, и человек узнал бы об этом только из счёта.
    private static let fallbackPerMinute: Double = 0.006

    /// Тариф модели, если он известен.
    static func audioRate(forModel modelID: String) -> Double? {
        audioPerMinute[modelID]
    }

    /// Оценка стоимости расшифровки: длительность записи × тариф модели.
    static func audioCost(seconds: TimeInterval, modelID: String) -> Double {
        guard seconds > 0 else { return 0 }
        let rate = audioPerMinute[modelID] ?? fallbackPerMinute
        return seconds / 60 * rate
    }

    // MARK: - Причёсывание

    /// Модель, которой чистят текст (`Transcriber.cleanup`).
    static let cleanupModelID = "gpt-4o-mini"

    /// Доллары за миллион токенов.
    private static let cleanupInputPerMillion: Double = 0.15
    private static let cleanupOutputPerMillion: Double = 0.60

    /// Символов на токен. Для кириллицы у o200k_base выходит примерно три —
    /// латиница экономнее, но приложение русскоязычное, и занижать оценку хуже,
    /// чем завысить.
    private static let charactersPerToken: Double = 3

    /// Служебная часть запроса: системная инструкция чистки. Постоянная,
    /// на коротких расшифровках она и составляет основную часть счёта.
    private static let cleanupOverheadTokens: Double = 120

    /// Оценка стоимости одной чистки: текст уходит в модель и возвращается
    /// примерно той же длины, поэтому платится и вход, и выход.
    static func cleanupCost(characters: Int) -> Double {
        guard characters > 0 else { return 0 }
        let textTokens = Double(characters) / charactersPerToken
        let input = textTokens + cleanupOverheadTokens
        let output = textTokens
        return input / 1_000_000 * cleanupInputPerMillion
            + output / 1_000_000 * cleanupOutputPerMillion
    }

    // MARK: - Подписи

    /// Как модель называется в разбивке. Чистка получает пометку: иначе
    /// `gpt-4o-mini` в списке рядом с `gpt-4o-mini-transcribe` читается как опечатка.
    static func displayName(forModel modelID: String) -> String {
        modelID == cleanupModelID ? "\(modelID) · правка" : modelID
    }

    /// Формат `$0.06`: два знака, локаль источника цены.
    ///
    /// Переводить в рубли нечем — курса у приложения нет, а округлять до целых
    /// нельзя: почти все суммы здесь меньше доллара и схлопнулись бы в `$0`.
    static func money(_ value: Double) -> String {
        moneyFormatter.string(from: NSNumber(value: value)) ?? "$0.00"
    }

    private static let moneyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "en_US")
        formatter.currencyCode = "USD"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }()
}
