import AudioToolbox
import CoreAudio
import Foundation

/// Приглушает системный звук на время диктовки и возвращает как было.
///
/// Работает через CoreAudio напрямую: `set volume` из AppleScript потребовал бы
/// разрешения на автоматизацию, а это лишний системный запрос ради громкости.
///
/// Громкость запоминается в момент приглушения и восстанавливается ровно та же.
/// Если человек сам покрутил её, пока шла запись, мы всё равно вернём прежнюю —
/// иначе приглушение осталось бы висеть навсегда.
enum OutputDucker {
    /// Что делать со звуком, пока идёт запись.
    enum Mode: String, CaseIterable, Identifiable {
        /// Не трогать.
        case off
        /// Убавить до заданного уровня.
        case dim
        /// Заглушить полностью.
        case mute

        var id: String { rawValue }

        var title: String {
            switch self {
            case .off: return "Не трогать"
            case .dim: return "Убавить"
            case .mute: return "Выключить"
            }
        }
    }

    /// Громкость до приглушения. Ненулевое значение означает, что мы сейчас
    /// держим звук приглушённым и обязаны его вернуть.
    private static var restoreVolume: Float?

    // MARK: - Управление

    static func duck() {
        let settings = Settings.shared
        let mode = settings.duckMode
        guard mode != .off else { return }

        guard let device = defaultOutputDevice(), let current = volume(of: device) else {
            Log.write("Приглушение пропущено: устройство вывода не отдаёт громкость")
            return
        }

        // Если мак сейчас ничего не выводит — глушить нечего, и трогать
        // устройство нельзя. Смысл приглушения в том, чтобы звук мака не лез
        // в микрофон; при молчащем маке в микрофон лезть нечему.
        //
        // Это не мелочь: у беспроводных наушников, подключённых и к маку,
        // и к телефону, одна запись громкости будит их и отбирает у телефона.
        // Музыка обрывается ровно так же, как если бы мы открыли на них
        // микрофон, — только причина другая.
        guard AudioDevices.isRunning(device) else {
            Log.write("Приглушение пропущено: мак через устройство вывода молчит")
            return
        }

        // Уже приглушено — второй раз запоминать нельзя, затрём исходное.
        guard restoreVolume == nil else { return }

        let target: Float = mode == .mute ? 0 : current * Float(settings.duckLevel)
        // Убавлять до уровня выше текущего бессмысленно: человек и так сделал тише.
        guard target < current else { return }

        restoreVolume = current
        setVolume(target, on: device)
        Log.write(String(format: "Звук приглушён: %.0f%% → %.0f%%", current * 100, target * 100))
    }

    static func restore() {
        guard let previous = restoreVolume else { return }
        restoreVolume = nil

        guard let device = defaultOutputDevice() else { return }
        setVolume(previous, on: device)
        Log.write(String(format: "Звук возвращён на %.0f%%", previous * 100))
    }

    // MARK: - CoreAudio

    private static func defaultOutputDevice() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device
        )
        return status == noErr && device != 0 ? device : nil
    }

    /// Громкость мастера, а если её нет — среднее по каналам.
    /// Часть устройств (например, некоторые USB-гарнитуры) мастера не имеют.
    private static func volume(of device: AudioDeviceID) -> Float? {
        if let master = scalarVolume(of: device, channel: kAudioObjectPropertyElementMain) {
            return master
        }

        let channels = [UInt32(1), UInt32(2)].compactMap {
            scalarVolume(of: device, channel: $0)
        }
        guard !channels.isEmpty else { return nil }
        return channels.reduce(0, +) / Float(channels.count)
    }

    private static func scalarVolume(of device: AudioDeviceID, channel: UInt32) -> Float? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: channel
        )
        guard AudioObjectHasProperty(device, &address) else { return nil }

        var value = Float(0)
        var size = UInt32(MemoryLayout<Float>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
        return status == noErr ? value : nil
    }

    private static func setVolume(_ value: Float, on device: AudioDeviceID) {
        let clamped = min(max(value, 0), 1)
        let channels: [UInt32] = [kAudioObjectPropertyElementMain, 1, 2]

        for channel in channels {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: channel
            )
            guard AudioObjectHasProperty(device, &address) else { continue }

            var settable: DarwinBoolean = false
            guard AudioObjectIsPropertySettable(device, &address, &settable) == noErr,
                  settable.boolValue
            else { continue }

            var target = clamped
            AudioObjectSetPropertyData(
                device, &address, 0, nil, UInt32(MemoryLayout<Float>.size), &target
            )

            // Мастер перекрывает каналы: если он есть, по каналам не ходим.
            if channel == kAudioObjectPropertyElementMain { return }
        }
    }
}
