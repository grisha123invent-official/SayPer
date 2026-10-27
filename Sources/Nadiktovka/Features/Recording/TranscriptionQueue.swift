import Foundation

/// Очередь расшифровок: сами запросы идут параллельно, а текст вставляется
/// строго в том порядке, в каком фразы были надиктованы.
///
/// Записывать по-прежнему можно только одну фразу за раз — микрофон один.
/// А вот ждать ответа от OpenAI, чтобы начать следующую, незачем: человек
/// договорил, отпустил клавишу и сразу диктует дальше, пока предыдущая фраза
/// расшифровывается в фоне.
///
/// Порядок вставки хранится отдельно от порядка ответов намеренно. Время
/// расшифровки растёт с длиной записи, поэтому короткая вторая фраза почти
/// всегда возвращается раньше длинной первой. Вставлять «как ответилось»
/// значило бы перемешивать текст в поле — вторая половина мысли оказывалась бы
/// выше первой. Готовый, но преждевременный результат ждёт своей очереди.
///
/// Класс целиком не помечен `@MainActor` намеренно: этого потребовал бы и весь
/// `AppDelegate`, а за ним протоколы меню и панели — правка расползлась бы
/// по половине проекта. Главному актору принадлежит только то, что выполняется
/// из фоновой задачи; всё остальное и так вызывается с главной очереди.
final class TranscriptionQueue {
    /// Одна надиктованная фраза на пути к полю ввода.
    struct Job {
        let id: Int
        let audio: URL
        let duration: TimeInterval
        let startedAt: Date
        /// Способ вставки фиксируется в момент записи: авто-стоп подменяет его
        /// одноразово, и к моменту ответа подмена уже не действует.
        let insertMode: InsertMode
        /// Фраза, подобранная после перезапуска. Её текст никуда не вставляется:
        /// курсор давно в другом окне, и вставка вслепую хуже потери.
        var isRecovered = false
    }

    /// Что происходит с фразой прямо сейчас — для строки в панели.
    struct Progress: Identifiable, Equatable {
        enum Stage: Equatable {
            case sending
            /// Текст готов, но впереди стоит фраза, которая ещё едет.
            /// Вставляем строго по порядку, поэтому этот ждёт своей очереди.
            case ready
            /// Связь подвела, идёт повтор. Номер попытки — человеку важно
            /// видеть, что приложение не сдалось, а работает.
            case retrying(attempt: Int)
            case failed(String)
        }

        let id: Int
        let startedAt: Date
        let duration: TimeInterval
        let isRecovered: Bool
        /// Файл записи: по «убрать» его надо стереть, иначе фраза вернётся
        /// при следующем запуске как недоставленная.
        let audio: URL
        /// Нужен для повтора: способ вставки фиксируется в момент записи.
        let insertMode: InsertMode
        /// Есть ли смысл предлагать «Повторить». Не всякий провал лечится
        /// повтором: если в записи нет звука, вторая отправка вернёт ту же
        /// ошибку и потратит деньги впустую.
        var canRetry = false
        var stage: Stage
    }

    /// Что делать с готовым текстом. Вызывается строго по порядку записей.
    var onReady: ((String, Job) -> Void)?
    /// Расшифровка не удалась — сюда идёт текст ошибки.
    var onFailure: ((String) -> Void)?
    /// Меняется, когда очередь становится пустой или снова непустой:
    /// по нему приложение показывает и прячет пилюлю.
    var onActivityChange: ((Bool) -> Void)?
    /// Список того, что сейчас в работе. Дёргается на каждое изменение:
    /// панель показывает эти строки вперемешку с готовыми расшифровками,
    /// чтобы было видно — запись не потерялась, она едет.
    var onProgress: (([Progress]) -> Void)?

    private var nextID = 0
    private var nextToDeliver = 0
    private var tasks: [Int: Task<Void, Never>] = [:]
    /// Ответы, пришедшие раньше своей очереди, вместе со своими фразами.
    private var ready: [Int: (text: String, job: Job)] = [:]
    /// Номера, которых в очереди уже не будет: фраза провалилась, её
    /// остановили вручную или отложили до следующего запуска. Список нужен
    /// затем, что пропускать номер в момент провала нельзя — к этой минуте
    /// он не обязательно первый в очереди, см. `deliverReady()`.
    private var skipped: Set<Int> = []
    /// Состояние каждой фразы в работе. Провалившиеся остаются здесь,
    /// пока человек не уберёт их сам: молча исчезнувшая фраза читается
    /// как потерянная.
    private var progress: [Int: Progress] = [:]

    var isEmpty: Bool { tasks.isEmpty }

    /// Задачи, о которых пилюле знать не нужно.
    private var quietJobs: Set<Int> = []

