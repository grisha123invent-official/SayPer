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
    }

    /// Что делать с готовым текстом. Вызывается строго по порядку записей.
    var onReady: ((String, Job) -> Void)?
    /// Расшифровка не удалась — сюда идёт текст ошибки.
    var onFailure: ((String) -> Void)?
    /// Меняется, когда очередь становится пустой или снова непустой:
    /// по нему приложение показывает и прячет пилюлю.
    var onActivityChange: ((Bool) -> Void)?

    private var nextID = 0
    private var nextToDeliver = 0
    private var tasks: [Int: Task<Void, Never>] = [:]
    /// Ответы, пришедшие раньше своей очереди, вместе со своими фразами.
    private var ready: [Int: (text: String, job: Job)] = [:]

    var isEmpty: Bool { tasks.isEmpty }

    /// Сколько секунд ждёт самая старая фраза в очереди — для подписи на пилюле.
    var oldestWait: TimeInterval {
        guard let started = oldestStart else { return 0 }
        return Date().timeIntervalSince(started)
    }

    private var oldestStart: Date?

    func enqueue(audio: URL, duration: TimeInterval, insertMode: InsertMode) {
        let job = Job(
            id: nextID, audio: audio, duration: duration,
            startedAt: Date(), insertMode: insertMode
        )
        nextID += 1

        if tasks.isEmpty {
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
        ready.removeAll()
        // Хвост очереди отменён — следующая фраза начнёт нумерацию заново,
        // иначе она встала бы в ожидание отменённых предшественниц навсегда.
        nextToDeliver = nextID
        oldestStart = nil
        onActivityChange?(false)
    }

    // MARK: - Работа

    @MainActor
    private func run(_ job: Job) async {
        defer {
            tasks[job.id] = nil
            try? FileManager.default.removeItem(at: job.audio)
            finishIfDrained()
        }

        do {
            let text = try await Transcriber.transcribe(fileURL: job.audio)
            guard !Task.isCancelled else { return }
            ready[job.id] = (text, job)
            deliverReady()
        } catch {
            // Отмена приходит и как CancellationError, и как URLError(.cancelled) —
            // это не сбой, ругаться на неё не надо.
            let cancelled = error is CancellationError
                || (error as? URLError)?.code == .cancelled
                || Task.isCancelled

            if cancelled {
                Log.write("Расшифровка отменена")
            } else {
                onFailure?(error.localizedDescription)
            }
            // Провалившаяся фраза не должна держать следующие: пропускаем её
            // номер, иначе весь хвост очереди застрянет навсегда.
            if job.id == nextToDeliver {
                nextToDeliver += 1
                deliverReady()
            }
        }
    }

    /// Отдаёт всё, что готово и стоит следующим по очереди.
    @MainActor
    private func deliverReady() {
        while let entry = ready.removeValue(forKey: nextToDeliver) {
            nextToDeliver += 1
            onReady?(entry.text, entry.job)
        }
    }

    @MainActor
    private func finishIfDrained() {
        guard tasks.isEmpty else { return }
        oldestStart = nil
        onActivityChange?(false)
    }
}
