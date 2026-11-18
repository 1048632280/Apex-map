import SwiftUI
import UIKit

enum BrandAsset {
    static let logo: UIImage? = {
        guard let url = Bundle.main.url(forResource: "apex-icon-192", withExtension: "png") else {
            return nil
        }
        return UIImage(contentsOfFile: url.path)
    }()
}

// MARK: - 主界面（固定一屏，不滚动）

struct MainView: View {
    @StateObject private var store = ConfigStore()
    @State private var showCalibration = false

    @Environment(\.colorScheme) private var colorScheme

    private var palette: Palette { .forScheme(colorScheme) }

    var body: some View {
        // 15 秒一次重建外层，用于跨换图边界时切换当前地图；
        // 倒计时本身由 hero 内部的 1 秒时间线负责。
        TimelineView(.periodic(from: .now, by: 15)) { _ in
            GeometryReader { proxy in
                layout(size: proxy.size)
            }
        }
        .background(palette.page.ignoresSafeArea())
        .animation(.easeInOut(duration: 0.3), value: colorScheme)
        .preferredColorScheme(store.themeMode.colorScheme)
        .sheet(isPresented: $showCalibration) {
            CalibrationView(store: store)
        }
        .task {
            if !store.isCalibrated {
                showCalibration = true
            }
        }
    }

    // MARK: - 尺寸策略

    private struct Metrics {
        let size: CGSize

        var horizontal: CGFloat { size.width < 360 ? 14 : 18 }
        var gap: CGFloat { size.height < 620 ? 8 : (size.height < 720 ? 10 : 12) }
        var top: CGFloat { 2 }
        var bottom: CGFloat { 8 }
        /// 屏幕越矮，下面列出的排程越少，保证首页永远装得下
        var listRows: Int {
            if size.height < 620 { return 2 }
            if size.height < 720 { return 3 }
            return 4
        }
    }

    private func layout(size: CGSize) -> some View {
        let metrics = Metrics(size: size)
        let slots = store.upcoming(at: .now, count: 2 + metrics.listRows)

        return VStack(spacing: metrics.gap) {
            header

            if let current = slots.first {
                hero(current)
                    .layoutPriority(1)

                if slots.count > 1 {
                    nextCard(slots[1])
                }

                if slots.count > 2 {
                    sectionLabel("之后")
                    upcomingList(Array(slots[2...].prefix(metrics.listRows)))
                }
            } else {
                Spacer(minLength: 0)
                Text("还没有可用的轮换配置")
                    .font(.system(size: 15))
                    .foregroundStyle(palette.ink3)
                    .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            }

            footer()
        }
        .padding(.horizontal, metrics.horizontal)
        .padding(.top, metrics.top)
        .padding(.bottom, metrics.bottom)
    }

    // MARK: - 顶栏

    private var header: some View {
        ZStack {
            HStack(spacing: 7) {
                if let logo = BrandAsset.logo {
                    Image(uiImage: logo)
                        .resizable()
                        .frame(width: 18, height: 18)
                }
                Text("APEX LEGENDS")
                    .font(.system(size: 11, weight: .black))
                    .kerning(1.7)
                    .foregroundStyle(palette.ink2)
            }
            .frame(maxWidth: .infinity)

            HStack {
                iconButton(systemName: "slider.horizontal.3") {
                    showCalibration = true
                }
                .accessibilityLabel("校准与设置")

                Spacer()

                themeButton
            }
        }
        .frame(height: 44)
    }

