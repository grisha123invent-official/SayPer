import AppKit
import SwiftUI

/// Обёртка над NSWindow, чтобы окно жило независимо от меню.
final class SettingsWindowController {
    private var window: NSWindow?
    let model = SettingsModel()

    func show() {
        show(defaultSection())
    }

    /// Открыть окно сразу на нужном разделе — так работают пункты меню.
    func show(_ section: SettingsSection) {
        model.refreshPermissions()
        model.section = section

        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let size = NSSize(width: 820, height: 486)
        let hosting = NSHostingController(rootView: SettingsRootView(model: model))

        // Стеклянная подложка кладётся в contentView окна — иначе окно
        // остаётся просто прозрачным и фон «пропадает».
        let glass = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        glass.material = .underWindowBackground
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.autoresizingMask = [.width, .height]

        hosting.view.frame = glass.bounds
        hosting.view.autoresizingMask = [.width, .height]
        glass.addSubview(hosting.view)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentView = glass
        window.title = "Надиктовка — настройки"
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Пока нечем работать — открываем там, где это чинится.
    private func defaultSection() -> SettingsSection {
        if Settings.shared.apiKey == nil || !HotkeyMonitor.isTrusted {
            return .system
        }
        return model.section
    }
}
