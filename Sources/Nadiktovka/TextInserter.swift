import AppKit

/// Доставляет готовый текст в поле, где стоит курсор.
enum TextInserter {
    static func deliver(_ text: String, mode: InsertMode) {
        switch mode {
        case .clipboardOnly:
            copyToPasteboard(text)
        case .paste:
            pasteViaClipboard(text)
        case .type:
            typeUnicode(text)
        }
    }

    private static func copyToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// Кладём текст в буфер, шлём ⌘V и возвращаем буфер как было.
    private static func pasteViaClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        let saved = snapshot(of: pasteboard)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        sendCommandV()

        // Даём приложению-получателю прочитать буфер до того, как вернём старое содержимое.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            restore(saved, to: pasteboard)
        }
    }

    private static func sendCommandV() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        // Чтобы наш ⌘V не смешался с физически зажатым модификатором-хоткеем.
        source.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )

        let vKeyCode: CGKeyCode = 9 // «V» в раскладке ANSI
        guard
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        else { return }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cgAnnotatedSessionEventTap)
        keyUp.post(tap: .cgAnnotatedSessionEventTap)
    }

    /// Посимвольный ввод: буфер обмена не трогается, но длинный текст «печатается» заметно.
    private static func typeUnicode(_ text: String) {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }

        // Порциями по 20 символов — CGEvent не любит длинные строки за раз.
        for chunk in Array(text).chunked(into: 20) {
            let string = String(chunk)
            var utf16 = Array(string.utf16)
            guard
                let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            else { continue }

            keyDown.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
            keyUp.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
            keyDown.post(tap: .cgAnnotatedSessionEventTap)
            keyUp.post(tap: .cgAnnotatedSessionEventTap)
            Thread.sleep(forTimeInterval: 0.005)
        }
    }

    private static func snapshot(of pasteboard: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        (pasteboard.pasteboardItems ?? []).map { item in
            var stored: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    stored[type] = data
                }
            }
            return stored
        }
    }

    private static func restore(_ snapshot: [[NSPasteboard.PasteboardType: Data]], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !snapshot.isEmpty else { return }

        let items: [NSPasteboardItem] = snapshot.map { stored in
            let item = NSPasteboardItem()
            for (type, data) in stored {
                item.setData(data, forType: type)
            }
            return item
        }
        pasteboard.writeObjects(items)
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
