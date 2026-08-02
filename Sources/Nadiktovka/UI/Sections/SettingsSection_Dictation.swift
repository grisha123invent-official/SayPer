import SwiftUI

/// Раздел «Текст»: что и как приложение распознаёт и куда девает результат.
///
/// Две карточки: «Расшифровка» — всё, что влияет на распознанный текст,
/// «Вставка» — что с ним делают дальше. Словарь отдельной карточки не получает:
/// он подсказка для модели, то есть часть расшифровки.
struct SettingsSectionDictation: View {
    @ObservedObject var model: SettingsModel

    @FocusState private var vocabularyFocused: Bool

    private let languages: [(String, String)] = [
        ("", "Автоопределение"),
        ("ru", "Русский"),
        ("en", "English"),
        ("de", "Deutsch"),
        ("es", "Español"),
        ("fr", "Français")
    ]

    var body: some View {
        SectionScaffold {
            transcription
            insertion
        }
    }

    private var transcription: some View {
        GlassCard("Расшифровка", separated: true) {
            CardDivider()

            SettingRow("Модель") {
                Picker("", selection: $model.model) {
                    ForEach(TranscriptionModel.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .labelsHidden()
                .frame(width: 260)
            }

            CardDivider()

            SettingRow("Язык речи") {
                Picker("", selection: $model.language) {
                    ForEach(languages, id: \.0) { code, title in
                        Text(title).tag(code)
                    }
                }
                .labelsHidden()
                .frame(width: 180)
            }

            CardDivider()
            vocabulary
            CardDivider()

            SwitchToggle(
                "Причёсывать текст",
                subtitle: "Пунктуация и слова-паразиты, +1 секунда · gpt-4o-mini",
                isOn: $model.cleanup
            )
        }
    }

    /// Подпись-заголовок над редактором убрана: что писать, объясняет плейсхолдер
    /// внутри поля — там это видно ровно в тот момент, когда нужно (`ia.md` §3).
    private var vocabulary: some View {
        HStack(alignment: .top, spacing: Palette.spaceSm) {
            Text("Словарь")
                .font(.body)
                .frame(height: Palette.rowHeight, alignment: .center)

            Spacer(minLength: Palette.spaceSm)

            ZStack(alignment: .topLeading) {
                TextEditor(text: $model.vocabulary)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 5)
                    .focused($vocabularyFocused)

                if model.vocabulary.isEmpty {
                    Text("имена и термины через запятую")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: 330, height: 62)
            // Заливка, обводка и фокусное кольцо — одним кирпичиком:
            // `.plain`-редактор системного кольца не рисует (`tokens.md` §11).
            .fieldChrome(isFocused: vocabularyFocused)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var insertion: some View {
        GlassCard("Вставка", separated: true) {
            CardDivider()

            SettingRow("Способ") {
                Picker("", selection: $model.insertMode) {
                    ForEach(InsertMode.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .labelsHidden()
                .frame(width: 300)
            }
        }
    }
}
