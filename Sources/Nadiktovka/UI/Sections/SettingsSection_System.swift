import AppKit
import SwiftUI

/// Раздел «Ключ и доступ»: то, что настраивают один раз при установке.
struct SettingsSectionSystem: View {
    @ObservedObject var model: SettingsModel

    @FocusState private var keyFieldFocused: Bool

    var body: some View {
        SectionScaffold {
            openAI
            keyboardAccess
            system
        }
    }

    private var openAI: some View {
        GlassCard("OpenAI") {

            HStack(spacing: Palette.spaceSm) {
                Text("API-ключ")
                    .font(.body)
                    .frame(width: 96, alignment: .leading)
                keyField
            }
            .frame(minHeight: Palette.rowHeight)

            HStack(spacing: Palette.spaceSm) {
                CapsuleButton(
                    "Проверить ключ",
                    kind: .accent,
                    isLoading: model.isCheckingKey
                ) {
                    Task { await model.checkAPIKey() }
                }
                .disabled(model.apiKey.isEmpty)

                if let result = model.keyCheckResult {
                    // Результат — иконкой и текстом рядом с кнопкой, без всплывающих
                    // сообщений: цвет здесь не единственный носитель смысла.
                    HStack(spacing: 5) {
                        Image(systemName: result.isOK
                              ? "checkmark.circle.fill"
                              : "exclamationmark.triangle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(result.isOK ? Palette.success : Palette.warning)
                        Text(result.message)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)
            }
            .frame(minHeight: Palette.rowHeight)

            // Единственная подсказка в разделе: про хранение ключа из контрола
            // не догадаешься, а это вопрос безопасности.
            Hint("Ключ хранится в связке ключей macOS")
        }
    }

    private var keyField: some View {
        HStack(spacing: 6) {
            SecureField("sk-…", text: $model.apiKey)
                .textFieldStyle(.plain)
                .font(.system(size: 13).monospaced())
                .focused($keyFieldFocused)

            Button {
                model.pasteAPIKey()
            } label: {
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 13))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Вставить из буфера")
        }
        .padding(.leading, Palette.spaceXs)
        // 3, а не 6: у кнопки зона нажатия 20pt вокруг глифа 13pt, и правый
        // край глифа встаёт ровно на 6 от края поля, как `.field .icon` в мокапе.
        .padding(.trailing, 3)
        .frame(height: Palette.capsuleHeight)
        .fieldChrome(isFocused: keyFieldFocused)
    }

    private var keyboardAccess: some View {
        GlassCard("Доступ к клавиатуре") {
            HStack(spacing: Palette.spaceSm) {
                HStack(spacing: 7) {
                    Image(systemName: model.accessibilityGranted
                          ? "checkmark.circle.fill"
                          : "exclamationmark.triangle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(model.accessibilityGranted
                                         ? Palette.success : Palette.warning)
                    Text(model.accessibilityGranted
                         ? "Доступ выдан — хоткей работает"
                         : "Доступа нет — хоткей не сработает")
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: Palette.spaceSm)

                // При выданном доступе проверять нечего — кнопки нет.
                if !model.accessibilityGranted {
                    CapsuleButton("Проверить") { model.refreshPermissions() }
                }
                CapsuleButton("Открыть настройки доступа") { KeyboardAccess.request(model) }
            }
            .frame(minHeight: Palette.rowHeight)

            // Диагностика переехала сюда из панели строки меню: нужна она
            // только когда что-то не работает, а искать её будут рядом
            // с разрешениями — здесь же видно их состояние.
            SettingRow(
                "Диагностика",
                subtitle: "Состояние доступов, микрофона и ключа плюс путь к журналу"
            ) {
                CapsuleButton("Показать") {
                    NotificationCenter.default.post(name: .showDiagnostics, object: nil)
                }
            }
        }
    }

    private var system: some View {
        GlassCard("Система") {
            SwitchToggle("Запускать при входе в систему", isOn: $model.launchAtLogin)

            // Текст ошибки появляется только тогда, когда ошибка есть.
            if let error = model.launchError {
                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(Palette.warning)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
