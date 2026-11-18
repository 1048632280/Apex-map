import SwiftUI
import WidgetKit

// MARK: - 数据

struct RotationEntry: TimelineEntry {
    let date: Date
    let current: RotationSlot
    let upcoming: [RotationSlot]
    let calibrated: Bool
}

extension RotationEntry {
    static var placeholder: RotationEntry {
        let config = RotationConfig.fallback
        let now = Date()
        let slot = RotationEngine.slot(at: now, config: config)
            ?? RotationSlot(map: SeedMaps.entries[0], start: now, end: now.addingTimeInterval(3600))
        let upcoming = Array(RotationEngine.upcoming(at: now, config: config, count: 4).dropFirst())
        return RotationEntry(date: now, current: slot, upcoming: upcoming, calibrated: true)
    }
}

struct RotationProvider: TimelineProvider {
    func placeholder(in context: Context) -> RotationEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (RotationEntry) -> Void) {
        completion(.placeholder)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RotationEntry>) -> Void) {
        let config = SharedConfig.load()
        completion(Timeline(entries: Self.makeEntries(config: config, now: .now), policy: .atEnd))
    }

    /// 只按换图边界和半小时粒度给条目：没有进度环了，不需要更密
    static func makeEntries(config: RotationConfig, now: Date) -> [RotationEntry] {
        var dates: [Date] = [now]
        for step in 1...10 {
            dates.append(now.addingTimeInterval(Double(step) * 1800))
        }
        for step in 1...8 {
            dates.append(now.addingTimeInterval(5 * 3600 + Double(step) * 3600))
        }

        return Array(Set(dates)).sorted().compactMap { date in
            guard let slot = RotationEngine.slot(at: date, config: config) else { return nil }
            let upcoming = RotationEngine.upcoming(at: date, config: config, count: 4).dropFirst()
            return RotationEntry(
                date: date,
                current: slot,
                upcoming: Array(upcoming),
                calibrated: config.calibrated
            )
        }
    }
}

// MARK: - 小组件

struct SmallCurrentWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "small_current", provider: RotationProvider()) { entry in
            if entry.calibrated {
                SmallCurrentView(entry: entry)
            } else {
                UncalibratedWidgetView()
            }
        }
        .configurationDisplayName("当前地图")
        .description("地图大图、名称和剩余时间。")
        .supportedFamilies([.systemSmall])
    }
}

struct SmallCountdownWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "small_countdown", provider: RotationProvider()) { entry in
            if entry.calibrated {
                SmallCountdownView(entry: entry)
            } else {
                UncalibratedWidgetView()
            }
        }
        .configurationDisplayName("只看倒计时")
        .description("超大数字，一眼看到还剩多久。")
        .supportedFamilies([.systemSmall])
    }
}

struct SmallNextWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "small_next", provider: RotationProvider()) { entry in
            if entry.calibrated {
                SmallNextView(entry: entry)
            } else {
                UncalibratedWidgetView()
            }
        }
        .configurationDisplayName("下一张")
        .description("下一张地图的大图和切换时间。")
        .supportedFamilies([.systemSmall])
    }
}

struct MediumSplitWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "medium_split", provider: RotationProvider()) { entry in
            if entry.calibrated {
                MediumSplitView(entry: entry)
            } else {
                UncalibratedWidgetView()
            }
        }
        .configurationDisplayName("当前 + 下一张（分栏）")
        .description("左边当前地图大图，右边下一张。")
        .supportedFamilies([.systemMedium])
    }
}

struct MediumDualWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "medium_dual", provider: RotationProvider()) { entry in
            if entry.calibrated {
                MediumDualView(entry: entry)
            } else {
                UncalibratedWidgetView()
            }
        }
        .configurationDisplayName("当前 + 下一张（整图）")
        .description("一整张地图大图，左右分栏。")
        .supportedFamilies([.systemMedium])
    }
}

struct LargeListWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "large_list", provider: RotationProvider()) { entry in
            if entry.calibrated {
                LargeListView(entry: entry)
            } else {
                UncalibratedWidgetView()
            }
        }
        .configurationDisplayName("大图 + 排程")
        .description("上方当前地图大图，下方接下来三张。")
        .supportedFamilies([.systemLarge])
    }
}

struct LargeOverlayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "large_overlay", provider: RotationProvider()) { entry in
            if entry.calibrated {
                LargeOverlayView(entry: entry)
            } else {
                UncalibratedWidgetView()
            }
        }
        .configurationDisplayName("沉浸大图")
        .description("整张大图，信息压在底部。")
        .supportedFamilies([.systemLarge])
    }
}

@main
struct ApexWidgetsBundle: WidgetBundle {
    var body: some Widget {
        SmallCurrentWidget()
        SmallCountdownWidget()
        SmallNextWidget()
        MediumSplitWidget()
        MediumDualWidget()
        LargeListWidget()
        LargeOverlayWidget()
    }
}