    private func isQuiet(_ id: Int) -> Bool { quietJobs.contains(id) }

    /// Сколько сейчас работает задач, ради которых пилюля показывается.
    private var loudJobsRunning: Int {
        tasks.keys.filter { !quietJobs.contains($0) }.count
    }

    /// Сколько секунд ждёт самая старая фраза в очереди — для подписи на пилюле.
    var oldestWait: TimeInterval {
        guard let started = oldestStart else { return 0 }
        return Date().timeIntervalSince(started)
    }

    private var oldestStart: Date?

    /// `quietly` — работа, которую человек не начинал голосом прямо сейчас:
    /// повтор из панели и записи, подобранные после перезапуска. Пилюля для
    /// них не показывается: она сообщает «слушаю тебя», а тут никто не говорит,
    /// и всплывшая посреди работы плашка только мешает.
    func enqueue(audio: URL, duration: TimeInterval, insertMode: InsertMode,
                 isRecovered: Bool = false, quietly: Bool = false) {
        let job = Job(
            id: nextID, audio: audio, duration: duration,
            startedAt: Date(), insertMode: insertMode, isRecovered: isRecovered
        )
        nextID += 1

        progress[job.id] = Progress(id: job.id, startedAt: job.startedAt,
                                    duration: duration, isRecovered: isRecovered,
                                    audio: audio, insertMode: insertMode, stage: .sending)
        publishProgress()

        if quietly || isRecovered {
            quietJobs.insert(job.id)
        }

        if !isQuiet(job.id), loudJobsRunning == 0 {
            oldestStart = job.startedAt
            onActivityChange?(true)
        }

        tasks[job.id] = Task { [weak self] in
            await self?.run(job)
        }
    }

    /// Отменяет всё, что ещё в работе.
    func cancelAll() {
        guard !tasks.isEmpty else { return }
        for task in tasks.values { task.cancel() }
        tasks.removeAll()
        quietJobs.removeAll()
        ready.removeAll()
        progress.removeAll()
        publishProgress()
        // Хвост очереди отменён — следующая фраза начнёт нумерацию заново,
        // иначе она встала бы в ожидание отменённых предшественниц навсегда.
        nextToDeliver = nextID
        skipped.removeAll()
        oldestStart = nil
        onActivityChange?(false)
    }

    // MARK: - Работа

    @MainActor
    private func run(_ job: Job) async {
        defer {
            tasks[job.id] = nil
            finishIfDrained()
        }

        // Отправляем сжатую копию, а исходник держим до подтверждения:
        // пока текст не доехал, запись — единственное, что есть.
        let packed = RecordingVault.compressed(job.audio)
        defer { if packed != job.audio { try? FileManager.default.removeItem(at: packed) } }

        do {
            let text = try await Transcriber.transcribe(fileURL: packed) { [weak self] attempt in
                Task { @MainActor in self?.note(job.id, .retrying(attempt: attempt)) }
            }
            guard !Task.isCancelled else { return }
            RecordingVault.discard(job.audio)
            // Строку не убираем: текст готов, но может ждать впереди стоящую
            // фразу. Без этой отметки человек видел пустоту и не понимал,
            // почему ничего не появляется, — а всё стояло за одним затором.
            note(job.id, .ready)
            ready[job.id] = (text, job)
            deliverReady()
        } catch {
            // Отмена приходит и как CancellationError, и как URLError(.cancelled) —
            // это не сбой, ругаться на неё не надо.
            let cancelled = error is CancellationError
                || (error as? URLError)?.code == .cancelled
                || Task.isCancelled

            if cancelled {
                // Запись НЕ стираем. Отмена прилетает не только от человека:
                // так же выглядит закрытие приложения и снятие процесса,
                // а там сказанное ещё никуда не доставлено. Замерено
                // 23 августа: пропал интернет, расшифровка повисла,
                // приложение перезапустили — и запись на 14 секунд исчезла,
                // потому что отмена считала её ненужной.
                //
                // Стирает запись только осознанное нажатие крестика,
                // см. `cancel(_:)`. Всё остальное её сохраняет: при следующем
                // запуске приложение подберёт её само.
                Log.write("Расшифровка отменена, запись сохранена — "
                          + "подберу при следующем запуске")
                progress[job.id] = nil
                publishProgress()
            } else if isHopeless(error) {
                // Речи в записи нет — повтор вернёт ту же пустоту. Держать
                // такой файл значит расшифровывать его заново при каждом
                // запуске и каждый раз платить за это.
                Log.write("В записи нет речи — удаляю, повторять нечего")
                RecordingVault.discard(job.audio)
                progress[job.id] = nil
                publishProgress()
            } else {
                // Файл не трогаем: связь могла отвалиться, а запись —
                // единственное, что осталось от сказанного. Подберём
                // при следующем запуске.
                note(job.id, .failed(error.localizedDescription))
                onFailure?(error.localizedDescription)
            }
            // Фраза до поля не доедет — её номер в очереди пропускаем.
            //
            // Раньше здесь стояла проверка «а она ли сейчас первая», и этого
            // было мало: провал случается и раньше ответа на предыдущую фразу
            // (короткая запись падает быстрее, чем длинная расшифровывается).
            // Тогда номер оставался дыркой, доставка упиралась в него
            // навсегда — а весь хвост к этому времени уже расшифрован,
            // и записи удалены. Замерено 27 октября: четыре готовые фразы
            // не дошли ни одна, человек диктовал в пустоту.
            skipped.insert(job.id)
            deliverReady()
        }
    }

