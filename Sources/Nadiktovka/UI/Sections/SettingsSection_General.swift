import SwiftUI

/// Раздел «Запись»: чем включать диктовку и что видно, пока она идёт.
struct SettingsSectionGeneral: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        SectionScaffold {
            hotkey
            RecordingModeCard()
            duringRecording
        }
    }

    private var hotkey: some View {
        GlassCard("Горячая клавиша") {
            SettingRow("Зажимать") {
                HotkeyRecorder(hotkey: $model.hotkey)
                    .frame(width: 190, height: 26)
            }

            HStack {
                Spacer()
                Button("Сбросить на правый ⌥") { model.hotkey = .rightOptionOnly }
                    .buttonStyle(.link)
                    .font(.caption)
            }

            Hint("Кликни по полю и зажми любое сочетание — хоть один модификатор, "
                 + "хоть ⌃⌥D. Левые и правые клавиши различаются.")

            Hint(model.hotkey.keyCode == nil
                 ? "Нажатая во время удержания обычная клавиша отменяет запись, "
                   + "так что привычные шорткаты не ломаются."
                 : "Пока сочетание назначено, эта клавиша не печатается "
                   + "в других приложениях.")

            Hint("Esc прерывает и запись, и ожидание расшифровки.")
        }
    }

    private var duringRecording: some View {
        GlassCard("Во время записи") {
            SwitchToggle("Показывать индикатор записи", isOn: $model.showIndicator)
            SwitchToggle("Звуковые сигналы", isOn: $model.playSounds)
        }
    }
}
