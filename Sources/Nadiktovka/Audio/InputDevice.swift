import CoreAudio
import Foundation

/// Выбор микрофона для записи.
///
/// Приложение больше не берёт «системный по умолчанию» вслепую. Причина —
/// беспроводные наушники: пока они просто подключены к маку, а звук идёт
/// с телефона, они всё равно числятся микрофоном по умолчанию. Стоит открыть
/// на них вход, как они уходят в режим гарнитуры, отбираются у телефона,
/// и музыка обрывается. Человек хотел продиктовать, а не переключать наушники.
struct InputDevice: Identifiable, Equatable {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let transport: UInt32

    var isBluetooth: Bool {
        transport == kAudioDeviceTransportTypeBluetooth
            || transport == kAudioDeviceTransportTypeBluetoothLE
    }

    var isBuiltIn: Bool { transport == kAudioDeviceTransportTypeBuiltIn }

    /// Одни и те же наушники macOS показывает двумя устройствами: UID у них
    /// `54-2A-43-4D-CB-55:input` и `…:output`. Чтобы понять, что микрофон
    /// и колонки — это одна гарнитура, сравнивать надо часть до двоеточия.
    var hardwareID: String {
        uid.split(separator: ":").first.map(String.init) ?? uid
    }

    /// Микрофон айфона через «Непрерывность». Тоже отбирает звук у телефона,
    /// и тоже не то, чего ждут от диктовки на маке.
    var isContinuity: Bool {
        transport == kAudioDeviceTransportTypeContinuityCapture
            || transport == kAudioDeviceTransportTypeContinuityCaptureWired
            || transport == kAudioDeviceTransportTypeContinuityCaptureWireless
    }
}

enum AudioDevices {
    // MARK: - Перечисление

    static func inputs() -> [InputDevice] {
        all().filter { channels($0, scope: kAudioObjectPropertyScopeInput) > 0 }
            .map(describe)
    }

    static func defaultInput() -> AudioDeviceID? {
        systemDevice(kAudioHardwarePropertyDefaultInputDevice)
    }

    static func defaultOutput() -> AudioDeviceID? {
        systemDevice(kAudioHardwarePropertyDefaultOutputDevice)
    }

    /// Выводит ли мак звук через это устройство прямо сейчас.
    ///
    /// Именно `DeviceIsRunning`, а не `DeviceIsRunningSomewhere`. Второй флаг
    /// проверялся первым и оказался бесполезен: он единица, если устройство
    /// у кого-то просто открыто. На живом маке его держала вкладка браузера,
    /// ничего не проигрывая, — и приложение считало, что человек слушает мак,
    /// хотя музыка шла с телефона. Замерено: при музыке с телефона
    /// `RunningSomewhere` = 1, а `IsRunning` = 0.
    static func isRunning(_ id: AudioDeviceID) -> Bool {
        value(id, address(kAudioDevicePropertyDeviceIsRunning), UInt32(0)) == 1
    }

    static func builtInInput() -> InputDevice? {
        inputs().first(where: \.isBuiltIn)
    }

    static func outputs() -> [InputDevice] {
        all().filter { channels($0, scope: kAudioObjectPropertyScopeOutput) > 0 }
            .map(describe)
    }

    static func builtInOutput() -> InputDevice? {
        outputs().first(where: \.isBuiltIn)
    }

    /// Куда проигрывать короткие сигналы приложения.
    ///
    /// `nil` — туда же, куда и всё остальное. Иначе — встроенные динамики:
    /// это случай, когда вывод по умолчанию стоит на беспроводных наушниках,
    /// а мак через них молчит. Любой звук, отправленный в такие наушники,
    /// будит их и отбирает у телефона — ровно то же, что делает микрофон.
    static func soundOutput() -> InputDevice? {
        guard let id = defaultOutput() else { return nil }
        let device = describe(id)
        guard device.isBluetooth, !isRunning(id) else { return nil }
        return builtInOutput()
    }

    // MARK: - Решение