    private func iconButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(palette.ink2)
                .frame(width: 36, height: 36)
                .background(palette.fill, in: Circle())
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
    }

    private var themeButton: some View {
        let isDark = colorScheme == .dark
        return Button {
            withAnimation(.easeInOut(duration: 0.3)) {
                store.toggleTheme()
            }
        } label: {
            Image(systemName: isDark ? "sun.max" : "moon")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.ink2)
                .rotationEffect(.degrees(isDark ? 0 : 180))
                .animation(.easeInOut(duration: 0.3), value: isDark)
                .frame(width: 36, height: 36)
                .background(palette.fill, in: Circle())
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .accessibilityLabel(isDark ? "切换到亮色" : "切换到暗色")
    }

    // MARK: - 当前地图（吃掉剩余空间）

    private func hero(_ slot: RotationSlot) -> some View {
        ZStack(alignment: .bottomLeading) {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay { artwork(slot.map.art) }
                .clipped()

            LinearGradient(
                colors: [.black.opacity(0.06), .black.opacity(0.34), .black.opacity(0.92)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 6) {
                Text(TimeFormat.range(slot.start, slot.end))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.75))

                Text(slot.map.name)
                    .font(.system(size: 30, weight: .heavy))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                HeroCountdown(slot: slot, tint: palette.accent)
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(alignment: .topLeading) {
            Text("当前")
                .font(.system(size: 10, weight: .bold))
                .kerning(0.6)
                .foregroundStyle(.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.44), in: Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.16), lineWidth: 1))
                .padding(14)
        }
    }

    // MARK: - 下一张

    private func nextCard(_ slot: RotationSlot) -> some View {
        let now = Date()
        return HStack(spacing: 12) {
            thumbnail(slot.map.thumb, size: 56, radius: 12)

            VStack(alignment: .leading, spacing: 2) {
                Text("下一张")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.ink3)
                Text(slot.map.name)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(palette.ink1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(TimeFormat.range(slot.start, slot.end))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(palette.ink3)
            }

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 2) {
                Text(TimeFormat.clock.string(from: slot.start))
                    .font(.system(size: 17, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.ink1)
                Text(TimeFormat.relative(from: now, to: slot.start))
                    .font(.system(size: 11))
                    .foregroundStyle(palette.ink3)
            }
        }
        .padding(12)
        .card(palette, radius: 14)
    }

    // MARK: - 之后

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(palette.ink3)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func upcomingList(_ slots: [RotationSlot]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(slots.enumerated()), id: \.element.id) { index, slot in
                HStack(spacing: 11) {
                    thumbnail(slot.map.thumb, size: 26, radius: 7)
                    Text(slot.map.name)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(palette.ink1)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 8)
                    Text(TimeFormat.clock.string(from: slot.start))
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(palette.ink2)
                }
                .padding(.vertical, 8)

                if index < slots.count - 1 {
                    Rectangle()
                        .fill(palette.hairline)
                        .frame(height: 1)
                }
            }
        }
        .padding(.horizontal, 14)
        .card(palette, radius: 14)
    }

    private func footer() -> some View {
        let stamp = store.config.calibratedAt ?? store.config.updatedAt
        return HStack {
            Text("每张 \(TimeFormat.duration(seconds: store.config.secondsPerMap)) · \(TimeFormat.ago(from: Date(), to: stamp))校准")
                .font(.system(size: 11))
                .foregroundStyle(palette.ink4)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 0)
        }
    }

    // MARK: - 图片

    @ViewBuilder
    private func artwork(_ base: String) -> some View {
        if let image = MapArt.image(for: base) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            palette.fill
        }
    }

    private func thumbnail(_ base: String, size: CGFloat, radius: CGFloat) -> some View {
        Color.clear
            .frame(width: size, height: size)
            .overlay { artwork(base) }
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

// MARK: - 每秒只重绘这一小块

private struct HeroCountdown: View {
    let slot: RotationSlot
    let tint: Color

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("剩余")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.65))
                    Text(TimeFormat.countdown(slot.remaining(at: context.date)))
                        .font(.system(size: 22, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white)
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.24))
                        Capsule()
                            .fill(tint)
                            .frame(width: proxy.size.width * min(1, max(0, slot.progress(at: context.date))))
                    }
                }
                .frame(height: 3)
            }
        }
    }
}
