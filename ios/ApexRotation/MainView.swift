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
    @State private var store = ConfigStore()
    @State private var showCalibration = false

    @Environment(\.colorScheme) private var colorScheme

    private var palette: Palette { .forScheme(colorScheme) }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            content(now: context.date)
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

    @ViewBuilder
    private func content(now: Date) -> some View {
        let slots = store.upcoming(at: now, count: 6)

        ScrollView {
            VStack(spacing: 0) {
                header

                if let current = slots.first {
                    hero(current, now: now)

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
                        .font(TypeScale.body)
                        .foregroundStyle(palette.ink3)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
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
                    .tracking(1.7)
                    .foregroundStyle(palette.ink2)
            }

            HStack {
                iconButton(systemName: "slider.horizontal.3") {
                    showCalibration = true
                }
                .accessibilityLabel("校准与设置")

                Spacer()

                themeButton
            }
        }
        .frame(height: 46)
    }

    private func iconButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(palette.ink2)
                .frame(width: 34, height: 34)
                .background(palette.fill, in: Circle())
        }
        .buttonStyle(.plain)
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
                .frame(width: 34, height: 34)
                .background(palette.fill, in: Circle())
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isDark ? "切换到亮色" : "切换到暗色")
    }

    // MARK: - 当前地图

    private func hero(_ slot: RotationSlot, now: Date) -> some View {
        ZStack(alignment: .bottomLeading) {
            if let image = MapArt.image(for: slot.map.art) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.black
            }

            LinearGradient(
                colors: [.black.opacity(0.10), .black.opacity(0.30), .black.opacity(0.90)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(TimeFormat.range(slot.start, slot.end))
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.72))

                Text(slot.map.name)
                    .font(TypeScale.mapName)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("剩余")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.62))
                    Text(TimeFormat.countdown(slot.remaining(at: now)))
                        .font(.system(size: 22, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white)
                }
                .padding(.top, 4)
            }
            .padding(16)
            .padding(.bottom, 8)
        }
        .frame(height: 344)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(alignment: .topLeading) {
            Text("当前")
                .font(.system(size: 10, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(.black.opacity(0.44), in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.16), lineWidth: 1))
                .padding(13)
        }
        .overlay(alignment: .bottom) {
            progressBar(progress: slot.progress(at: now))
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
    }

    private func progressBar(progress: Double) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.24))
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
            thumbnail(slot.map.thumb, size: 60, radius: 12)

            VStack(alignment: .leading, spacing: 1) {
                Text("下一张")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.ink3)
                Text(slot.map.name)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(palette.ink1)
                    .lineLimit(1)
                Text(TimeFormat.range(slot.start, slot.end))
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(palette.ink3)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 1) {
                Text(TimeFormat.clock.string(from: slot.start))
                    .font(.system(size: 17, weight: .bold).monospacedDigit())
                    .foregroundStyle(palette.ink1)
                Text(TimeFormat.relative(from: now, to: slot.start))
                    .font(.system(size: 11))
                    .foregroundStyle(palette.ink3)
            }
        }
        .padding(12)
        .card(palette, radius: 12)
        .padding(.top, 12)
    }

    // MARK: - 之后

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(TypeScale.section)
            .foregroundStyle(palette.ink3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 18)
            .padding(.bottom, 8)
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
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
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
        .card(palette, radius: 12)
    }

    private func footer(now: Date) -> some View {
        HStack {
            Text("本地推算 · \(TimeFormat.ago(from: now, to: store.config.updatedAt))校准")
                .font(.system(size: 11))
                .foregroundStyle(palette.ink4)
            Spacer()
        }
        .padding(.top, 14)
    }

    @ViewBuilder
    private func thumbnail(_ base: String, size: CGFloat, radius: CGFloat) -> some View {
        if let image = MapArt.image(for: base) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(palette.fill)
                .frame(width: size, height: size)
        }
    }
}
