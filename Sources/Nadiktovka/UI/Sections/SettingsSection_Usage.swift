import AppKit
import SwiftUI

/// Раздел «Расходы»: минуты, слова и оценка стоимости.
///
/// Раздел прокручивается — это норма: четыре плитки, график за месяц и разбивка
/// по моделям в 540pt по высоте не помещаются, а ужимать график ради того, чтобы
/// всё было видно сразу, значит сделать его нечитаемым.
struct SettingsSectionUsage: View {
    @ObservedObject private var store = UsageStore.shared

    @State private var period = Settings.shared.usagePeriod
    @State private var showsNumbers = Settings.shared.usageShowsNumbers
    @State private var isConfirmingReset = false

    var body: some View {
        SectionScaffold {
            expenses
            if !summary.isEmpty {
                models
                reset
            }
        }
    }

    // MARK: - Данные

    private var summary: UsageStore.Summary {
        store.summary(for: period)
    }

    private var chartPoints: [UsageChart.Point] {
        store.buckets(lastDays: period.chartDays).map {
            UsageChart.Point(day: $0.day, value: $0.summary.cost)
        }
    }

    // MARK: - Карточка «Расходы»

    private var expenses: some View {
        GlassCard("Расходы", accessory: AnyView(periodPicker), separated: true) {
            CardDivider()

            tiles

            if summary.isEmpty {
                emptyState
            } else {
                UsageChart(points: chartPoints)
                    .padding(.top, Palette.spaceMd)

                // Единственная подсказка в разделе: из плитки «$2.34» не видно,
                // откуда взялось число, а это ровно тот случай, когда подсказка
                // объясняет невидимое последствие.
                Hint("Оценка по тарифу выбранной модели на момент запроса — "
                     + "API не возвращает точный расход")
                    .padding(.top, 10)

                numbersToggle
            }
        }
    }

    private var periodPicker: some View {
        SegmentedControl(selection: periodBinding, compact: true) { $0.title }
    }

    private var periodBinding: Binding<UsagePeriod> {
        Binding(
            get: { period },
            set: {
                period = $0
                Settings.shared.usagePeriod = $0
            }
        )
    }

    private var tiles: some View {
        HStack(spacing: Palette.spaceSm) {
            StatTile(value: Self.count(summary.count), caption: "расшифровок")
            StatTile(value: Self.minutes(summary.duration), caption: "минут")
            StatTile(value: Self.count(summary.words), caption: "слов")
            StatTile(value: Self.money(summary.cost, isEmpty: summary.isEmpty),
                     caption: "потрачено")
        }
        .padding(.top, Palette.spaceXs)
    }

    /// Пусто — это не ошибка и не повод для иллюстрации: одна строка о том,
    /// откуда возьмутся цифры, и всё.
    private var emptyState: some View {
        HStack(spacing: Palette.spaceXs) {
            Image(systemName: SettingsSection.usage.symbol)
                .font(.system(size: 15))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
            Text("Здесь появятся расходы после первой расшифровки")
                .font(.body)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.top, Palette.spaceMd)
        .padding(.bottom, Palette.space2xs)
    }

    // MARK: - Цифрами

