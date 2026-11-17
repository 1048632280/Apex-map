import SwiftUI
import UIKit

struct CalibrationView: View {
    @ObservedObject var store: ConfigStore

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var selectedIndex = 0
    @State private var switchTime = Date()
    @State private var hours = 4
    @State private var minutes = 30
    @State private var notice = ""

    private var palette: Palette { .forScheme(colorScheme) }
    private var durationSeconds: Int { max(300, hours * 3600 + minutes * 60) }
    private var minuteOptions: [Int] { Array(stride(from: 0, to: 60, by: 5)) }

    var body: some View {
        NavigationView {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    calibrationCard
                    durationCard
                    orderCard
                    dataCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 36)
            }
            .background(palette.page.ignoresSafeArea())
            .navigationTitle("校准")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .onAppear { loadCurrentState() }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - 当前状态

    private var calibrationCard: some View {
        VStack(spacing: 0) {
            sectionTitle("现在游戏里是哪张图")

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 96), spacing: 10)],
                spacing: 10
            ) {
                ForEach(Array(store.config.maps.enumerated()), id: \.element.id) { index, map in
                    mapCell(map, index: index)
                }
            }
            .padding(.horizontal, 14)

            divider.padding(.top, 14)

            HStack {
                Text("这张图结束于")
                    .font(.system(size: 15))
                    .foregroundStyle(palette.ink1)
                Spacer(minLength: 8)
                DatePicker("", selection: $switchTime, displayedComponents: .hourAndMinute)
                    .labelsHidden()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Text(previewText)
                .font(.system(size: 12))
                .foregroundStyle(palette.ink3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.bottom, 4)

            if !isPlausible {
                Text("结束时间应该在 \(TimeFormat.duration(seconds: durationSeconds))以内")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.top, 4)
            }

            Button {
                apply()
            } label: {
                Text("应用校准")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(palette.onAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(
                        palette.accent,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!isPlausible)
            .opacity(isPlausible ? 1 : 0.45)
            .padding(14)
        }
        .card(palette, radius: 16)
    }

    private func mapCell(_ map: MapEntry, index: Int) -> some View {
        Button {
            selectedIndex = index
            switchTime = suggestedSwitchTime()
        } label: {
            ZStack(alignment: .bottomLeading) {
                Color.clear
                    .frame(height: 62)
                    .overlay { artwork(map.thumb) }
                    .clipped()

                LinearGradient(
                    colors: [Color.clear, Color.black.opacity(0.78)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                Text(map.name)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 5)
                    .padding(.bottom, 4)
            }
            .frame(height: 62)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(selectedIndex == index ? palette.accent : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 时长（滚轮选数字）

    private var durationCard: some View {
        VStack(spacing: 0) {
            HStack {
                Text("每张图时长")
                    .font(.system(size: 15))
                    .foregroundStyle(palette.ink1)
                Spacer(minLength: 8)
                Text(TimeFormat.duration(seconds: durationSeconds))
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .foregroundStyle(palette.ink2)
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 2)

            HStack(spacing: 0) {
                Picker("", selection: $hours) {
                    ForEach(0...12, id: \.self) { value in
                        Text("\(value) 小时").tag(value)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)
                .clipped()

                Picker("", selection: $minutes) {
                    ForEach(minuteOptions, id: \.self) { value in
                        Text("\(value) 分").tag(value)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)
                .clipped()
            }
            .frame(height: 132)
            .padding(.horizontal, 6)
        }
        .card(palette, radius: 16)
        .onChange(of: hours) { _ in commitDuration() }
        .onChange(of: minutes) { _ in commitDuration() }
    }

    // MARK: - 顺序

    private var orderCard: some View {
        VStack(spacing: 0) {
            sectionTitle("轮换顺序")

            ForEach(Array(store.config.maps.enumerated()), id: \.element.id) { index, map in
                HStack(spacing: 11) {
                    thumbnail(map.thumb, size: 28, radius: 7)

                    Text(map.name)
                        .font(.system(size: 15))
                        .foregroundStyle(palette.ink1)

                    Spacer(minLength: 8)

                    HStack(spacing: 14) {
                        Button {
                            move(index, by: -1)
                        } label: {
                            Image(systemName: "chevron.up")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(index == 0 ? palette.ink4 : palette.ink2)
                                .frame(width: 30, height: 30)
                        }
                        .buttonStyle(.plain)
                        .disabled(index == 0)

                        Button {
                            move(index, by: 1)
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(index == store.config.maps.count - 1 ? palette.ink4 : palette.ink2)
                                .frame(width: 30, height: 30)
                        }
                        .buttonStyle(.plain)
                        .disabled(index == store.config.maps.count - 1)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)

                if index < store.config.maps.count - 1 {
                    divider.padding(.leading, 53)
                }
            }
        }
        .card(palette, radius: 16)
    }

    // MARK: - 数据

    private var dataCard: some View {
        VStack(spacing: 0) {
            Button {
                UIPasteboard.general.string = store.exportText()
                notice = "配置 JSON 已复制"
            } label: {
                row("复制配置 JSON") {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 14))
                        .foregroundStyle(palette.ink3)
                }
            }
            .buttonStyle(.plain)

            divider.padding(.leading, 14)

            Button {
                importFromPasteboard()
            } label: {
                row("从剪贴板导入") {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 14))
                        .foregroundStyle(palette.ink3)
                }
            }
            .buttonStyle(.plain)

            divider.padding(.leading, 14)

            HStack {
                Button {
                    store.reset()
                    loadCurrentState()
                    notice = "已重置"
                } label: {
                    Text("重置为默认配置")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(palette.accent)
                }
                .buttonStyle(.plain)

                Spacer(minLength: 8)

                if !notice.isEmpty {
                    Text(notice)
                        .font(.system(size: 11))
                        .foregroundStyle(palette.ink3)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .card(palette, radius: 16)
    }

    // MARK: - 零件

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(palette.ink3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 10)
    }

    private var divider: some View {
        Rectangle()
            .fill(palette.hairline)
            .frame(height: 1)
    }

    private func row<Content: View>(_ title: String, @ViewBuilder trailing: () -> Content) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 15))
                .foregroundStyle(palette.ink1)
            Spacer(minLength: 12)
            trailing()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

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

    // MARK: - 逻辑

    private var resolvedSwitchTime: Date {
        let now = Date()
        guard switchTime <= now.addingTimeInterval(60) else { return switchTime }
        return Calendar.current.date(byAdding: .day, value: 1, to: switchTime) ?? switchTime
    }

    private var isPlausible: Bool {
        RotationEngine.isPlausible(
            nextSwitchAt: resolvedSwitchTime,
            now: .now,
            secondsPerMap: durationSeconds
        )
    }

    private var previewText: String {
        guard store.config.maps.indices.contains(selectedIndex) else { return "--" }
        let map = store.config.maps[selectedIndex]
        let nextIndex = (selectedIndex + 1) % store.config.maps.count
        let nextName = store.config.maps[nextIndex].name
        return "将推算为 \(map.name) \(TimeFormat.clock.string(from: resolvedSwitchTime)) 结束，之后是 \(nextName)"
    }

    private func suggestedSwitchTime() -> Date {
        if store.isCalibrated, let slot = store.currentSlot(at: .now) {
            return slot.end
        }
        return Date().addingTimeInterval(Double(durationSeconds))
    }

    private func loadCurrentState() {
        let seconds = store.config.secondsPerMap
        hours = min(12, max(0, seconds / 3600))
        minutes = min(55, max(0, ((seconds % 3600) / 60 / 5) * 5))

        if store.isCalibrated, let slot = store.currentSlot(at: .now) {
            selectedIndex = store.config.maps.firstIndex(of: slot.map) ?? 0
            switchTime = slot.end
        } else {
            selectedIndex = 0
            switchTime = suggestedSwitchTime()
        }
    }

    private func commitDuration() {
        store.setSecondsPerMap(durationSeconds)
        notice = "时长改为 \(TimeFormat.duration(seconds: durationSeconds))"
    }

    private func apply() {
        store.setSecondsPerMap(durationSeconds)
        store.calibrate(currentMapIndex: selectedIndex, nextSwitchAt: resolvedSwitchTime)
        dismiss()
    }

    private func importFromPasteboard() {
        guard let text = UIPasteboard.general.string else {
            notice = "剪贴板是空的"
            return
        }
        if store.importText(text) {
            loadCurrentState()
            notice = "已导入配置"
        } else {
            notice = "剪贴板内容不是有效配置"
        }
    }

    private func move(_ index: Int, by offset: Int) {
        let target = index + offset
        guard store.config.maps.indices.contains(index),
              store.config.maps.indices.contains(target) else {
            return
        }
        store.moveMaps(from: IndexSet(integer: index), to: target > index ? target + 1 : target)
    }
}
