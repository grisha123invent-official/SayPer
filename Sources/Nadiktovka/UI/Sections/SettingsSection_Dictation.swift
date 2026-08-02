import SwiftUI

/// Раздел «Текст»: что и как приложение распознаёт и куда девает результат.
struct SettingsSectionDictation: View {
    @ObservedObject var model: SettingsModel

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
            vocabulary
            insertion
        }
    }

    private var transcription: some View {
        GlassCard("Расшифровка") {
            Picker("Модель", selection: $model.model) {
                ForEach(TranscriptionModel.allCases) { item in
                    Text(item.title).tag(item)
                }
            }

            Picker("Язык речи", selection: $model.language) {
                ForEach(languages, id: \.0) { code, title in
                    Text(title).tag(code)
                }
            }

            SwitchToggle("Причёсывать текст через gpt-4o-mini",
                         subtitle: "Расставит пунктуацию и уберёт слова-паразиты. Добавляет ~1 секунду.",
                         isOn: $model.cleanup)
        }
    }

    private var vocabulary: some View {
        GlassCard("Словарь") {
            TextEditor(text: $model.vocabulary)
                .frame(height: 60)
                .font(.system(size: 12))
                .scrollContentBackground(.hidden)
                .padding(Palette.space2xs)
                .background(Palette.surfaceTile)
                .clipShape(RoundedRectangle(cornerRadius: Palette.radiusField, style: .continuous))

            Hint("Имена, термины и названия через запятую — их модель начинает узнавать.")
        }
    }

    private var insertion: some View {
        GlassCard("Вставка") {
            Picker("Способ", selection: $model.insertMode) {
                ForEach(InsertMode.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
        }
    }
}
