import Combine
import SwiftUI

/// Строка «Режим» в секции «Активация» раздела «Запись».
///
/// Сегменты, а не переключатель: удержание и «нажал-нажал» — два равноправных
/// способа, а не включение опции (`ia.md` §1.1). Описание под сегментами меняется
/// вместе с выбором — так «чем они отличаются» читается там же, где выбирают,
/// и отдельная подсказка не нужна.
///
/// Своей модели у карточки нет: вызов `RecordingModeCard()` из раздела зафиксирован
/// в подготовке, поэтому значения она берёт и пишет прямо в `Settings`. Шлюз
/// подхватывает их сам, перезапуск не нужен.
/// Авто-стоп своей строки в карточке не получил: `ia.md` §1.1 и `settings.html`
/// описывают «Режим» ровно как сегменты плюс одну строку описания, и ни одна
/// карточка в эталоне не меняет высоту при переключении сегментов. Предел живёт
/// в `Settings+Recording` со значением по умолчанию в пять минут — это страховка
/// от забытой записи (`plan.md` §5), а не настройка, которую ходят крутить.
struct RecordingModeRow: View {
    @State private var mode: HotkeyActivation = Settings.shared.hotkeyActivation

    var body: some View {
        SettingRow("Режим", subtitle: mode.summary) {
            SegmentedControl(selection: $mode) { $0.title }
        }
        .onChange(of: mode) { _, newValue in
            Settings.shared.hotkeyActivation = newValue
        }
        // Режим меняют и из меню в строке статуса — при открытом окне сегменты
        // обязаны сдвинуться сами, иначе окно показывает вчерашнюю правду.
        //
        // `.receive(on:)` обязателен: уведомление приходит на потоке того, кто
        // записал настройку, а `syncFromSettings()` меняет состояние SwiftUI —
        // это можно делать только с главного потока.
        .onReceive(
            NotificationCenter.default
                .publisher(for: UserDefaults.didChangeNotification)
                .receive(on: RunLoop.main)
        ) { _ in
            syncFromSettings()
        }
    }

    /// Сверка с настройками. Присваиваем только отличающееся: иначе `onChange`
    /// запишет то же самое обратно и мы получим круг «запись — уведомление — запись».
    private func syncFromSettings() {
        let storedMode = Settings.shared.hotkeyActivation
        if storedMode != mode { mode = storedMode }
    }
}
