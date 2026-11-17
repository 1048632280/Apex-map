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

// MARK: - 主界面

struct MainView: View {
    @StateObject private var store = ConfigStore()
    @State private var showCalibration = false

    @Environment(\.colorScheme) private var colorScheme

    private var palette: Palette { .forScheme(colorScheme) }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            GeometryReader { proxy in
                content(now: context.date, size: proxy.size)
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

    // MARK: - 布局指标（按屏幕尺寸算，不写死）

    private struct Metrics {
        let size: CGSize

        var horizontal: CGFloat { size.width < 360 ? 14 : 18 }
        var gap: CGFloat { size.height < 700 ? 10 : 14 }
        var heroHeight: CGFloat { min(max(size.height * 0.36, 220), 392) }
        var bottomPadding: CGFloat { 24 }
    }

    @ViewBuilder
    private func content(now: Date, size: CGSize) -> some View {
        let metrics = Metrics(size: size)
        let slots = store.upcoming(at: now, count: 6)

        ScrollView(showsIndicators: false) {
            VStack(spacing: metrics.gap) {
                header

                if let current = slots.first {
                    hero(current, now: now, height: metrics.heroHeight)

                    if slots.count > 1 {
                        nextCard(slots[1], now: now)
                    }

                    if slots.count > 2 {
                        sectionLabel("之后")
                        upcomingList(Array(slots[2...].prefix(4)))
                    }

                    footer(now: now)
                } else {
                    Text("还没有可用的轮换配置")
                        .font(.system(size: 15))
                        .foregroundStyle(palette.ink3)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                }
            }
            .padding(.horizontal, metrics.horizontal)
            .padding(.bottom, metrics.bottomPadding)
        }
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

    // MARK: - 当前地图

    private func hero(_ slot: RotationSlot, now: Date, height: CGFloat) -> some View {
        ZStack(alignment: .bottomLeading) {
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: height)
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
                    .font(.system(size: height < 300 ? 28 : 33, weight: .heavy))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("剩余")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.65))
                    Text(TimeFormat.countdown(slot.remaining(at: now)))
                        .font(.system(size: 22, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white)
                }
                .padding(.top, 2)
            }
            .padding(18)
            .padding(.bottom, 6)

            VStack {
                Spacer(minLength: 0)
                progressBar(progress: slot.progress(at: now))
                    .padding(.horizontal, 18)
                    .padding(.bottom, 14)
            }
        }
        .frame(height: height)
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

    private func progressBar(progress: Double) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.24))
                Capsule()
                    .fill(palette.accent)
                    .frame(width: proxy.size.width * min(1, max(0, progress)))
            }
        }
        .frame(height: 3)
    }

    // MARK: - 下一张

    private func nextCard(_ slot: RotationSlot, now: Date) -> some View {
        HStack(spacing: 12) {
            thumbnail(slot.map.thumb, size: 56, radius: 12)

            VStack(alignment: .leading, spacing: 2) {
                Text("下一张")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.ink3)
                Text(slot.map.name)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(palette.ink1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
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
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(palette.ink3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
    }

    private func upcomingList(_ slots: [RotationSlot]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(slots.enumerated()), id: \.element.id) { index, slot in
                HStack(spacing: 11) {
                    thumbnail(slot.map.thumb, size: 28, radius: 7)
                    Text(slot.map.name)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(palette.ink1)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(TimeFormat.clock.string(from: slot.start))
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(palette.ink2)
                }
                .padding(.vertical, 9)

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

    private func footer(now: Date) -> some View {
        HStack {
            Text("本地推算 · 每张 \(TimeFormat.duration(seconds: store.config.secondsPerMap)) · \(TimeFormat.ago(from: now, to: store.config.updatedAt))校准")
                .font(.system(size: 11))
                .foregroundStyle(palette.ink4)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
        .padding(.top, 2)
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
