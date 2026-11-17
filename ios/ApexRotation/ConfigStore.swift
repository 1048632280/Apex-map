import Foundation
import Combine
import SwiftUI

final class ConfigStore: ObservableObject {
    private static let themeKey = "themeMode"

    @Published private(set) var config: RotationConfig
    @Published private(set) var themeMode: ThemeMode

    init() {
        self.config = SharedConfig.load()
        let raw = UserDefaults.standard.string(forKey: Self.themeKey) ?? ThemeMode.system.rawValue
        self.themeMode = ThemeMode(rawValue: raw) ?? .system
    }

    var isCalibrated: Bool {
        config.calibrated && !config.maps.isEmpty
    }

    // MARK: - 查询

    func currentSlot(at now: Date) -> RotationSlot? {
        RotationEngine.slot(at: now, config: config)
    }

    func upcoming(at now: Date, count: Int) -> [RotationSlot] {
        RotationEngine.upcoming(at: now, config: config, count: count)
    }

    // MARK: - 修改

    func calibrate(currentMapIndex: Int, nextSwitchAt: Date) {
        config.anchor = RotationEngine.anchor(
            currentMapIndex: currentMapIndex,
            nextSwitchAt: nextSwitchAt,
            secondsPerMap: config.secondsPerMap
        )
        config.calibrated = true
        persist()
    }

    func calibrateJustSwitched(currentMapIndex: Int, now: Date) {
        calibrate(
            currentMapIndex: currentMapIndex,
            nextSwitchAt: now.addingTimeInterval(Double(config.secondsPerMap))
        )
    }

    func setSecondsPerMap(_ seconds: Int) {
        config.secondsPerMap = max(60, seconds)
        persist()
    }

    func moveMaps(from source: IndexSet, to destination: Int) {
        config.maps.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    func reset() {
        config = .fallback
        persist()
    }

    // MARK: - 主题

    func toggleTheme() {
        setTheme(themeMode.toggled)
    }

    func setTheme(_ mode: ThemeMode) {
        themeMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: Self.themeKey)
    }

    // MARK: - 备份

    func exportText() -> String {
        SharedConfig.exportText(config)
    }

    @discardableResult
    func importText(_ text: String) -> Bool {
        guard let imported = SharedConfig.importText(text) else { return false }
        config = imported
        persist()
        return true
    }

    // MARK: - 持久化

    private func persist() {
        config.updatedAt = .now
        SharedConfig.save(config)
    }
}
