import Foundation
import ServiceManagement

/// Автозапуск при входе в систему через SMAppService (macOS 13+).
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Возвращает описание ошибки, если система отказала.
    @discardableResult
    static func set(_ enabled: Bool) -> String? {
        do {
            if enabled {
                // requiresApproval означает, что пункт выключен пользователем
                // в «Объекты входа» — сначала снимаем старую регистрацию.
                if SMAppService.mainApp.status == .requiresApproval {
                    try? SMAppService.mainApp.unregister()
                }
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
