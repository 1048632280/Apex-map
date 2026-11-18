import Foundation
import Combine
import SwiftUI

final class ConfigStore: ObservableObject {
    private static let themeKey = "themeMode"
    private static let durationMigratedKey = "durationMigratedTo270"

    @Published private(set) var config: RotationConfig
    @Published private(set) var themeMode: ThemeMode

    init() {
        var loaded = SharedConfig.load()
        // 旧版本默认是 60 分钟；只迁移一次，避免覆盖用户后来手动选的 1 小时
        if !UserDefaults.standard.bool(forKey: Self.durationMigratedKey) {
            UserDefaults.standard.set(true, forKey: Self.durationMigratedKey)
            if loaded.secondsPerMap == 3600 {
                loaded.secondsPerMap = RotationConfig.defaultSecondsPerMap
                SharedConfig.save(loaded)
            }
        }
        self.config = loaded

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
        config.calibratedAt = .now
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
        invalidateCalibration()
        persist()
    }

    func toggleMap(_ map: MapEntry) {
        if let index = config.maps.firstIndex(where: { $0.slug == map.slug }) {
            guard config.maps.count > 1 else { return }
            config.maps.remove(at: index)
        } else {
            config.maps.append(map)
        }
        invalidateCalibration()
        persist()
    }

    func moveMap(from source: Int, to destination: Int) {
        guard config.maps.indices.contains(source),
              config.maps.indices.contains(destination),
              source != destination else { return }
        let map = config.maps.remove(at: source)
        config.maps.insert(map, at: destination)
        invalidateCalibration()
        persist()
    }

    private func invalidateCalibration() {
        config.calibrated = false
        config.calibratedAt = nil
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