    /// Какой микрофон брать под текущую настройку.
    /// `nil` — оставить системный по умолчанию, ничего не переопределять.
    static func resolve(_ mode: MicrophoneMode) -> InputDevice? {
        let list = inputs()

        switch mode {
        case .systemDefault:
            return nil

        case .builtIn:
            return list.first(where: \.isBuiltIn)

        case .specific(let uid):
            // Устройство могли отключить — тогда молча возвращаемся к системному,
            // это лучше, чем отказаться записывать.
            return list.first { $0.uid == uid }

        case .smart:
            guard let currentID = defaultInput(),
                  let current = list.first(where: { $0.id == currentID }) else { return nil }

            // Проводное, встроенное, USB — берём как есть: у них нет второго
            // хозяина, отбирать их не у кого.
            guard current.isBluetooth || current.isContinuity else { return nil }

            // Наушники берём только если человек и правда слушает через них мак:
            // они же стоят выходом по умолчанию, и через этот выход прямо сейчас
            // идёт звук. Если играет телефон, а мак просто подключён к тем же
            // наушникам, — это не наш случай, трогать их нельзя.
            if current.isBluetooth, let output = defaultOutput(),
               describe(output).hardwareID == current.hardwareID, isRunning(output) {
                return current
            }

            return list.first(where: \.isBuiltIn) ?? nil
        }
    }

    /// Что именно решил `resolve`, словами — для журнала и диагностики.
    ///
    /// Пишется вместе с состоянием вывода: если решение окажется неверным,
    /// по журналу сразу видно, на чём оно основано, и гадать не придётся.
    static func explain(_ mode: MicrophoneMode) -> String {
        let chosen = resolve(mode)
        let system = defaultInput().map { describe($0).name } ?? "неизвестно"
        var note = ""
        if let out = defaultOutput() {
            note = "; вывод — \(describe(out).name), "
                 + (isRunning(out) ? "мак через него играет" : "мак через него молчит")
        }
        guard let chosen else { return "системный по умолчанию (\(system))\(note)" }
        return "\(chosen.name) (системный — \(system))\(note)"
    }

    // MARK: - CoreAudio

    private static func address(
        _ selector: AudioObjectPropertySelector,
        _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain
        )
    }

    private static func value<T>(_ id: AudioObjectID, _ addr: AudioObjectPropertyAddress, _ fallback: T) -> T {
        var addr = addr
        var size = UInt32(MemoryLayout<T>.size)
        var out = fallback
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &out) == noErr else { return fallback }
        return out
    }

    private static func string(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String {
        var addr = address(selector)
        var size = UInt32(MemoryLayout<CFString?>.size)
        var out: CFString?
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &out) == noErr else { return "" }
        return out as String? ?? ""
    }

    private static func systemDevice(_ selector: AudioObjectPropertySelector) -> AudioDeviceID? {
        let id: AudioDeviceID = value(
            AudioObjectID(kAudioObjectSystemObject), address(selector), kAudioObjectUnknown
        )
        return id == kAudioObjectUnknown ? nil : id
    }

    private static func all() -> [AudioDeviceID] {
        var addr = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size
        ) == noErr else { return [] }

        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids
        ) == noErr else { return [] }
        return ids
    }

    private static func channels(_ id: AudioDeviceID, scope: AudioObjectPropertyScope) -> Int {
        var addr = address(kAudioDevicePropertyStreamConfiguration, scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr, size > 0 else { return 0 }

        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 16)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, raw) == noErr else { return 0 }

        let list = raw.assumingMemoryBound(to: AudioBufferList.self)
        return UnsafeMutableAudioBufferListPointer(list).reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func describe(_ id: AudioDeviceID) -> InputDevice {
        InputDevice(
            id: id,
            uid: string(id, kAudioDevicePropertyDeviceUID),
            name: string(id, kAudioObjectPropertyName),
            transport: value(id, address(kAudioDevicePropertyTransportType), UInt32(0))
        )
    }
}

/// Откуда брать звук.
enum MicrophoneMode: Equatable {
    /// Не переключаться на беспроводные наушники, пока человек не слушает
    /// через них сам мак. Всё остальное — как в системе.
    case smart
    /// Всегда встроенный микрофон.
    case builtIn
    /// Как в системных настройках звука.
    case systemDefault
    /// Конкретное устройство по его UID.
    case specific(String)
}

extension Settings {
    /// Ключ `audio.micMode`; для `specific` рядом лежит `audio.micDevice`.
    var microphoneMode: MicrophoneMode {
        get {
            switch text("audio.micMode", default: "smart") {
            case "builtIn": return .builtIn
            case "system": return .systemDefault
            case "specific":
                let uid = text("audio.micDevice")
                return uid.isEmpty ? .smart : .specific(uid)
            default: return .smart
            }
        }
        set {
            switch newValue {
            case .smart: set("smart", forKey: "audio.micMode")
            case .builtIn: set("builtIn", forKey: "audio.micMode")
            case .systemDefault: set("system", forKey: "audio.micMode")
            case .specific(let uid):
                set("specific", forKey: "audio.micMode")
                set(uid, forKey: "audio.micDevice")
            }
        }
    }
}
