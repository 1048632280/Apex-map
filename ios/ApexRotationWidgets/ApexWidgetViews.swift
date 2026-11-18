import SwiftUI
import UIKit
import WidgetKit

/// iOS 17 起系统会自动加组件内容边距，低版本需要自己补
enum WidgetInset {
    static var value: CGFloat {
        if #available(iOS 17.0, *) { return 0 } else { return 13 }
    }
}

// MARK: - 通用零件

struct ArtBackground: View {
    let base: String
    var strong: Bool = false

    var body: some View {
        ZStack {
            if let image = MapArt.image(for: base) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.black
            }

            LinearGradient(
                colors: strong
                    ? [.black.opacity(0.20), .black.opacity(0.55), .black.opacity(0.94)]
                    : [.black.opacity(0.06), .black.opacity(0.32), .black.opacity(0.90)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

struct CountdownText: View {
    let slot: RotationSlot
    var size: CGFloat

    var body: some View {
        Group {
            if #available(iOS 16.0, *) {
                Text(timerInterval: slot.start...slot.end, countsDown: true)
            } else {
                // iOS 15：日期文本样式同样由系统每秒刷新，不依赖 timeline 刷新
                Text(slot.end, style: .timer)
            }
        }
        .font(.system(size: size, weight: .semibold, design: .monospaced))
        .foregroundStyle(.white)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
}

// MARK: - 组件背景（iOS 17 用 containerBackground，低版本用 background）

struct WidgetBackground<Background: View>: ViewModifier {
    let background: Background

    func body(content: Content) -> some View {
        Group {
            if #available(iOS 17.0, *) {
                content.containerBackground(for: .widget) { background }
            } else {
                content.background(background)
            }
        }
    }
}

extension View {
    func widgetBackground<Background: View>(@ViewBuilder _ background: () -> Background) -> some View {
        modifier(WidgetBackground(background: background()))
    }
}

struct ProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.24))
                Capsule()
                    .fill(Color(hex: 0xFFB4B8))
                    .frame(width: proxy.size.width * min(1, max(0, progress)))
            }
        }
    }
}

struct RingView<Content: View>: View {
    let progress: Double
    var lineWidth: CGFloat = 7
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.22), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(.white, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            content()
        }
    }
}

struct WidgetLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .tracking(1.0)
            .foregroundStyle(.white.opacity(0.72))
    }
}

struct UncalibratedWidgetView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 18))
            Text("打开 App 校准")
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetBackground {
            Color(uiColor: .secondarySystemGroupedBackground)
        }
    }
}

// MARK: - 小尺寸

struct SmallCurrentView: View {
    let entry: RotationEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)
            WidgetLabel(text: "当前")
            Text(entry.current.map.name)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            CountdownText(slot: entry.current, size: 18)
                .padding(.top, 2)
            Spacer().frame(height: 8)
            ProgressBar(progress: entry.current.progress(at: entry.date))
                .frame(height: 3)
        }
        .padding(WidgetInset.value)
        .widgetBackground {
            ArtBackground(base: entry.current.map.art, strong: true)
        }
    }
}

struct SmallCountdownView: View {
    let entry: RotationEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Spacer(minLength: 0)
            Text(entry.current.map.name)
                .font(.system(size: 10, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(.white.opacity(0.82))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            CountdownText(slot: entry.current, size: 30)
        }
        .padding(WidgetInset.value)
        .widgetBackground {
            ArtBackground(base: entry.current.map.art, strong: true)
        }
    }
}

struct SmallRingView: View {
    let entry: RotationEntry

    var body: some View {
        VStack(spacing: 7) {
            RingView(progress: entry.current.progress(at: entry.date), lineWidth: 8) {
                Text("\(Int((entry.current.progress(at: entry.date) * 100).rounded()))%")
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
            }
            .frame(width: 92, height: 92)

            Text(entry.current.map.name)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(WidgetInset.value)
        .widgetBackground {
            ArtBackground(base: entry.current.map.art, strong: true)
        }
    }
}

struct SmallRingNameView: View {
    let entry: RotationEntry

    var body: some View {
        RingView(progress: entry.current.progress(at: entry.date), lineWidth: 7) {
            VStack(spacing: 3) {
                CountdownText(slot: entry.current, size: 15)
                Text(entry.current.map.name)
                    .font(.system(size: 10, weight: .bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 12)
            }
        }
        .frame(width: 106, height: 106)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(WidgetInset.value)
        .widgetBackground {
            ArtBackground(base: entry.current.map.art, strong: true)
        }
    }
}

// MARK: - 中尺寸

struct MediumSplitView: View {
    let entry: RotationEntry

