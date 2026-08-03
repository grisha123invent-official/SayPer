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

    /// Настоящее железо, а не программная прослойка.
    var isRealHardware: Bool {
        transport != kAudioDeviceTransportTypeVirtual
            && transport != kAudioDeviceTransportTypeAggregate
            && transport != kAudioDeviceTransportTypeUnknown
    }

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

    /// Микрофоны, из которых человек выбирает.
    ///
    /// Пока ровно два вида: беспроводная гарнитура и встроенный микрофон.
    /// Остальное отсеяно намеренно — микрофон айфона через «Непрерывность»,
    /// USB-микрофоны, виртуальные устройства Zoom и Teams, служебные агрегаты
    /// системы. Их поведение ещё не обговорено, а пустой выбор в списке
    /// путает и ломает правила приглушения.
    static func inputs() -> [InputDevice] {
        all().filter { channels($0, scope: kAudioObjectPropertyScopeInput) > 0 }
            .map(describe)
            .filter { $0.isBuiltIn || $0.isBluetooth }
    }

    /// Есть ли рядом беспроводная гарнитура — хоть подключённая, хоть просто
    /// видимая системе.
    static func hasWirelessInput() -> Bool {
        inputs().contains(where: \.isBluetooth)
    }

    /// Можно ли трогать устройство вывода — и громкостью, и своими звуками.
    ///
    /// Правила обговорены 3 августа и записаны в CLAUDE.md:
    ///
    /// | выбран микрофон | что вокруг | глушим |
    /// |---|---|---|
    /// | беспроводная гарнитура | неважно | да |
    /// | встроенный | рядом есть гарнитура | нет |
    /// | встроенный | гарнитуры нет | да |
    ///
    /// Смысл средней строки: раз гарнитура рядом, человек слушает в неё,
    /// и в встроенный микрофон из неё ничего не попадает — глушить нечего.
    ///
    /// Правило распространяется и на звуковые сигналы приложения. Короткого
    /// «тинь» на старте записи достаточно, чтобы наушники, подключённые
    /// и к маку, и к телефону, перескочили на мак и оборвали музыку: сигнал
    /// уходит в устройство вывода по умолчанию, то есть прямо в них. Решили
    /// не трогать гарнитуру — значит не трогаем ничем.
    static func mayTouchOutput() -> Bool {
        guard let chosen = selected() else { return true }
        if chosen.isBluetooth { return true }
        return !hasWirelessInput()
    }

    static func defaultInput() -> AudioDeviceID? {
        systemDevice(kAudioHardwarePropertyDefaultInputDevice)
    }

    /// Делает устройство системным микрофоном по умолчанию.
    ///
    /// Так, а не подменой устройства внутри `AVAudioEngine`. Движок на macOS
    /// держит вход и выход одним узлом и навязанное устройство переваривает
    /// через раз: `start()` отвечал -10868, «формат не поддерживается», и
    /// диктовка не начиналась вовсе. Системный выбор он же читает штатно.
    ///
    /// Побочное следствие честное и видимое: выбранный в приложении микрофон
    /// становится микрофоном системы. Это ровно то, что человек и просит,
    /// и это же видно в системных настройках звука.
    @discardableResult
    static func makeDefaultInput(_ id: AudioDeviceID) -> Bool {
        var addr = address(kAudioHardwarePropertyDefaultInputDevice)
        var value = id
        return AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil,
            UInt32(MemoryLayout<AudioDeviceID>.size), &value
        ) == noErr
    }

    static func defaultOutput() -> AudioDeviceID? {
        systemDevice(kAudioHardwarePropertyDefaultOutputDevice)
    }

    /// Беспроводная гарнитура, которую нельзя трогать без спроса: она может
    /// быть подключена и к маку, и к телефону одновременно, и любое обращение
    /// к ней — микрофон, громкость, звук — перетягивает её на мак.
    ///
    /// Отличить «мак сейчас звучит в наушники» от «звучит телефон» macOS
    /// не позволяет, и это проверено, а не предположено. Замерены три
    /// состояния на живой машине:
    ///
    /// | что происходит | процессы с `IsRunningOutput` на устройстве |
    /// |---|---|
    /// | мак играет музыку | WebKit, Music |
    /// | мак на паузе | WebKit |
    /// | играет телефон | WebKit |
    ///
    /// Последние два неотличимы: Safari держит открытый поток вывода
    /// постоянно. `DeviceIsRunningSomewhere` в этих же состояниях всегда
    /// единица, `DeviceIsRunning` — всегда ноль (он про свой процесс),
    /// а `ProcessIsAudible` вообще не запрос про чужие процессы, а рычаг
    /// «заглушить себя». Публичного признака нет; Apple делает своё
    /// автопереключение не через открытый API.
    ///
    /// Поэтому приложение не угадывает, а не трогает такие устройства
    /// по умолчанию.
    static func isShared(_ device: InputDevice) -> Bool {
        device.isBluetooth || device.isContinuity
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

    /// Стоит ли вывод на беспроводной гарнитуре, которую можно отобрать
    /// у телефона. По этому признаку приложение решает, можно ли трогать
    /// громкость и проигрывать свои сигналы.
    static func outputIsShared() -> Bool {
        guard let id = defaultOutput() else { return false }
        return isShared(describe(id))
    }

    // MARK: - Решение

    /// Устройство, с которого писать.
    ///
    /// Три случая, и ни в одном приложение ничего не угадывает:
    ///
    /// - `auto` — системный микрофон по умолчанию, но **никогда**
    ///   беспроводная гарнитура: определить, слушает ли человек через неё мак
    ///   или телефон, macOS не позволяет (см. `isShared`), а взяв её вслепую,
    ///   приложение отберёт наушники у телефона. В этом случае — встроенный.
    /// - `builtIn` — встроенный всегда, без вариантов.
    /// - конкретное устройство — то, что человек выбрал сам. Выбрал
    ///   наушники — значит сказал, что они на маке, и вопросов нет.
    static func selected() -> InputDevice? {
        resolve(Settings.shared.microphone)
    }

    /// То же решение, но для заданного выбора: режим «клавиша на устройство»
    /// назначает микрофон сочетанием, а не общей настройкой.
    static func resolve(_ choice: MicrophoneChoice) -> InputDevice? {
        switch choice {
        case .auto:
            guard let currentID = defaultInput(),
                  let current = inputs().first(where: { $0.id == currentID })
            else { return builtInInput() }
            return isShared(current) ? builtInInput() : current

        case .builtIn:
            return builtInInput()

        case .device(let uid):
            // Устройство могли отключить — тогда пишем со встроенного, чтобы
            // диктовка не сорвалась. Выбор при этом не стираем: вернут
            // наушники — вернётся и он.
            return inputs().first { $0.uid == uid } ?? builtInInput()
        }
    }

    /// Выбранное устройство пропало из системы.
    static func selectedIsMissing() -> Bool {
        guard case .device(let uid) = Settings.shared.microphone else { return false }
        return !inputs().contains { $0.uid == uid }
    }

    /// Что сейчас выбрано, словами — для журнала и диагностики.
    static func explain() -> String {
        let chosen = selected()?.name ?? "встроенный не найден"
        let mode: String
        switch Settings.shared.microphone {
        case .auto: mode = "авто"
        case .builtIn: mode = "встроенный"
        case .device: mode = selectedIsMissing() ? "выбранное отключено" : "выбран вручную"
        }
        let out = defaultOutput().map { "; вывод — \(describe($0).name)" } ?? ""
        return "\(chosen) [\(mode)]\(out)"
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
enum MicrophoneChoice: Equatable {
    /// Как в системе, но беспроводную гарнитуру не берём.
    case auto
    /// Встроенный микрофон всегда.
    case builtIn
    /// Конкретное устройство по его UID.
    case device(String)

    /// Значение для меню: пустая строка — авто, `builtin` — встроенный,
    /// остальное — UID устройства.
    var tag: String {
        switch self {
        case .auto: return ""
        case .builtIn: return "builtin"
        case .device(let uid): return uid
        }
    }

    init(tag: String) {
        switch tag {
        case "": self = .auto
        case "builtin": self = .builtIn
        default: self = .device(tag)
        }
    }
}

extension Settings {
    /// Ключ `audio.micDevice`. Хранится UID, а не идентификатор устройства:
    /// идентификаторы система раздаёт заново при каждом переподключении,
    /// а UID у наушников постоянный.
    var microphone: MicrophoneChoice {
        get { MicrophoneChoice(tag: text("audio.micDevice")) }
        set { set(newValue.tag, forKey: "audio.micDevice") }
    }
}
