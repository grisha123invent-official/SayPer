import AudioToolbox
import AVFoundation
import CoreAudio
import Foundation

/// Пишет с микрофона в 16 kHz mono WAV — формат, который Whisper принимает
/// напрямую и который в шесть раз легче исходных 48 kHz stereo.
///
/// Записывает не через `AVAudioEngine`, а через собственный юнит AUHAL
/// с **выключенной выходной стороной**. Так делают серьёзные звуковые
/// приложения, и переход на этот способ 21 августа закрыл сразу весь ворох
/// бед, которые до того лечились по одной и возвращались:
///
/// - **Системный микрофон больше не переключается.** Раньше выбрать устройство
///   можно было только сделав его системным входом: у `AVAudioEngine` нет
///   свойства «пиши с этого устройства». Своему юниту оно задаётся напрямую,
///   поэтому чужие настройки не трогаются вовсе.
/// - **Наушники на выводе больше не мешают.** Движок держит вход и выход одним
///   узлом: при выводе на AirPods и записи со встроенного микрофона `start()`
///   отвечал -10868, «формат не поддерживается». Здесь выхода нет вообще.
/// - **Перестройки звука не рвут запись.** Уведомление о них приходило движку,
///   он терял отвод и молча замолкал посреди фразы.
///
/// Проверено замером на живой машине: вывод на AirPods Pro, вход встроенный,
/// 143 872 кадра за три секунды при ожидаемых 144 000, системный вход
/// нетронут.
final class AudioRecorder {
    enum RecorderError: LocalizedError {
        case micDenied
        case engineFailed(String)

        var errorDescription: String? {
            switch self {
            case .micDenied:
                return "Нет доступа к микрофону. Системные настройки → Конфиденциальность и безопасность → Микрофон."
            case .engineFailed(let message):
                return "Не удалось запустить запись: \(message)"
            }
        }
    }

    /// Текущий уровень звука 0…1 — для индикатора. Вызывается на главном потоке.
    var onLevel: ((Float) -> Void)?

    /// Устройства переключились посреди записи. Запись при этом продолжается:
    /// свой юнит держит своё устройство и чужих перестроек не замечает.
    var onDevicesChanged: (() -> Void)?

    /// Микрофон открылся, но не отдал ни одного кадра.
    var onMicrophoneDead: (() -> Void)?

    private(set) var isRecording = false

    /// Самый громкий кадр за запись, 0…1. По нему видно, был ли вообще звук.
    private(set) var peakLevel: Float = 0

    /// Сколько уже пишем. Нужно, чтобы отличить задетую клавишу от шортката.
    var currentDuration: TimeInterval {
        startedAt.map { Date().timeIntervalSince($0) } ?? 0
    }

    private var unit: AudioUnit?
    private var file: AVAudioFile?
    private var converter: AVAudioConverter?
    private var hardwareFormat: AVAudioFormat?
    private var outputURL: URL?
    private var startedAt: Date?
    private var receivedAudio = false
    private var deadMicWatchdog: Timer?

    static func requestMicrophoneAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    // MARK: - Запись

