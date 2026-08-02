import AppKit
import SwiftUI

/// Окно мастера первого запуска.
///
/// Устроено как окно настроек: стеклянное шасси, фон-орб под ним, содержимое
/// поверх. Размер фиксированный — шаги свёрстаны под него, тянуть окно не за чем.
@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let model = OnboardingModel()

    /// Вызывается после завершения мастера — и по кнопке, и по закрытию окна.
    var onFinish: (() -> Void)?

    private static let size = NSSize(width: 640, height: 500)

    func show() {
        let window = self.window ?? makeWindow()
        model.startPolling()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        let chassis = NSVisualEffectView()
        chassis.material = .windowBackground
        chassis.blendingMode = .behindWindow
        chassis.state = .followsWindowActiveState
        window.contentView = chassis

        // Тот же орб, что в настройках: первое окно приложения сразу показывает,
        // как оно выглядит, а стеклу панели есть что преломлять.
        let backdrop = NSHostingView(rootView: AmbientGlow())
        let hosting = NSHostingView(rootView: OnboardingView(model: model))
        // Иначе размер окна диктует содержимое: у панели `maxHeight: .infinity`,
        // и как собственный размер вида это превращается в трёхтысячный рост.
        backdrop.sizingOptions = []
        hosting.sizingOptions = []

        for view in [backdrop, hosting] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            chassis.addSubview(view)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: chassis.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: chassis.trailingAnchor),
                view.topAnchor.constraint(equalTo: chassis.topAnchor),
                view.bottomAnchor.constraint(equalTo: chassis.bottomAnchor)
            ])
        }

        window.title = "Добро пожаловать"
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.isReleasedWhenClosed = false
        window.delegate = self
        // Размер задаём после сборки иерархии: содержимое его не диктует.
        window.setContentSize(Self.size)
        window.center()

        model.onFinish = { [weak self] in self?.close() }

        self.window = window
        return window
    }

    private func close() {
        model.stopPolling()
        window?.close()
        window = nil
        onFinish?()
    }

    /// Крестик — это тоже ответ: мастер отмечается пройденным, второй раз
    /// приветствие не покажется. Всё, что он предлагал, есть в настройках.
    func windowWillClose(_ notification: Notification) {
        model.stopPolling()
        guard !Settings.shared.onboardingCompleted else { return }
        Settings.shared.onboardingCompleted = true
        Log.write("Онбординг закрыт крестиком на шаге \(model.step.rawValue + 1)")
        window = nil
        onFinish?()
    }
}
