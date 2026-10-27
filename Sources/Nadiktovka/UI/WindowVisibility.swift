import AppKit
import SwiftUI

/// Видно ли на экране окно, в котором лежит вид.
///
/// Окна приложения создаются один раз и живут всё время работы: пилюля,
/// панель строки меню и окно настроек при закрытии только прячутся.
/// Анимации на `TimelineView` в них этого не замечали и продолжали рисовать
/// кадры в спрятанном окне — по 20–30 раз в секунду, круглосуточно, начиная
/// с первой диктовки. Снято слепком 15 октября: приложение в простое держало
/// около трети ядра, а все его окна были убраны с экрана.
///
/// Видимость берётся из `occlusionState` окна. Оно учитывает разом и
/// спрятанное окно, и свёрнутое, и целиком перекрытое, и погасший экран —
/// во всех этих случаях рисовать незачем.
extension View {
    /// Пишет в `isVisible`, видно ли сейчас окно с этим видом.
    func trackingWindowVisibility(_ isVisible: Binding<Bool>) -> some View {
        background(WindowVisibilityReader(isVisible: isVisible))
    }
}

private struct WindowVisibilityReader: NSViewRepresentable {
    @Binding var isVisible: Bool

    func makeNSView(context: Context) -> VisibilityProbe {
        VisibilityProbe()
    }

    func updateNSView(_ probe: VisibilityProbe, context: Context) {
        probe.onChange = { visible in
            if isVisible != visible { isVisible = visible }
        }
    }
}

/// Пустой вид-зонд: подписывается на смену видимости своего окна.
private final class VisibilityProbe: NSView {
    var onChange: ((Bool) -> Void)?
    private var observer: NSObjectProtocol?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil

        guard let window else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.report()
        }
        report()
    }

    private func report() {
        let visible = window?.occlusionState.contains(.visible) ?? false
        // Отложенно: состояние SwiftUI нельзя менять посреди обновления вида,
        // а первый отчёт приходит как раз из него — при вставке в окно.
        DispatchQueue.main.async { [weak self] in
            self?.onChange?(visible)
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }
}
