import AVFoundation
import Foundation

/// Пишет с микрофона в 16 kHz mono WAV — формат, который Whisper принимает напрямую
/// и который в 6 раз легче исходных 48 kHz stereo.
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

    private let engine = AVAudioEngine()
    private var file: AVAudioFile?
    private var converter: AVAudioConverter?
    private var outputURL: URL?
    private(set) var isRecording = false
    private var startedAt: Date?

    static func requestMicrophoneAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        default:
            return false
        }
    }

    func start(deviceTag: String? = nil) throws {
        guard !isRecording else { return }

        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            throw RecorderError.micDenied
        }

        // Устройство назначаем до первого обращения к формату: движок
        // запрашивает параметры у того устройства, которое стоит в этот момент,
        // и переключать его потом уже поздно.
        selectInputDevice(deviceTag)

        let input = engine.inputNode
        let inputFormat = input.inputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0 else {
            throw RecorderError.engineFailed("микрофон не отдаёт данные")
        }

        // AAC вместо WAV: те же 13 секунд речи весят ~40 КБ вместо 430 КБ,
        // и отправка перестаёт упираться в таймаут на слабой сети.
        let (url, audioFile) = try makeFile()
        // processingFormat — float32 16 kHz mono; в Int16 файл квантует сам AVAudioFile.
        guard let conv = AVAudioConverter(from: inputFormat, to: audioFile.processingFormat) else {
            throw RecorderError.engineFailed("формат микрофона не поддерживается")
        }

        file = audioFile
        converter = conv
        outputURL = url

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.append(buffer)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            file = nil
            converter = nil
            outputURL = nil
            try? FileManager.default.removeItem(at: url)
            throw RecorderError.engineFailed(error.localizedDescription)
        }

        isRecording = true
        startedAt = Date()
    }

    /// Назначает движку конкретное устройство ввода.
    ///
    /// Без этого AVAudioEngine берёт системное «по умолчанию», а это сплошь
    /// и рядом беспроводные наушники — и запись отбирает их у телефона.
    /// Единственный способ задать устройство на macOS — достучаться до AUHAL
    /// под движком: у самого AVAudioEngine такого свойства нет.
    private func selectInputDevice(_ deviceTag: String?) {
        // Тег приходит из режима «клавиша на устройство»: там микрофон
        // назначает само сочетание, а не общий выбор в панели.
        let chosen = deviceTag.map { AudioDevices.resolve(MicrophoneChoice(tag: $0)) }
            ?? AudioDevices.selected()
        guard let device = chosen else {
            Log.write("Микрофон: \(AudioDevices.explain())")
            return
        }

        // Выходной узел движка отдельно не переключается: на macOS вход и выход
        // AVAudioEngine — один и тот же HAL-узел, и запись устройства вывода
        // сбрасывает устройство ввода. Проверено: после такой попытки выбор
        // микрофона возвращал -10851, а движок — «микрофон не отдаёт данные».
        var id = device.id
        let unit = engine.inputNode.audioUnit
        guard let unit else { return }

        let status = AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &id,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )

        if status == noErr {
            Log.write("Микрофон: \(AudioDevices.explain())")
        } else {
            Log.write("Микрофон: не удалось выбрать «\(device.name)» (код \(status)), "
                      + "остаётся системный")
        }
    }

    /// Останавливает запись и возвращает файл и его длительность.
    @discardableResult
    func stop() -> (url: URL, duration: TimeInterval)? {
        guard isRecording else { return nil }
        isRecording = false

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        let duration = startedAt.map { Date().timeIntervalSince($0) } ?? 0
        let url = outputURL

        file = nil          // закрывает файл и дописывает WAV-заголовок
        converter = nil
        outputURL = nil
        startedAt = nil

        guard let url else { return nil }
        return (url, duration)
    }

    /// Прервать запись и выбросить файл — например, когда удержание оказалось шорткатом.
    func cancel() {
        guard let result = stop() else { return }
        try? FileManager.default.removeItem(at: result.url)
    }

    /// Пишем в m4a; если система почему-то не даёт кодировать AAC,
    /// откатываемся на обычный WAV — лучше тяжёлый файл, чем сорванная запись.
    private func makeFile() throws -> (URL, AVAudioFile) {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("nadiktovka-\(UUID().uuidString)")

        let compressed = base.appendingPathExtension("m4a")
        let aac: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16_000.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 24_000
        ]
        if let file = try? AVAudioFile(forWriting: compressed, settings: aac) {
            return (compressed, file)
        }

        Log.write("AAC недоступен, пишу WAV")
        let raw = base.appendingPathExtension("wav")
        let pcm: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        return (raw, try AVAudioFile(forWriting: raw, settings: pcm))
    }

    private func append(_ buffer: AVAudioPCMBuffer) {
        guard let file, let converter else { return }

        let outFormat = file.processingFormat
        let ratio = outFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: capacity) else { return }

        var consumed = false
        var error: NSError?
        converter.convert(to: outBuffer, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }

        guard error == nil, outBuffer.frameLength > 0 else { return }
        try? file.write(from: outBuffer)

        if let level = Self.rms(of: outBuffer) {
            DispatchQueue.main.async { [weak self] in
                self?.onLevel?(level)
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
