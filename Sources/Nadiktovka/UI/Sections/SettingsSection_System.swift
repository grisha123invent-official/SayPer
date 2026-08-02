import AppKit
import SwiftUI

/// Раздел «Ключ и доступ»: то, что настраивают один раз при установке.
struct SettingsSectionSystem: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        SectionScaffold {
            openAI
            keyboardAccess
            system
        }
    }

    private var openAI: some View {
        GlassCard("OpenAI") {
            HStack(spacing: Palette.spaceXs) {
                SecureField("API-ключ (sk-…)", text: $model.apiKey)
                    .textFieldStyle(.roundedBorder)
                Button("Вставить") { model.pasteAPIKey() }
            }

            HStack(spacing: Palette.spaceXs) {
                Button("Проверить ключ") {
                    Task { await model.checkAPIKey() }
                }
                .disabled(model.apiKey.isEmpty || model.isCheckingKey)

                if model.isCheckingKey {
                    ProgressView().controlSize(.small)
                }
                if let result = model.keyCheckResult {
                    Image(systemName: result.isOK
                          ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(result.isOK ? .green : .orange)
                    Text(result.message)
                        .font(.subheadline)
                        .foregroundStyle(result.isOK ? .green : .orange)
                }
                Spacer()
            }

            Hint("Ключ хранится в связке ключей macOS.")
        }
    }

    private var keyboardAccess: some View {
        GlassCard("Доступ к клавиатуре") {
            HStack(spacing: Palette.space2xs + 2) {
                Image(systemName: model.accessibilityGranted
                      ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(model.accessibilityGranted ? .green : .orange)
                Text(model.accessibilityGranted
                     ? "Доступ к клавиатуре выдан"
                     : "Нет доступа к клавиатуре — хоткей не сработает")
                    .font(.subheadline)
                Spacer()
            }

            HStack(spacing: Palette.spaceXs) {
                Button("Открыть настройки доступа") {
                    HotkeyMonitor.requestTrust()
                    NSWorkspace.shared.open(URL(string:
                        "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }
                Button("Проверить") { model.refreshPermissions() }
                Spacer()
            }
        }
    }

    private var system: some View {
        GlassCard("Система") {
            SwitchToggle("Запускать при входе в систему", isOn: $model.launchAtLogin)
            if let error = model.launchError {
                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
