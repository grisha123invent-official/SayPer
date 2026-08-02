import Foundation
import Combine

/// Сколько наговорили и во сколько это обошлось.
///
/// Хранит **только агрегаты** (`UsageDay`): текст расшифровки отбрасывается
/// на входе, в `UsageSample`, и до этого хранилища не доходит. Это не мелочь
/// оформления, а договорённость из `UsageSample.swift`: файл с текстами ровно
/// один, и гасит его «Хранить историю», а не переключатель в расходах.
///
/// API заморожен планом (`Summary`, `DayBucket`, `today`, `allTime`,
/// `last30Days`, `summary(since:)`, `resetAll`) — меню статус-бара опирается
/// на него.
final class UsageStore: ObservableObject, TranscriptionObserver {
    static let shared = UsageStore()

    /// Итог за период. Стоимость — всегда оценка: API не возвращает usage
    /// при `response_format: text`, считать приходится по длительности.
    struct Summary: Equatable {
        var count: Int = 0
        /// Суммарная длительность записей, секунды.
        var duration: TimeInterval = 0
        var words: Int = 0
        var characters: Int = 0
        /// Оценка стоимости в долларах.
        var cost: Double = 0

        static let empty = Summary()

        var minutes: Double { duration / 60 }
        var isEmpty: Bool { count == 0 }
    }

    /// Один день на графике и в списке.
    struct DayBucket: Identifiable, Equatable {
        /// Начало дня.
        let day: Date
        let summary: Summary

        var id: Date { day }
    }

    /// Строка разбивки «По моделям».
    struct ModelUsage: Identifiable, Equatable {
        let modelID: String
        /// Как подписать: у правки к идентификатору добавляется пометка.
        let title: String
        let count: Int
        /// Секунды аудио. У модели-правщика ноль — минут там нет.
        let duration: TimeInterval
        let cost: Double

        var id: String { modelID }
    }

    /// Суточные агрегаты по возрастанию даты.
    @Published private(set) var days: [UsageDay] = []

    private let archive: UsageArchive
    private let calendar = Calendar.current

    private init() {
        archive = UsageArchive()
        days = UsageArchive.pruned(archive.load())
    }

    // MARK: - Срезы

    var today: Summary {
        summary(since: calendar.startOfDay(for: Date()))
    }

    var allTime: Summary {
        Self.summarize(days)
    }

    /// Последние 30 суток, от старого к новому. Дни без записей входят нулями —
    /// иначе столбцы графика поехали бы, а провал в работе выглядел бы
    /// как непрерывная нагрузка.
    var last30Days: [DayBucket] {
        buckets(lastDays: 30)
    }

    func summary(since date: Date) -> Summary {
        Self.summarize(days.filter { $0.day >= calendar.startOfDay(for: date) })
    }

    func summary(for period: UsagePeriod) -> Summary {
        guard let start = period.start(calendar: calendar) else { return allTime }
        return summary(since: start)
    }

    /// Ровно `count` корзин подряд, заканчивая сегодняшним днём.
    func buckets(lastDays count: Int) -> [DayBucket] {
        guard count > 0 else { return [] }
        let today = calendar.startOfDay(for: Date())
        // Дубликаты суток уже сняты на входе (`UsageArchive.collapsed`), но
        // словарь строится из данных с диска, а `uniqueKeysWithValues` на них
        // означает падение по precondition вместо показа статистики.
        let byDay = Dictionary(days.map { ($0.day, $0) }, uniquingKeysWith: { $1 })

        return (0..<count).reversed().map { offset in
            let day = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
            guard let stored = byDay[day] else {
                return DayBucket(day: day, summary: .empty)
            }
            return DayBucket(day: day, summary: Self.summarize([stored]))
        }
    }

    /// Разбивка по моделям за период, от дорогих к дешёвым.
    func models(for period: UsagePeriod) -> [ModelUsage] {
        let start = period.start(calendar: calendar).map { calendar.startOfDay(for: $0) }
        var totals: [String: UsageModelTotals] = [:]

        for day in days where start.map({ day.day >= $0 }) ?? true {
            for (modelID, model) in day.models {
                var entry = totals[modelID] ?? UsageModelTotals()
                entry.count += model.count
                entry.duration += model.duration
                entry.cost += model.cost
                totals[modelID] = entry
            }
        }

        return totals
            .map {
                ModelUsage(
                    modelID: $0.key,
                    title: Pricing.displayName(forModel: $0.key),
                    count: $0.value.count,
                    duration: $0.value.duration,
                    cost: $0.value.cost
                )
            }
            // Вторым ключом — идентификатор: при равной стоимости порядок
            // не должен меняться от перезапуска к перезапуску, а обход словаря
            // его не гарантирует.
            .sorted {
                $0.cost == $1.cost ? $0.modelID < $1.modelID : $0.cost > $1.cost
            }
    }

    func resetAll() {
        days.removeAll()
        archive.removeAll()
    }

    // MARK: - Подписка на шину

    func transcriptionDidFinish(_ record: TranscriptionRecord) {
        add(UsageSample(record))
    }

    /// Единственная точка входа для новых данных. Стоимость считается здесь,
    /// в момент запроса, и уже такой ложится на диск: тариф со временем меняется,
    /// а потраченное вчера от этого другим не становится.
    func add(_ sample: UsageSample) {
        let day = calendar.startOfDay(for: sample.date)
        let audioCost = Pricing.audioCost(seconds: sample.audioDuration, modelID: sample.modelID)
        let cleanupCost = sample.cleanupUsed
            ? Pricing.cleanupCost(characters: sample.characterCount)
            : 0

        var entry = days.first { $0.day == day } ?? UsageDay(day: day)
        entry.count += 1
        entry.duration += sample.audioDuration
        entry.words += sample.wordCount
        entry.characters += sample.characterCount
        entry.cost += audioCost + cleanupCost

        var audio = entry.models[sample.modelID] ?? UsageModelTotals()
        audio.count += 1
        audio.duration += sample.audioDuration
        audio.cost += audioCost
        entry.models[sample.modelID] = audio

        if sample.cleanupUsed {
            var cleanup = entry.models[Pricing.cleanupModelID] ?? UsageModelTotals()
            cleanup.count += 1
            cleanup.cost += cleanupCost
            entry.models[Pricing.cleanupModelID] = cleanup
        }

        var updated = days.filter { $0.day != day }
        updated.append(entry)
        updated.sort { $0.day < $1.day }

        days = UsageArchive.pruned(updated)
        archive.save(days)
    }

    // MARK: -

    private static func summarize(_ days: [UsageDay]) -> Summary {
        var summary = Summary.empty
        for day in days {
            summary.count += day.count
            summary.duration += day.duration
            summary.words += day.words
            summary.characters += day.characters
            summary.cost += day.cost
        }
        return summary
    }
}
