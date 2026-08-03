import AppKit

/// Звуковые сигналы приложения.
///
/// Каждый отвечает за свой момент, и выключать их имеет смысл поштучно:
/// сигнал старта нужен почти всем — без него не понять, что запись пошла, —
/// а «текст вставлен» многих раздражает, потому что результат и так виден.
enum SoundEvent: String, CaseIterable, Identifiable {
    case start
    case stop
    case done
    case error

    var id: String { rawValue }

    /// Имя системного звука macOS. Своих файлов не носим: системные звучат
    /// привычно, тише и не спорят с настройками звука в самой системе.
    var systemName: String {
        switch self {
        case .start: return "Tink"
        case .stop: return "Pop"
        case .done: return "Purr"
        case .error: return "Basso"
        }
    }

    var title: String {
        switch self {
        case .start: return "Запись пошла"
        case .stop: return "Запись закончена"
        case .done: return "Текст вставлен"
        case .error: return "Ошибка"
        }
    }

    var subtitle: String {
        switch self {
        case .start: return "Отпускать клавишу ещё рано"
        case .stop: return "Ушло на расшифровку"
        case .done: return "Готово, можно смотреть в поле"
        case .error: return "Что-то не вышло"
        }
    }
}

enum Sounds {
    /// Проиграть сигнал события. Молча ничего не делает, если звуки выключены
    /// целиком, отключён сам сигнал или громкость выкручена в ноль.
    static func play(_ event: SoundEvent) {
        let settings = Settings.shared
        guard settings.playSounds, settings.isSoundEnabled(event) else { return }

        // Молчим там, где решили не трогать устройство вывода: сигнал уходит
        // в него же, и одного «тинь» хватает, чтобы утащить наушники
        // с телефона на мак. Что происходит с записью, видно по пилюле
        // и по значку в строке меню.
        guard AudioDevices.mayTouchOutput() else { return }

        let volume = Float(settings.soundVolume)
        guard volume > 0.001 else { return }

        // Новый экземпляр на каждый сигнал: у общего `play()` обрывает
        // предыдущее воспроизведение, а сигналы идут встык — «запись
        // закончена» звучит почти сразу за «текст вставлен».
        guard let sound = NSSound(named: event.systemName) else { return }
        sound.volume = volume
        sound.play()
    }

    /// Образец для настроек: играет независимо от того, включён ли сам сигнал, —
    /// человек крутит громкость и хочет её слышать.
    static func preview(_ event: SoundEvent = .done) {
        let volume = Float(Settings.shared.soundVolume)
        guard volume > 0.001, let sound = NSSound(named: event.systemName) else { return }
        sound.volume = volume
        sound.play()
    }
}

extension Settings {
    /// Общая громкость сигналов, 0…1. Ключ `sound.volume`.
    ///
    /// По умолчанию не единица: системные звуки на полной громкости в тихой
    /// комнате бьют по ушам, а диктуют обычно именно в тишине.
    var soundVolume: Double {
        get { min(max(decimal("sound.volume", default: 0.6), 0), 1) }
        set { set(min(max(newValue, 0), 1), forKey: "sound.volume") }
    }

    func isSoundEnabled(_ event: SoundEvent) -> Bool {
        flag("sound.\(event.rawValue)", default: true)
    }

    func setSound(_ enabled: Bool, for event: SoundEvent) {
        set(enabled, forKey: "sound.\(event.rawValue)")
    }
}
