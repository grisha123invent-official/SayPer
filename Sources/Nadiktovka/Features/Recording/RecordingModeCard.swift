import SwiftUI

/// Карточка «Режим» в разделе «Запись».
///
/// Заготовка: режим сегодня один, поэтому карточка только объясняет, как
/// работает удержание. Сегменты «Удержание / Нажал-нажал» и авто-стоп
/// добавляет слайс «Нажал-нажал» — вызов `RecordingModeCard()` из раздела
/// при этом не меняется.
struct RecordingModeCard: View {
    private let mode: HotkeyActivation = .hold

    var body: some View {
        GlassCard("Режим") {
            SettingRow(mode.title, subtitle: mode.summary) {
                EmptyView()
            }
        }
    }
}