    /// Отказ, который повтором не лечится: в записи просто нет речи.
    ///
    /// Отличать важно. Обрыв связи — повод сохранить запись и попробовать
    /// снова, а пустая запись — повод её удалить: иначе она подбирается
    /// при каждом запуске, снова уходит в OpenAI и снова возвращается
    /// пустотой, и так до бесконечности за твои деньги.
    private func isHopeless(_ error: Error) -> Bool {
        guard let error = error as? Transcriber.TranscribeError else { return false }
        switch error {
        case .empty, .tooShort: return true
        case .noAPIKey, .http: return false
        }
    }

    /// Отдаёт всё, что готово и стоит следующим по очереди.
    @MainActor
    private func deliverReady() {
        while true {
            if let entry = ready.removeValue(forKey: nextToDeliver) {
                progress[entry.job.id] = nil
                nextToDeliver += 1
                onReady?(entry.text, entry.job)
            } else if skipped.remove(nextToDeliver) != nil {
                nextToDeliver += 1
            } else {
                // Следующая по счёту фраза ещё едет — дальше не идём:
                // порядок вставки важнее скорости.
                break
            }
        }
        publishProgress()
    }

    /// Отметить новое состояние фразы и показать его.
    @MainActor
    private func note(_ id: Int, _ stage: Progress.Stage) {
        guard var entry = progress[id], entry.stage != stage else { return }
        entry.stage = stage
        if case .failed = stage {
            // Пустая запись повтором не чинится — там нечего расшифровывать.
            entry.canRetry = RecordingVault.duration(of: entry.audio) > 0.4
        }
        progress[id] = entry
        publishProgress()
    }

    /// Остановить фразу и убрать её из панели вместе с записью.
    ///
    /// Работает в любом состоянии: и когда расшифровка ещё идёт, и когда она
    /// уже провалилась. Нажатие осознанное, поэтому запись стирается — иначе
    /// остановленная фраза вернулась бы при следующем запуске как забытая.
    ///
    /// Без `@MainActor`: зовётся из панели, которая и так живёт на главной
    /// очереди, а пометка потянула бы за собой весь `AppDelegate`.
    func cancel(_ id: Int) {
        if let task = tasks[id] {
            task.cancel()
            tasks[id] = nil
        }
        ready[id] = nil
        skipped.insert(id)

        if let entry = progress[id] {
            RecordingVault.discard(entry.audio)
            Log.write("Фраза остановлена вручную, запись удалена")
        }
        progress[id] = nil
        publishProgress()
        deliverReadyFromMain()
        finishIfDrainedFromMain()
    }

    private func deliverReadyFromMain() {
        Task { @MainActor in self.deliverReady() }
    }

    private func finishIfDrainedFromMain() {
        Task { @MainActor in self.finishIfDrained() }
    }

    /// Отправить провалившуюся фразу заново.
    ///
    /// Запись всё это время лежала на диске: провал её не стирает. Способ
    /// вставки берётся тот же, что был при записи, — человек нажал «Повторить»
    /// ради того же самого текста в том же самом месте.
    func retry(_ id: Int) {
        guard let entry = progress[id] else { return }
        progress[id] = nil
        publishProgress()
        Log.write("Повторная отправка фразы длиной "
                  + String(format: "%.1f", entry.duration) + " с")
        enqueue(audio: entry.audio, duration: entry.duration,
                insertMode: entry.insertMode, isRecovered: entry.isRecovered,
                quietly: true)
    }

    private func publishProgress() {
        onProgress?(progress.values.sorted { $0.startedAt < $1.startedAt })
    }

    @MainActor
    private func finishIfDrained() {
        // Пилюлю снимаем, когда закончились именно «громкие» задачи: фоновый
        // повтор может ехать сколько угодно, человеку это не мешает.
        guard loudJobsRunning == 0 else { return }
        oldestStart = nil
        onActivityChange?(false)
        if tasks.isEmpty { quietJobs.removeAll() }
    }
}
