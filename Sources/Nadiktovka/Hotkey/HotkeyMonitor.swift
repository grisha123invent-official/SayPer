import AppKit
import IOKit.hid

/// Глобально следит за выбранным сочетанием клавиш через CGEventTap.
/// Tap, а не NSEvent-монитор, потому что нажатие обычной клавиши в составе
/// хоткея нужно «съедать», иначе символ улетит в активное поле.
final class HotkeyMonitor {
    /// Сработало сочетание. Аргумент — тег устройства из привязки: в режиме
    /// «клавиша на устройство» именно он решает, с какого микрофона писать.
    /// `nil` — устройство определяется обычным порядком.
    var onPress: ((String?) -> Void)?
    var onRelease: (() -> Void)?
    var onCancel: (() -> Void)?
    /// Esc — универсальная отмена: прерывает и запись, и ожидание расшифровки.
    var onEscape: (() -> Void)?
    /// Не удалось создать tap — почти всегда это отсутствие «Универсального доступа».
    var onSetupFailed: (() -> Void)?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// Удалось ли поставить перехват клавиатуры.
    private(set) var isActive = false

    /// Все сочетания, за которыми следим. В обычном режиме оно одно.
    private var routes: [HotkeyRoute] = []
    /// Какое сочетание держат прямо сейчас.
    private var heldRoute: HotkeyRoute?
    /// Отложенный старт для сочетания, которое является частью другого:
    /// ⌃ нельзя отличить от начала ⌃⇧ иначе как подождав.
    private var pendingStart: DispatchWorkItem?
    private var currentMask: UInt = 0
    private var pressedKey: UInt16?
    private var isHeld = false
    /// Для хоткеев из одних модификаторов: во время удержания нажали обычную
    /// клавишу — значит это шорткат, а не диктовка.
    private var interrupted = false
    /// На время записи нового сочетания перехват выключается.
    private var isSuspended = false

    func suspend() {
        guard !isSuspended else { return }
        if isHeld {
            isHeld = false
            deliver(onCancel)
        }
        resetState()
        isSuspended = true
    }

    func resume() {
        guard isSuspended else { return }
        isSuspended = false
        resetState()
    }

    /// Сообщает, что перехват поднялся сам, без перезапуска приложения.
    var onBecameActive: (() -> Void)?

    private var watchdog: Timer?

    func start() {
        routes = Self.currentRoutes()
        installTap()
        startWatchdog()
    }

    /// Сочетания из настроек: либо одно основное, либо таблица привязок.
    private static func currentRoutes() -> [HotkeyRoute] {
        switch Settings.shared.micRouting {
        case .panel:
            return [HotkeyRoute(binding: Settings.shared.hotkey, deviceTag: "")]
        case .perHotkey:
            return Settings.shared.hotkeyRoutes.filter { $0.binding.isValid }
        }
    }

