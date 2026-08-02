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
                HStack(spacing: Palette.spaceXs) {
                    HotkeyRecorder(hotkey: $model.hotkey)
                        .frame(width: 190, height: 28)

                    // Сброс показывается, только когда есть что сбрасывать.
                    // Держать его под курсором нельзя: афорданс, живущий
                    // только в наведении, для клавиатуры не существует.
                    if model.hotkey != .rightOptionOnly {
                        Button {
                            model.hotkey = .rightOptionOnly
                        } label: {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.system(size: 12))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(.secondary)
                                .frame(width: 20, height: 20)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Вернуть правый ⌥")
                    }
                }
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
