import SwiftUI

/// Раздел «Запись»: чем включать диктовку и что видно, пока она идёт.
struct SettingsSectionGeneral: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        SectionScaffold {
            activation
            duringRecording
        }
    }

    /// Сочетание и режим — одна тема: чем запускается запись. Раньше они жили
    /// в двух секциях, и граница между ними ничего не значила.
    private var activation: some View {
        GlassCard("Активация") {
            SettingRow(
                "Сочетание",
                subtitle: "Кликни по полю и зажми клавиши. Левые и правые различаются"
            ) {
                // Сброс живёт внутри поля, у правого края с отступом 6
                // (`components.md` §2), и рисует его сам рекордер. Отдельной
                // кнопкой рядом он сдвигал поле на 28pt в момент появления —
                // то есть ровно тогда, когда человек целится в клавиши.
                HotkeyRecorder(hotkey: $model.hotkey)
                    .frame(width: 190, height: 28)
            }

            RecordingModeRow()
        }
    }

    private var duringRecording: some View {
        GlassCard("Во время записи") {
            SwitchToggle("Показывать индикатор", isOn: $model.showIndicator)
            SwitchToggle("Звуковые сигналы", isOn: $model.playSounds)
        }
    }
}