    /// Разрешение можно выдать при уже запущенном приложении — тогда перехват
    /// надо поднять самим, иначе пришлось бы перезапускаться вручную.
    private func startWatchdog() {
        watchdog?.invalidate()
        watchdog = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self, !self.isActive, Self.isTrusted else { return }

            Log.write("Разрешение появилось — поднимаю перехват на ходу")
            self.installTap()
            if self.isActive {
                self.onBecameActive?()
            }
        }
    }

    func stopWatchdog() {
        watchdog?.invalidate()
        watchdog = nil
    }

    func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        runLoopSource = nil
        tap = nil
        resetState()
    }

    /// Перечитать хоткей из настроек.
    func reload() {
        if isHeld {
            isHeld = false
            deliver(onRelease)
        }
        routes = Self.currentRoutes()
        resetState()
        Log.write("Сочетания перечитаны: " + routes.map { $0.binding.displayString }
            .joined(separator: ", "))
    }

    private func resetState() {
        pendingStart?.cancel()
        pendingStart = nil
        currentMask = 0
        pressedKey = nil
        isHeld = false
        heldRoute = nil
        interrupted = false
    }

    private func installTap() {
        stop()

        let mask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
                return monitor.handle(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            isActive = false
            Log.write("ОШИБКА: не удалось создать перехват клавиатуры. "
                      + "AXIsProcessTrusted=\(AXIsProcessTrusted())")
            onSetupFailed?()
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.tap = tap
        self.runLoopSource = source
        isActive = true
        Log.write("Перехват клавиатуры установлен. Сочетания: "
                  + routes.map { "\($0.binding.displayString)"
                      + ($0.deviceTag.isEmpty ? "" : " → \($0.deviceTag)") }
                      .joined(separator: ", "))
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Систему не устраивает медленный tap — она его отключает, включаем обратно.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        guard !isSuspended else { return Unmanaged.passUnretained(event) }

        currentMask = UInt(event.flags.rawValue) & ModifierBit.all

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0

        switch type {
        case .keyDown:
            if !isRepeat {
                if keyCode == 53 {
                    deliver(onEscape)
                }
                pressedKey = keyCode
                // Хоткей без обычной клавиши + нажатие буквы = обычный шорткат.
                if isHeld, heldRoute?.keyCode == nil {
                    interrupted = true
                    isHeld = false
                    heldRoute = nil
                    deliver(onCancel)
                }
            }
        case .keyUp:
            if pressedKey == keyCode { pressedKey = nil }
        default:
            break
        }

        updateHeldState()

        // Клавишу, входящую в хоткей, дальше не пропускаем.
        if type == .keyDown || type == .keyUp,
           routes.contains(where: { route in
               route.keyCode == keyCode && (currentMask & route.mask) == route.mask
           }) {
            return nil
        }

        return Unmanaged.passUnretained(event)
    }

    private func updateHeldState() {
        let match = bestMatch()

        if let match, !isHeld, !interrupted {
            start(match)
        } else if match == nil, isHeld {
            pendingStart?.cancel()
            pendingStart = nil
            isHeld = false
            heldRoute = nil
            Log.write("Хоткей отпущен")
            deliver(onRelease)
        } else if let match, isHeld, let held = heldRoute, match != held, pendingStart != nil {
            // Пока ждали, зажали более точное сочетание — берём его.
            start(match)
        }

        // Все модификаторы отпущены — снимаем блокировку на следующий заход.
        if currentMask == 0 {
            interrupted = false
        }
    }

    /// Самое точное из подходящих сочетаний.
    ///
    /// ⌃⇧ удовлетворяет и привязке на ⌃, и привязке на ⌃⇧ — брать надо вторую,
    /// иначе более длинное сочетание не сработает никогда. Точнее то, у кого
    /// есть обычная клавиша, а при равенстве — у кого больше модификаторов.
    private func bestMatch() -> HotkeyRoute? {
        routes
            .filter { $0.binding.isHeld(currentMask: currentMask, pressedKey: pressedKey) }
            .max { a, b in
                let aScore = (a.keyCode != nil ? 100 : 0) + a.mask.nonzeroBitCount
                let bScore = (b.keyCode != nil ? 100 : 0) + b.mask.nonzeroBitCount
                return aScore < bScore
            }
    }

    /// Начинает запись по сочетанию — сразу или с задержкой.
    ///
    /// Задержка нужна только там, где сочетание является частью другого:
    /// ⌃ и ⌃⇧ физически нельзя нажать одновременно, ⌃ приходит первым,
    /// и без паузы длинное сочетание никогда бы не дождалось своей очереди.
    /// Во всех остальных случаях старт мгновенный.
    private func start(_ route: HotkeyRoute) {
        pendingStart?.cancel()
        pendingStart = nil

        guard isPrefixOfAnother(route) else {
            fire(route)
            return
        }

        let work = DispatchWorkItem { [weak self] in
            guard let self, self.pendingStart != nil else { return }
            self.pendingStart = nil
            self.fire(route)
        }
        pendingStart = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: work)
    }

    private func fire(_ route: HotkeyRoute) {
        isHeld = true
        heldRoute = route
        Log.write("Хоткей зажат: \(route.binding.displayString)"
                  + (route.deviceTag.isEmpty ? "" : " → \(route.deviceTag)"))
        let tag: String? = Settings.shared.micRouting == .perHotkey ? route.deviceTag : nil
        if let onPress {
            DispatchQueue.main.async { onPress(tag) }
        }
    }

    /// Есть ли сочетание, которое включает это как часть себя.
    private func isPrefixOfAnother(_ route: HotkeyRoute) -> Bool {
        routes.contains { other in
            guard other != route else { return false }
            guard (other.mask & route.mask) == route.mask else { return false }
            return other.mask != route.mask || (route.keyCode == nil && other.keyCode != nil)
        }
    }

    private func deliver(_ action: (() -> Void)?) {
        guard let action else { return }
        DispatchQueue.main.async(execute: action)
    }

    // MARK: - Разрешения

    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    static func requestTrust() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// «Мониторинг ввода» — отдельное от «Универсального доступа» разрешение,
    /// без него перехват клавиатуры на свежих macOS тоже не поднимается.
    static var inputMonitoringStatus: String {
        switch IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) {
        case kIOHIDAccessTypeGranted: return "выдан"
        case kIOHIDAccessTypeDenied: return "ЗАПРЕЩЁН"
        default: return "ещё не спрашивали"
        }
    }

    static var hasInputMonitoring: Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    @discardableResult
    static func requestInputMonitoring() -> Bool {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }
}
