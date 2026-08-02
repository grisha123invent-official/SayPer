import SwiftUI

/// Раздел «История»: последние расшифровки, копирование и повторная вставка.
///
/// Одна карточка со списком и одна с хранением. Порядок такой, потому что
/// в раздел приходят за текстом, а не за настройкой: настройка — то, что
/// трогают один раз, и она уходит вниз (`ia.md`, принцип частоты).
struct SettingsSectionHistory: View {
    @ObservedObject private var store = HistoryStore.shared

    @State private var query = ""

    var body: some View {
        SectionScaffold {
            listCard
            storageCard
        }
    }

    // MARK: - Список

    private var listCard: some View {
        GlassCard("Последние расшифровки", accessory: counter, separated: true) {
            CardDivider()

            // Поиск появляется, только когда список перестаёт охватываться
            // взглядом (`ia.md` §1.3): на десяти строках поле — лишний контрол.
            if showsSearch {
                searchField
            }

            list
                .padding(.top, Palette.spaceSm)

            HStack(spacing: 0) {
                // Обычная капсула, не красная: второе контрастное пятно
                // на экране заводить нельзя (П6), а действие не катастрофично.
                CapsuleButton("Очистить историю") { store.clear() }
                    .disabled(store.isEmpty)
                Spacer(minLength: 0)
            }
            .padding(.top, Palette.space2xl)
        }
    }

    /// Счётчик в шапке. При пустом списке его нет: «0 записей» рядом
    /// с сообщением «здесь появятся расшифровки» — это второй раз одно и то же.
    private var counter: AnyView? {
        guard !store.isEmpty else { return nil }
        return AnyView(
            Text(countTitle(store.items.count))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        )
    }

    private var showsSearch: Bool { store.items.count > 10 }

    private var visible: [TranscriptionRecord] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        // Поле поиска могло исчезнуть вместе с одиннадцатой записью: фильтровать
        // список запросом, который человеку уже негде стереть, нельзя.
        guard showsSearch, !needle.isEmpty else { return store.items }
        return store.items.filter {
            $0.text.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    @ViewBuilder
    private var list: some View {
        if store.isEmpty {
            emptyState(
                symbol: SettingsSection.history.symbol,
                text: "Здесь появятся последние расшифровки"
            )
        } else if visible.isEmpty {
            emptyState(symbol: "magnifyingglass", text: "Ничего не нашлось")
        } else {
            VStack(spacing: 0) {
                ForEach(Array(visible.enumerated()), id: \.element.id) { index, record in
                    // Волосок между строками, но не над первой и не под последней:
                    // карточка уже отделена от списка своим разделителем.
                    if index > 0 {
                        // Строка истории отступает на 8 сама, инсет складывается.
                        CardDivider(inset: 20, spacing: 0)
                    }
                    row(record)
                }
            }
        }
    }

    private func row(_ record: TranscriptionRecord) -> some View {
        HistoryRow(
            text: record.text,
            time: Self.timeTitle(record.date),
            duration: Self.durationTitle(record.audioDuration),
            onCopy: { store.copy(record) },
            onInsertAgain: { store.insertAgain(record) }
        )
        // Дубль действий строки: афорданс, живущий только под курсором,
        // запрещён (`ia.md` §1.3). Кнопки в строке под удаление нет намеренно —
        // промахнуться мимо «скопировать» и стереть запись не должно быть легко.
        //
        // Оговорка: `HistoryRow` объявляет собственное контекстное меню внутри
        // себя, и вложенные меню SwiftUI разрешает в пользу внутреннего. Пока
        // в `DesignSystem` у строки не появится `onRemove`, это меню может
        // оставаться в тени — правка чужого файла в границы слайса не входит.
        .contextMenu {
            Button("Скопировать") { store.copy(record) }
            Button("Вставить снова") { store.insertAgain(record) }
            Divider()
            Button("Удалить") { store.remove(record) }
        }
    }

    private func emptyState(symbol: String, text: String) -> some View {
        HStack(spacing: Palette.spaceXs) {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .symbolRenderingMode(.hierarchical)
            Text(text)
                .font(.body)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, Palette.spaceXs)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)

            TextField("Поиск по расшифровкам", text: $query)
                .textFieldStyle(.plain)
                .font(.body)

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Очистить поиск")
            }
        }
        .padding(.leading, Palette.spaceXs)
        .padding(.trailing, 3)
        .frame(height: Palette.capsuleHeight)
        .background(
            RoundedRectangle(cornerRadius: Palette.radiusField, style: .continuous)
                .fill(Palette.surfaceField)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Palette.radiusField, style: .continuous)
                .strokeBorder(Palette.fieldBorder, lineWidth: 1)
        )
    }

    // MARK: - Хранение

    private var storageCard: some View {
        GlassCard("Хранение", separated: true) {
            CardDivider()

            // Подсказка — описанием под своим контролом: она объясняет
            // невидимое последствие (что происходит с файлом), а не пересказывает
            // название переключателя.
            SwitchToggle(
                "Хранить историю",
                subtitle: "Выключишь — файл с расшифровками удалится с диска",
                isOn: $store.isStoringEnabled
            )
        }
    }

    // MARK: - Форматирование

    /// Форматтеры статические: строка списка перерисовывается на каждое
    /// наведение, а создание `DateFormatter` — заметно дорогая операция.
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.setLocalizedDateFormatFromTemplate("HHmm")
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.setLocalizedDateFormatFromTemplate("dMMM")
        return formatter
    }()

    /// Зона меты в строке — 56pt, поэтому дата коротка по построению:
    /// сегодня — время, вчера — словом, дальше — число и месяц.
    private static func timeTitle(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return timeFormatter.string(from: date) }
        if calendar.isDateInYesterday(date) { return "вчера" }
        return dayFormatter.string(from: date)
    }

    private static func durationTitle(_ seconds: TimeInterval) -> String? {
        guard seconds >= 1 else { return nil }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func countTitle(_ count: Int) -> String {
        let hundreds = count % 100
        let units = count % 10

        let word: String
        if (11...14).contains(hundreds) {
            word = "записей"
        } else if units == 1 {
            word = "запись"
        } else if (2...4).contains(units) {
            word = "записи"
        } else {
            word = "записей"
        }

        return "\(count) \(word)"
    }
}
