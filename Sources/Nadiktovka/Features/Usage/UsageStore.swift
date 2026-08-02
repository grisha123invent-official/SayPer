import Foundation
import Combine

/// Сколько наговорили и во сколько это обошлось. Заготовка: считает по записям
/// текущего сеанса, стоимость всегда 0 — тарифы и хранение на диске добавляет
/// слайс «Расходы». API заморожен: меню статус-бара опирается на него уже сейчас.
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
    }

    /// Один день на графике и в списке.
    struct DayBucket: Identifiable, Equatable {
        /// Начало дня.
        let day: Date
        let summary: Summary

        var id: Date { day }
    }

    @Published private(set) var records: [TranscriptionRecord] = []

    private let calendar = Calendar.current

    private init() {}

    // MARK: - Срезы

    var today: Summary {
        summary(since: calendar.startOfDay(for: Date()))
    }

    var allTime: Summary {
        Self.summarize(records)
    }

    /// Последние 30 дней, от старого к новому. Дни без записей не попадают.
    var last30Days: [DayBucket] {
        let since = calendar.startOfDay(for: Date()).addingTimeInterval(-29 * 24 * 3600)
        let grouped = Dictionary(grouping: records.filter { $0.date >= since }) {
            calendar.startOfDay(for: $0.date)
        }
        return grouped
            .map { DayBucket(day: $0.key, summary: Self.summarize($0.value)) }
            .sorted { $0.day < $1.day }
    }

    func summary(since date: Date) -> Summary {
        Self.summarize(records.filter { $0.date >= date })
    }

    func resetAll() {
        records.removeAll()
    }

    // MARK: - Подписка на шину

    func transcriptionDidFinish(_ record: TranscriptionRecord) {
        records.append(record)
    }

    // MARK: -

    private static func summarize(_ records: [TranscriptionRecord]) -> Summary {
        var summary = Summary.empty
        for record in records {
            summary.count += 1
            summary.duration += record.audioDuration
            summary.words += record.wordCount
            summary.characters += record.characterCount
            // Стоимость появится вместе с таблицей тарифов (`Pricing.swift`).
        }
        return summary
    }
}