    private var next: RotationSlot? { entry.upcoming.first }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Spacer(minLength: 0)
                WidgetLabel(text: "当前")
                Text(entry.current.map.name)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                CountdownText(slot: entry.current, size: 22)
                    .padding(.top, 2)
                Spacer().frame(height: 8)
                ProgressBar(progress: entry.current.progress(at: entry.date))
                    .frame(width: 140, height: 3)
            }
            .padding(WidgetInset.value)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 0) {
                Text("下一张")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)

                Text(next?.map.name ?? "--")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .padding(.top, 4)

                Spacer(minLength: 0)

                if let next {
                    Text(TimeFormat.clock.string(from: next.start))
                        .font(.system(size: 19, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.primary)
                    Text(TimeFormat.relative(from: entry.date, to: next.start))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.top, 1)
                }
            }
            .padding(WidgetInset.value)
            .frame(width: 148, alignment: .leading)
            .frame(maxHeight: .infinity)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
        }
        .widgetBackground {
            ArtBackground(base: entry.current.map.art)
        }
    }
}

struct MediumDualView: View {
    let entry: RotationEntry

    private var next: RotationSlot? { entry.upcoming.first }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Spacer(minLength: 0)
                WidgetLabel(text: "当前")
                Text(entry.current.map.name)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                CountdownText(slot: entry.current, size: 19)
                    .padding(.top, 2)
            }
            .padding(WidgetInset.value)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

            Rectangle()
                .fill(.white.opacity(0.18))
                .frame(width: 1)
                .padding(.vertical, 13)

            VStack(alignment: .trailing, spacing: 2) {
                Spacer(minLength: 0)
                WidgetLabel(text: "下一张")
                Text(next?.map.name ?? "--")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let next {
                    Text(TimeFormat.clock.string(from: next.start))
                        .font(.system(size: 17, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.top, 2)
                }
            }
            .padding(WidgetInset.value)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        }
        .widgetBackground {
            ArtBackground(base: entry.current.map.art, strong: true)
        }
    }
}

// MARK: - 大尺寸

struct LargeListView: View {
    let entry: RotationEntry

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                Color.clear
                    .frame(height: 206)
                    .overlay {
                        ArtBackground(base: entry.current.map.art)
                    }
                    .clipped()

                VStack(alignment: .leading, spacing: 2) {
                    WidgetLabel(text: "当前")
                    Text(entry.current.map.name)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    CountdownText(slot: entry.current, size: 24)
                        .padding(.top, 2)
                }
                .padding(WidgetInset.value)
            }
            .frame(height: 206)

            VStack(spacing: 0) {
                ForEach(Array(entry.upcoming.prefix(3).enumerated()), id: \.element.id) { index, slot in
                    WidgetSlotRow(slot: slot, isNext: index == 0, onArt: false)
                    if index < min(3, entry.upcoming.count) - 1 {
                        Rectangle()
                            .fill(Color(uiColor: .separator))
                            .frame(height: 1)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 2)

            Spacer(minLength: 0)
        }
        .widgetBackground {
            Color(uiColor: .secondarySystemGroupedBackground)
        }
    }
}

struct LargeOverlayView: View {
    let entry: RotationEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetLabel(text: "当前")
            Text(entry.current.map.name)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)

            Spacer(minLength: 0)

            CountdownText(slot: entry.current, size: 26)

            VStack(spacing: 0) {
                ForEach(Array(entry.upcoming.prefix(3).enumerated()), id: \.element.id) { index, slot in
                    WidgetSlotRow(slot: slot, isNext: index == 0, onArt: true)
                        .padding(.vertical, 1)
                    if index < min(3, entry.upcoming.count) - 1 {
                        Rectangle()
                            .fill(.white.opacity(0.14))
                            .frame(height: 1)
                    }
                }
            }
            .padding(.top, 8)
        }
        .padding(WidgetInset.value)
        .widgetBackground {
            ArtBackground(base: entry.current.map.art, strong: true)
        }
    }
}

struct WidgetSlotRow: View {
    let slot: RotationSlot
    let isNext: Bool
    let onArt: Bool

    private var timeColor: Color {
        onArt ? Color.white.opacity(0.7) : Color(uiColor: .secondaryLabel)
    }

    private var nameColor: Color {
        onArt ? Color.white : Color(uiColor: .label)
    }

    var body: some View {
        HStack(spacing: 9) {
            Text(TimeFormat.clock.string(from: slot.start))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(timeColor)
                .frame(width: 34, alignment: .leading)

            if let image = MapArt.image(for: slot.map.thumb) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 24, height: 24)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }

            Text(slot.map.name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(nameColor)
                .lineLimit(1)

            Spacer(minLength: 4)

            if isNext {
                Text("下一张")
                    .font(.system(size: 10))
                    .foregroundStyle(timeColor)
            }
        }
        .padding(.vertical, 6)
    }
}
