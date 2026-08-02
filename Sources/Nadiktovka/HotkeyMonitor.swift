import AppKit
import IOKit.hid

/// Глобально следит за выбранным сочетанием клавиш через CGEventTap.
/// Tap, а не NSEvent-монитор, потому что нажатие обычной клавиши в составе
/// хоткея нужно «съедать», иначе символ улетит в активное поле.
final class HotkeyMonitor {
    var onPress: (() -> Void)?
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

    private var binding: HotkeyBinding = .rightOptionOnly
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
        binding = Settings.shared.hotkey
        installTap()
        startWatchdog()
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
        binding = Settings.shared.hotkey
        resetState()
    }

    private func resetState() {
        currentMask = 0
        pressedKey = nil
        isHeld = false
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
        Log.write("Перехват клавиатуры установлен. Хоткей: \(binding.displayString) "
                  + "(mask=0x\(String(binding.mask, radix: 16)), key=\(binding.keyCode.map(String.init) ?? "нет"))")
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
                if isHeld, binding.keyCode == nil {
                    interrupted = true
                    isHeld = false
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
        if let bound = binding.keyCode, bound == keyCode,
           type == .keyDown || type == .keyUp,
           (currentMask & binding.mask) == binding.mask {
            return nil
        }

        return Unmanaged.passUnretained(event)
    }

    private func updateHeldState() {
        let held = binding.isHeld(currentMask: currentMask, pressedKey: pressedKey)

        if held, !isHeld, !interrupted {
            isHeld = true
            Log.write("Хоткей зажат")
            deliver(onPress)
        } else if !held, isHeld {
            isHeld = false
            Log.write("Хоткей отпущен")
            deliver(onRelease)
        }

        // Все модификаторы отпущены — снимаем блокировку на следующий заход.
        if currentMask == 0 {
            interrupted = false
        }
    }

    /// Колбэки уводим с потока tap: запуск записи слишком тяжёлый,
    /// система отключила бы tap по таймауту.
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