    /// График читается не всеми и не всегда: те же значения обязаны быть
    /// доступны текстом, иначе данные существуют только для зрячей мыши.
    @ViewBuilder
    private var numbersToggle: some View {
        Button(showsNumbers ? "Скрыть цифры" : "Показать цифрами") {
            showsNumbers.toggle()
            Settings.shared.usageShowsNumbers = showsNumbers
        }
        .buttonStyle(.plain)
        .font(.subheadline)
        .foregroundStyle(Color.accentColor)
        .padding(.top, Palette.spaceSm)
        .frame(maxWidth: .infinity, alignment: .leading)

        if showsNumbers {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(store.buckets(lastDays: period.chartDays).reversed()) { bucket in
                        HStack {
                            Text(Self.dayFormatter.string(from: bucket.day))
                                .foregroundStyle(.secondary)
                            Spacer(minLength: Palette.spaceSm)
                            Text(Pricing.money(bucket.summary.cost))
                                .monospacedDigit()
                        }
                        .font(.subheadline)
                        .frame(height: 22)
                    }
                }
            }
            .frame(maxHeight: 132)
            .padding(.top, Palette.spaceXs)
        }
    }

    // MARK: - Карточка «По моделям»

    private var models: some View {
        GlassCard("По моделям", separated: true) {
            CardDivider()

            let rows = store.models(for: period)
            let maxCost = rows.map(\.cost).max() ?? 0

            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 {
                    CardDivider()
                }
                modelRow(row, maxCost: maxCost)
            }
        }
    }

    private func modelRow(_ row: UsageStore.ModelUsage, maxCost: Double) -> some View {
        HStack(spacing: Palette.spaceSm) {
            Text(row.title)
                .font(.body)
                .lineLimit(1)
                .frame(width: 176, alignment: .leading)

            // Полоса-мера: доля этой модели в общих расходах. Тон один —
            // это одна величина, а не разные категории.
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(Self.meterTrack)
                    Capsule(style: .continuous)
                        .fill(Color.accentColor)
                        .frame(width: geometry.size.width * Self.share(row.cost, of: maxCost))
                }
            }
            .frame(height: 6)

            Text(Self.modelAmount(row))
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 62, alignment: .trailing)

            Text(Pricing.money(row.cost))
                .font(.body)
                .monospacedDigit()
                .frame(width: 54, alignment: .trailing)
        }
        .frame(height: 28)
    }

    // MARK: - Сброс

    /// Отбивка перед редким и необратимым действием — 32pt: 24 даёт сам
    /// каркас между карточками, оставшиеся 8 добавляются здесь.
    private var reset: some View {
        HStack {
            CapsuleButton("Сбросить статистику") { isConfirmingReset = true }
            Spacer(minLength: 0)
        }
        .padding(.top, Palette.spaceXs)
        .confirmationDialog(
            "Сбросить статистику расходов?",
            isPresented: $isConfirmingReset
        ) {
            Button("Сбросить", role: .destructive) { store.resetAll() }
            Button("Отмена", role: .cancel) {}
        } message: {
            // Разводить два хранилища словами обязательно: иначе человек решит,
            // что вместе со счётчиками стёр и расшифровки.
            Text("Счётчики и график обнулятся. Расшифровки в разделе «История» останутся.")
        }
    }

    // MARK: - Форматирование

    private static func count(_ value: Int) -> String {
        value == 0 ? "—" : countFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    /// До десяти минут — с десятыми: «0» вместо сорока секунд выглядит как сбой.
    private static func minutes(_ duration: TimeInterval) -> String {
        guard duration > 0 else { return "—" }
        let minutes = duration / 60
        if minutes >= 10 {
            return countFormatter.string(from: NSNumber(value: Int(minutes.rounded())))
                ?? "\(Int(minutes.rounded()))"
        }
        return decimalFormatter.string(from: NSNumber(value: minutes)) ?? "0"
    }

    private static func money(_ value: Double, isEmpty: Bool) -> String {
        isEmpty ? "—" : Pricing.money(value)
    }

    /// У правщика минут нет — там считаются запуски.
    private static func modelAmount(_ row: UsageStore.ModelUsage) -> String {
        guard row.duration > 0 else { return "\(row.count) зап." }
        return "\(Int((row.duration / 60).rounded())) мин"
    }

    private static func share(_ value: Double, of maximum: Double) -> CGFloat {
        guard maximum > 0 else { return 0 }
        return CGFloat(min(max(value / maximum, 0), 1))
    }

    private static let countFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "ru_RU")
        return formatter
    }()

    private static let decimalFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.setLocalizedDateFormatFromTemplate("d MMMM")
        return formatter
    }()

    /// Дорожка полосы-меры: тот же акцент, приглушённый до подложки.
    private static let meterTrack = Color.accentColor.opacity(0.16)
}
