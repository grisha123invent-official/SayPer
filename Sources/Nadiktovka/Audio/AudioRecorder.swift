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

    /// Устройства переключились посреди записи.
    ///
    /// Подключение или пропажа любого устройства — наушников, монитора
    /// с колонками, гарнитуры — заставляет `AVAudioEngine` перестроиться:
    /// у входного узла меняется формат, а установленный отвод перестаёт
    /// отдавать данные. Само приложение об этом не узнаёт и продолжает
    /// считать, что пишет, — в файл при этом больше ничего не попадает.
    ///
    /// Замерено на живой записи: человек говорил 27 секунд, в файле оказалось
    /// 9.6, и Whisper честно расшифровал только их. Две трети сказанного
    /// пропадали молча.
    ///
    /// Поэтому о перестройке сообщаем наружу, а не пытаемся пережить её тихо.
    var onDevicesChanged: (() -> Void)?

    /// Микрофон открылся, но не отдал ни одного кадра.
    ///
    /// Так бывает после того, как рядом дёрнулось устройство: движок
    /// запускается без ошибки, а вход остаётся мёртвым. Замерено на живой
    /// записи: человек говорил 17 секунд, в файле оказалось 4096 байт —
    /// один заголовок. Узнавал он об этом только в конце, когда мысль уже
    /// была сказана в пустоту.
    ///
    /// Тишина в комнате сюда не попадает: молчащий микрофон всё равно шлёт
    /// кадры, просто нулевые. Ноль кадров — это сломанный вход, а не тишина.
    var onMicrophoneDead: (() -> Void)?

    /// Пересоздаётся на каждую запись.
    ///
    /// `AVAudioEngine` кэширует параметры устройства и смену этого устройства
    /// не переживает: после переключения вход перестаёт совпадать с выходом,
    /// и `start()` отвечает -10868, «формат не поддерживается». Ни `reset()`,
    /// ни повторное чтение формата не помогают — надёжно только новый движок.
    /// Стоит это доли миллисекунды, а запись идёт раз в минуту.
    private var engine = AVAudioEngine()
    private var file: AVAudioFile?
    private var converter: AVAudioConverter?
    private var outputURL: URL?
    private(set) var isRecording = false
    private var startedAt: Date?
    private var configObserver: NSObjectProtocol?
    private var receivedAudio = false
    private var deadMicWatchdog: Timer?

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

        // Новый движок на каждую запись — см. объявление `engine`.
        engine = AVAudioEngine()

        // Устройство назначаем до первого обращения к формату: движок
        // запрашивает параметры у того устройства, которое стоит в этот момент,
        // и переключать его потом уже поздно.
        selectInputDevice(deviceTag)

        let input = engine.inputNode
        let inputFormat = input.inputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw RecorderError.engineFailed("микрофон не отдаёт данные")
        }

        let (url, audioFile) = try makeFile()

        file = audioFile
        converter = nil
        outputURL = url

        // Формат отводу не задаём — берём `nil`, то есть «спроси у узла сам».
        //
        // Раньше сюда передавался формат, прочитанный секундой раньше, и на
        // беспроводной гарнитуре это роняло приложение: открытие микрофона
        // переводит наушники в гарнитурный режим, там другая частота, формат
        // перестаёт совпадать, и `installTap` бросает исключение Objective-C.
        // Из Swift такое не поймать — процесс просто падал.
        //
        // Раз формат теперь известен только в момент прихода данных,
        // преобразователь создаётся по первому же буферу.
        input.installTap(onBus: 0, bufferSize: 4096, format: nil) { [weak self] buffer, _ in
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

        receivedAudio = false
        // Секунды с запасом хватает: кадры идут примерно одиннадцать раз
        // в секунду, первый приходит почти сразу после старта.
        deadMicWatchdog = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: false) {
            [weak self] _ in
            guard let self, self.isRecording, !self.receivedAudio else { return }
            Log.write("Микрофон не отдал ни одного кадра за 1.2 с — обрываю запись")
            self.onMicrophoneDead?()
        }

        // Подписка после успешного старта: до него движок ещё не тот, за чьей
        // перестройкой мы следим, а порядок вызовов выше трогать нельзя.
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            guard let self, self.isRecording else { return }
            Log.write("Устройства переключились посреди записи — закрываю то, что успел")
            self.onDevicesChanged?()
        }
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

        // Если это и так системный микрофон по умолчанию, ничего не трогаем.
        // Любое назначение устройства — риск, а тут оно бессмысленно.
        if AudioDevices.defaultInput() == device.id {
            Log.write("Микрофон: \(AudioDevices.explain())")
            return
        }

        // Переключаем системный микрофон, а не подменяем устройство внутри
        // движка — см. `AudioDevices.makeDefaultInput`.
        if AudioDevices.makeDefaultInput(device.id) {
            Log.write("Микрофон: \(AudioDevices.explain())")
        } else {
            Log.write("Микрофон: не удалось переключить на «\(device.name)», "
                      + "остаётся системный")
        }
    }

    /// Останавливает запись и возвращает файл и его длительность.
    @discardableResult
    func stop() -> (url: URL, duration: TimeInterval)? {
        guard isRecording else { return nil }
        isRecording = false

        deadMicWatchdog?.invalidate()
        deadMicWatchdog = nil

        if let configObserver {
            NotificationCenter.default.removeObserver(configObserver)
            self.configObserver = nil
        }

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

    /// Пишем несжатым WAV в кладовку записей.
    ///
    /// Раньше писали сразу в m4a — он в десять раз легче, и отправка
    /// не упиралась в таймаут на слабой сети. Но у m4a оглавление
    /// дописывается при закрытии файла: запись, оборванная перезапуском
    /// посреди фразы, не открывалась потом ничем, и наговоренное пропадало.
    /// У WAV данные идут сразу за заголовком — оборванный файл чинится
    /// двумя числами, см. `RecordingVault.repairIfNeeded`.
    ///
    /// Выигрыш в весе никуда не делся: сжимаем перед самой отправкой.
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

    private func append(_ buffer: AVAudioPCMBuffer) {
        guard let file else { return }

        // Преобразователь строится по формату первого пришедшего буфера:
        // до этого момента настоящий формат устройства неизвестен, а на
        // беспроводной гарнитуре он ещё и меняется при переключении режима.
        if converter == nil {
            guard let made = AVAudioConverter(from: buffer.format, to: file.processingFormat) else {
                Log.write("Формат микрофона не поддерживается: \(buffer.format)")
                return
            }
            converter = made
            Log.debug("Формат записи: \(Int(buffer.format.sampleRate)) Гц, "
                      + "\(buffer.format.channelCount) кан.")
        }
        guard let converter else { return }

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

        let level = Self.rms(of: outBuffer)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // Первый дошедший кадр снимает сторожа мёртвого микрофона.
            // Флаг ставится здесь, а не в звуковом потоке: иначе главный
            // поток читал бы его наперегонки с записью.
            self.receivedAudio = true
            if let level { self.onLevel?(level) }
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
