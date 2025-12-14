import UIKit

// MARK: - EnergySaving

public func determineEnergySavingMode() -> Bool {
    // 1. Проверяем системный режим экономии энергии
    if ProcessInfo.processInfo.isLowPowerModeEnabled {
        return true
    }

    // 2. Проверяем уровень заряда батареи (если доступно)
//    if UIDevice.current.isBatteryMonitoringEnabled {
//        let batteryLevel = UIDevice.current.batteryLevel
//        if batteryLevel > 0 && batteryLevel < 0.05 { // Меньше 5%
//            return true
//        }
//    }

    // 3. Проверяем тепловое состояние
//    let thermalState = ProcessInfo.processInfo.thermalState
//    if thermalState == .critical {
//        return true
//    }

    // 4. Используем пользовательские настройки
    let isSafeEnergy: Bool = false
    return isSafeEnergy
}
