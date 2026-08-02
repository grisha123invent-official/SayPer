import Foundation

/// Итог одной модели за сутки. Нужен только для разбивки «По моделям»:
/// день целиком считается полями самого `UsageDay`, иначе одна расшифровка
/// с включённой чисткой посчиталась бы дважды — как аудио и как правка.
struct UsageModelTotals: Codable, Equatable {
    /// Сколько раз обращались к этой модели.
    var count: Int = 0
    /// Суммарная длительность аудио, секунды. У модели-правщика она нулевая:
    /// текст ей отдают уже расшифрованным, минут там нет.
    var duration: TimeInterval = 0
    /// Оценка стоимости, доллары.
    var cost: Double = 0
}

/// Суточный агрегат. **Текста расшифровок здесь нет и быть не может** —
/// файл с текстами ровно один, им управляет «Хранить историю» (см. `AppEvents.swift`).
///
/// Дневные поля — источник итога, `models` — только разрез для карточки
/// «По моделям». Сумма по `models` совпадает с `cost`, но не с `count`.
struct UsageDay: Codable, Equatable, Identifiable {
    /// Начало суток в часовом поясе, в котором была сделана запись.
    let day: Date
    /// Сколько расшифровок за день.
    var count: Int = 0
    /// Суммарная длительность записей, секунды.
    var duration: TimeInterval = 0
    var words: Int = 0
    var characters: Int = 0
    /// Оценка стоимости за день: аудио плюс правка.
    var cost: Double = 0
    /// `modelID` → итог. Ключ правки — `Pricing.cleanupModelID`.
    var models: [String: UsageModelTotals] = [:]

    var id: Date { day }
}

/// Суточные агрегаты на диске: `~/Library/Application Support/SayPer/usage.json`.
///
/// Почему агрегаты, а не события: одна запись в день вместо сотни строк —
/// файл остаётся читаемым глазами, растёт линейно по дням, а не по расшифровкам,
/// и в нём физически негде оказаться тексту.
///
/// Битый файл считается отсутствующим: статистика — не то, ради чего стоит
/// падать при запуске. Предыдущее содержимое в этом случае перезапишется.
final class UsageArchive {
    /// Версия формата. Файл со старшей версией не читаем: лучше показать пусто,
    /// чем разобрать наполовину и потерять остальное при первой же записи.
    static let currentVersion = 1

    /// Сколько суток храним. Год с запасом: агрегат — десятки байт в день,
    /// а «всё время» без границы рано или поздно превращается в мусор.
    static let retentionDays = 400

    private struct Payload: Codable {
        var version: Int
        var days: [UsageDay]
    }

    private let url: URL
    /// Запись — вне главного потока, но строго по очереди: два сохранения
    /// подряд не должны перемешаться в одном файле.
    private let queue = DispatchQueue(label: "ru.nadiktovka.usage-archive", qos: .utility)

    init(url: URL = AppPaths.supportFile("usage.json")) {
        self.url = url
    }

    /// Читает агрегаты, отсортированные по возрастанию даты.
    ///
    /// Дубликаты суток схлопываются здесь же: инвариант «один день — одна
    /// запись» должен держаться на границе с диском, как и остальные проверки
    /// файла. Дальше по коду день служит ключом словаря, и второй такой же
    /// ронял бы приложение при открытии раздела.
    func load() -> [UsageDay] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        guard let payload = try? Self.decoder.decode(Payload.self, from: data),
              payload.version <= Self.currentVersion else {
            Log.write("Файл расходов не прочитан, начинаю с пустой статистики")
            return []
        }
        return Self.collapsed(payload.days).sorted { $0.day < $1.day }
    }

    /// Записывает агрегаты целиком. Файл маленький, частичная запись
    /// усложнила бы формат ради экономии килобайта.
    func save(_ days: [UsageDay]) {
        let payload = Payload(version: Self.currentVersion, days: days)
        queue.async { [url] in
            guard let data = try? Self.encoder.encode(payload) else { return }
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                Log.write("Не удалось сохранить расходы: \(error.localizedDescription)")
            }
        }
    }

    /// Убирает файл целиком — «Сбросить статистику». Пустой файл не оставляем:
    /// его отсутствие и есть отсутствие данных.
    func removeAll() {
        queue.async { [url] in
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Отсекает всё старше срока хранения.
    ///
    /// Срок набирается сутками календаря, а не умножением на 86400: в поясе
    /// с переводом часов сутки бывают на час короче или длиннее, и граница
    /// хранения поехала бы относительно тех же суток на графике.
    static func pruned(_ days: [UsageDay], now: Date = Date(), calendar: Calendar = .current) -> [UsageDay] {
        let today = calendar.startOfDay(for: now)
        let edge = calendar.date(byAdding: .day, value: -retentionDays, to: today) ?? today
        return days.filter { $0.day >= edge }
    }

    /// Схлопывает записи с одинаковым днём в одну.
    ///
    /// Складываем, а не оставляем последнюю: файл задуман читаемым и правимым
    /// глазами, и две записи за одни сутки — это чаще всего две части одного дня
    /// (слияние резервной копии, правка руками, второй экземпляр приложения),
    /// а не старое и новое значение одного и того же.
    ///
    /// Порядок первого появления сохраняется — сортировка идёт отдельным шагом.
    static func collapsed(_ days: [UsageDay]) -> [UsageDay] {
        var merged: [Date: UsageDay] = [:]
        var order: [Date] = []

        for day in days {
            guard var entry = merged[day.day] else {
                merged[day.day] = day
                order.append(day.day)
                continue
            }

            entry.count += day.count
            entry.duration += day.duration
            entry.words += day.words
            entry.characters += day.characters
            entry.cost += day.cost

            for (modelID, totals) in day.models {
                var model = entry.models[modelID] ?? UsageModelTotals()
                model.count += totals.count
                model.duration += totals.duration
                model.cost += totals.cost
                entry.models[modelID] = model
            }

            merged[day.day] = entry
        }

        return order.compactMap { merged[$0] }
    }

    // MARK: -

    /// Даты в ISO 8601: файл лежит в папке пользователя и должен читаться глазами,
    /// а не быть набором секунд от 2001 года.
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
}
