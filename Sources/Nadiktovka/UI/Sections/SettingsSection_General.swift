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
        GlassCard("Горячая клавиша", separated: true) {
            CardDivider()

            // Подсказка про поле стала описанием под самим полем: отдельным
            // блоком под разделителем она читалась как отдельная мысль,
            // хотя объясняет ровно этот контрол (`ia.md` §3).
            SettingRow(
                "Зажимать",
                subtitle: "Кликни и зажми сочетание. Левые и правые клавиши различаются"
            ) {
                // Сброс живёт внутри поля, у правого края с отступом 6
                // (`components.md` §2), и рисует его сам рекордер. Отдельной
                // кнопкой рядом он сдвигал поле на 28pt в момент появления —
                // то есть ровно тогда, когда человек целится в клавиши.
                HotkeyRecorder(hotkey: $model.hotkey)
                    .frame(width: 190, height: 28)
            }
        }
    }

    private var duringRecording: some View {
        GlassCard("Во время записи", separated: true) {
            CardDivider()
            SwitchToggle("Показывать индикатор", isOn: $model.showIndicator)
            CardDivider()
            SwitchToggle("Звуковые сигналы", isOn: $model.playSounds)
        }
    }
}
