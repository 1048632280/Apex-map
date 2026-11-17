import Foundation
import UIKit

// MARK: - 共享配置（App Group）

enum SharedConfig {
    static let appGroup = "group.com.apexmap.rotation"
    static let fileName = "rotation.json"

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
    }

    /// App Group 不可用时退回 App 自己的目录，至少保证主 App 的校准不会丢。
    static func fileURL() -> URL? {
        if let container = containerURL {
            return container.appendingPathComponent(fileName)
        }
        return FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent(fileName)
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    static func load() -> RotationConfig {
        guard
            let url = fileURL(),
            let data = try? Data(contentsOf: url),
            let config = try? decoder().decode(RotationConfig.self, from: data),
            !config.maps.isEmpty
        else {
            return .fallback
        }
        return config
    }

    @discardableResult
    static func save(_ config: RotationConfig) -> Bool {
        guard let url = fileURL() else { return false }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try encoder().encode(config).write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    static func exportText(_ config: RotationConfig) -> String {
        guard let data = try? encoder().encode(config) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    static func importText(_ text: String) -> RotationConfig? {
        guard let data = text.data(using: .utf8) else { return nil }
        guard
            let config = try? decoder().decode(RotationConfig.self, from: data),
            !config.maps.isEmpty
        else {
            return nil
        }
        return config
    }
}

// MARK: - 地图图片（资源平铺在 bundle 里）

enum MapArt {
    private static let cache = NSCache<NSString, UIImage>()

    static func image(for base: String) -> UIImage? {
        guard !base.isEmpty else { return nil }
        if let cached = cache.object(forKey: base as NSString) {
            return cached
        }
        for directory in [nil, "image"] as [String?] {
            guard
                let url = Bundle.main.url(forResource: base, withExtension: "webp", subdirectory: directory),
                let image = UIImage(contentsOfFile: url.path)
            else {
                continue
            }
            cache.setObject(image, forKey: base as NSString)
            return image
        }
        return nil
    }
}