    func start(deviceTag: String? = nil) throws {
        guard !isRecording else { return }

        let device = resolveDevice(deviceTag)
        let unit = try makeUnit(device: device)
        self.unit = unit

        let hardware = try clientFormat(of: unit)
        hardwareFormat = hardware

        let (url, audioFile) = try makeFile()
        file = audioFile
        outputURL = url
        converter = AVAudioConverter(from: hardware, to: audioFile.processingFormat)

        var callback = AURenderCallbackStruct(
            inputProc: { refCon, flags, stamp, bus, frames, _ in
                let recorder = Unmanaged<AudioRecorder>.fromOpaque(refCon).takeUnretainedValue()
                recorder.render(flags: flags, stamp: stamp, bus: bus, frames: frames)
                return noErr
            },
            inputProcRefCon: Unmanaged.passUnretained(self).toOpaque()
        )
        AudioUnitSetProperty(unit, kAudioOutputUnitProperty_SetInputCallback,
                             kAudioUnitScope_Global, 0, &callback,
                             UInt32(MemoryLayout<AURenderCallbackStruct>.size))

        let initStatus = AudioUnitInitialize(unit)
        guard initStatus == noErr else {
            teardown()
            try? FileManager.default.removeItem(at: url)
            throw RecorderError.engineFailed("вход не поднялся (\(initStatus))")
        }
        let startStatus = AudioOutputUnitStart(unit)
        guard startStatus == noErr else {
            teardown()
            try? FileManager.default.removeItem(at: url)
            throw RecorderError.engineFailed("запуск не удался (\(startStatus))")
        }

        isRecording = true
        startedAt = Date()
        receivedAudio = false
        peakLevel = 0

        // Заводится на главном цикле: запуск идёт из фоновой очереди,
        // а там нет цикла событий — таймер молча не сработал бы.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isRecording else { return }
            self.deadMicWatchdog = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: false) {
                [weak self] _ in
                guard let self, self.isRecording, !self.receivedAudio else { return }
                Log.write("Микрофон не отдал ни одного кадра за 1.2 с")
                self.onMicrophoneDead?()
            }
        }
    }

    /// Останавливает запись и возвращает файл и его длительность.
    /// Останавливает запись и возвращает файл и его длительность.
    ///
    /// Отдаёт файл **даже если запись уже считается остановленной**. Пустой
    /// ответ раньше означал молчаливую потерю: звук на диск лёг, а наверх
    /// об этом не сообщили, и никто его не подобрал. Замерено 23 августа —
    /// восемнадцать секунд речи исчезли ровно так.
    @discardableResult
    func stop() -> (url: URL, duration: TimeInterval)? {
        guard isRecording else {
            // Запись уже сняли, но файл от неё остался — отдаём его.
            guard let url = outputURL else { return nil }
            let duration = startedAt.map { Date().timeIntervalSince($0) } ?? 0
            Log.write("Запись уже была остановлена, но файл на месте — отдаю его")
            file = nil
            converter = nil
            hardwareFormat = nil
            outputURL = nil
            startedAt = nil
            return (url, duration)
        }
        isRecording = false

        deadMicWatchdog?.invalidate()
        deadMicWatchdog = nil

        let duration = startedAt.map { Date().timeIntervalSince($0) } ?? 0
        let url = outputURL

        teardown()
        file = nil          // закрывает файл и дописывает WAV-заголовок
        converter = nil
        hardwareFormat = nil
        outputURL = nil
        startedAt = nil

        guard let url else { return nil }
        return (url, duration)
    }

    /// Прервать запись и выбросить файл — например, когда удержание
    /// оказалось шорткатом.
    func cancel() {
        guard let result = stop() else { return }
        RecordingVault.discard(result.url)
    }

    // MARK: - Устройство и юнит

    private func resolveDevice(_ deviceTag: String?) -> InputDevice? {
        // Тег приходит из режима «клавиша на устройство»: там микрофон
        // назначает само сочетание, а не общий выбор в панели.
        let chosen = deviceTag.map { AudioDevices.resolve(MicrophoneChoice(tag: $0)) }
            ?? AudioDevices.selected()
        Log.write("Микрофон: \(chosen?.name ?? "системный") [\(AudioDevices.explain())]")
        return chosen
    }

    /// Собирает юнит: вход включён, выход выключен, устройство своё.
    ///
    /// Выключенный выход — суть всей затеи. Пока он включён, юнит обязан
    /// обслуживать и вывод тоже, и при разных устройствах на входе и выходе
    /// отказывается работать.
    private func makeUnit(device: InputDevice?) throws -> AudioUnit {
        var description = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0, componentFlagsMask: 0
        )
        guard let component = AudioComponentFindNext(nil, &description) else {
            throw RecorderError.engineFailed("в системе нет звукового компонента")
        }

        var created: AudioUnit?
        let status = AudioComponentInstanceNew(component, &created)
        guard status == noErr, let unit = created else {
            throw RecorderError.engineFailed("юнит не создался (\(status))")
        }

        var enable: UInt32 = 1
        var disable: UInt32 = 0
        AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO,
                             kAudioUnitScope_Input, 1, &enable, 4)
        AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO,
                             kAudioUnitScope_Output, 0, &disable, 4)

        if let device {
            var id = device.id
            let assigned = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice,
                                                kAudioUnitScope_Global, 0, &id, 4)
            if assigned != noErr {
                Log.write("Микрофон: не удалось назначить «\(device.name)» (\(assigned)), "
                          + "пишем системным")
            }
        }
        return unit
    }

    /// Формат, в котором юнит будет отдавать нам кадры: моно float
    /// на частоте самого железа. Частоту берём у устройства, а не задаём
    /// свою: навязанная частота — верный способ получить отказ.
    private func clientFormat(of unit: AudioUnit) throws -> AVAudioFormat {
        var hardware = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let status = AudioUnitGetProperty(unit, kAudioUnitProperty_StreamFormat,
                                          kAudioUnitScope_Input, 1, &hardware, &size)
        guard status == noErr, hardware.mSampleRate > 0 else {
            throw RecorderError.engineFailed("микрофон не отдаёт данные")
        }

        var client = AudioStreamBasicDescription(
            mSampleRate: hardware.mSampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4,
            mChannelsPerFrame: 1, mBitsPerChannel: 32, mReserved: 0
        )
        let applied = AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat,
                                           kAudioUnitScope_Output, 1, &client,
                                           UInt32(MemoryLayout<AudioStreamBasicDescription>.size))
        guard applied == noErr, let format = AVAudioFormat(streamDescription: &client) else {
            throw RecorderError.engineFailed("формат отвода не принят (\(applied))")
        }
        Log.debug("Формат записи: \(Int(hardware.mSampleRate)) Гц, "
                  + "\(hardware.mChannelsPerFrame) кан. с железа")
        return format
    }

    private func teardown() {
        guard let unit else { return }
        AudioOutputUnitStop(unit)
        AudioUnitUninitialize(unit)
        AudioComponentInstanceDispose(unit)
        self.unit = nil
    }

    /// Пишем несжатым WAV в кладовку записей.
    ///
    /// У m4a оглавление дописывается при закрытии файла: запись, оборванная
    /// перезапуском посреди фразы, не открывалась потом ничем. У WAV данные
    /// идут сразу за заголовком — оборванный файл чинится двумя числами,
    /// см. `RecordingVault.repairIfNeeded`. В весе не теряем: сжимаем
    /// перед самой отправкой.
    private func makeFile() throws -> (URL, AVAudioFile) {
        let url = RecordingVault.newRecordingURL()
        let pcm: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        return (url, try AVAudioFile(forWriting: url, settings: pcm))
    }

    // MARK: - Приём кадров

    private func render(flags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
                        stamp: UnsafePointer<AudioTimeStamp>,
                        bus: UInt32, frames: UInt32) {
        guard let unit, let hardwareFormat, let file, let converter else { return }

        var list = AudioBufferList(
            mNumberBuffers: 1,
            mBuffers: AudioBuffer(mNumberChannels: 1,
                                  mDataByteSize: frames * 4,
                                  mData: nil)
        )
        guard AudioUnitRender(unit, flags, stamp, bus, frames, &list) == noErr,
              let raw = list.mBuffers.mData,
              let source = AVAudioPCMBuffer(pcmFormat: hardwareFormat, frameCapacity: frames)
        else { return }

        source.frameLength = frames
        memcpy(source.floatChannelData![0], raw, Int(frames) * 4)

        let outFormat = file.processingFormat
        let ratio = outFormat.sampleRate / hardwareFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(frames) * ratio) + 1024
        guard let target = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: capacity) else {
            return
        }

        var consumed = false
        var error: NSError?
        converter.convert(to: target, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return source
        }

        guard error == nil, target.frameLength > 0 else { return }
        try? file.write(from: target)

        let level = Self.rms(of: target)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // Первый дошедший кадр снимает сторожа мёртвого микрофона.
            self.receivedAudio = true
            if let level {
                self.peakLevel = max(self.peakLevel, level)
                self.onLevel?(level)
            }
        }
    }

    /// Громкость кадра, нормализованная в 0…1 по шкале примерно −50…0 dBFS.
    private static func rms(of buffer: AVAudioPCMBuffer) -> Float? {
        guard let channel = buffer.floatChannelData?[0] else { return nil }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return nil }

        var sum: Float = 0
        for index in 0..<count {
            let sample = channel[index]
            sum += sample * sample
        }
        let rms = (sum / Float(count)).squareRoot()
        let db = 20 * log10(max(rms, 0.000_001))
        return min(max((db + 50) / 50, 0), 1)
    }
}
