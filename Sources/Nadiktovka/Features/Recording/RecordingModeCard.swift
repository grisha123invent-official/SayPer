import Combine
import SwiftUI

/// Карточка «Режим» в разделе «Запись».
///
/// Сегменты, а не переключатель: удержание и «нажал-нажал» — два равноправных
/// способа, а не включение опции (`ia.md` §1.1). Описание под сегментами меняется
/// вместе с выбором — так «чем они отличаются» читается там же, где выбирают,
/// и отдельная подсказка не нужна.
///
/// Своей модели у карточки нет: вызов `RecordingModeCard()` из раздела зафиксирован
/// в подготовке, поэтому значения она берёт и пишет прямо в `Settings`. Шлюз
/// подхватывает их сам, перезапуск не нужен.
struct RecordingModeCard: View {
    @State private var mode: HotkeyActivation = Settings.shared.hotkeyActivation
    @State private var autoStop: AutoStopLimit = Settings.shared.autoStopLimit

    var body: some View {
        GlassCard("Режим", separated: true) {
            CardDivider()

            SettingRow("Активация", subtitle: mode.summary) {
                SegmentedControl(selection: $mode) { $0.title }
            }

            // В удержании авто-стоп бессмыслен: запись живёт ровно столько,
            // сколько нажата клавиша. Показывать выключенную строку «на всякий
            // случай» — значит спрашивать про то, чего в этом режиме не бывает.
            if mode == .toggle {
                CardDivider()

                SettingRow(
                    "Автостоп",
                    subtitle: "Если про запись забыли, она закончится и расшифруется сама"
                ) {
                    Picker("", selection: $autoStop) {
                        ForEach(AutoStopLimit.allCases) { limit in
                            Text(limit.title).tag(limit)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 140)
                }
            }
        }
        .onChange(of: mode) { newValue in
            Settings.shared.hotkeyActivation = newValue
        }
        .onChange(of: autoStop) { newValue in
            Settings.shared.autoStopLimit = newValue
        }
        // Режим меняют и из меню в строке статуса — при открытом окне сегменты
        // обязаны сдвинуться сами, иначе окно показывает вчерашнюю правду.
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            syncFromSettings()
        }
    }

    /// Сверка с настройками. Присваиваем только отличающееся: иначе `onChange`
    /// запишет то же самое обратно и мы получим круг «запись — уведомление — запись».
    private func syncFromSettings() {
        let storedMode = Settings.shared.hotkeyActivation
        if storedMode != mode { mode = storedMode }

        let storedLimit = Settings.shared.autoStopLimit
        if storedLimit != autoStop { autoStop = storedLimit }
    }
}
