import SwiftUI
import UIKit

struct CalibrationView: View {
    @ObservedObject var store: ConfigStore

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var selectedIndex = 0
    @State private var switchTime = Date()
    @State private var minutesText = ""
    @State private var notice = ""
    @State private var editingSequence = false

    private var palette: Palette { .forScheme(colorScheme) }
    private var columns: [GridItem] { Array(repeating: GridItem(.flexible(), spacing: 8), count: 3) }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 0) {
                    sectionLabel("现在游戏里是哪张图")
                    mapGrid

                    sectionLabel("轮换")
                    rotationCard

                    sectionLabel("数据")
                    dataCard
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .background(palette.page.ignoresSafeArea())
            .navigationTitle("校准")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .task { loadCurrentState() }
        }
    }

    // MARK: - 地图网格

    private var mapGrid: some View {
        VStack(spacing: 0) {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Array(store.config.maps.enumerated()), id: \.element.id) { index, map in
                    Button {
                        selectedIndex = index
                        switchTime = suggestedSwitchTime()
                    } label: {
                        ZStack(alignment: .bottomLeading) {
                            Color.clear
                                .frame(height: 64)
                                .overlay { thumbnail(map.thumb) }
                                .clipped()

                            Text(map.name)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    LinearGradient(
                                        colors: [.clear, .black.opacity(0.82)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(selectedIndex == index ? palette.accent : .clear, lineWidth: 2)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)

            divider

            row("这张图结束于") {
                DatePicker("", selection: $switchTime, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .environment(\.locale, Locale(identifier: "zh_CN"))
            }

            divider

            Text(previewText)
                .font(.system(size: 12))
                .foregroundStyle(palette.ink3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)

            if !isPlausible {
                Text("结束时间应该在 \(store.config.secondsPerMap / 60) 分钟以内，请检查选择的当前地图或时间。")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
            }

            Button {
                apply()
            } label: {
                Text("应用校准")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.onAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(palette.accent, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!isPlausible)
            .opacity(isPlausible ? 1 : 0.4)
            .padding(12)
        }
        .card(palette)
    }

    // MARK: - 轮换

    private var rotationCard: some View {
        VStack(spacing: 0) {
            row("每张图时长") {
                HStack(spacing: 4) {
                    TextField("60", text: $minutesText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 52)
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                        .foregroundStyle(palette.ink1)
                    Text("分钟")
                        .font(.system(size: 15))
                        .foregroundStyle(palette.ink3)
                }
                .onSubmit {
                    if let minutes = Int(minutesText) {
                        store.setSecondsPerMap(minutes * 60)
                        notice = "时长已更新"
                    }
                }
            }

            divider

            ForEach(Array(store.config.maps.enumerated()), id: \.element.id) { index, map in
                HStack(spacing: 11) {
                    thumbnail(map.thumb)
                        .frame(width: 28, height: 28)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                    Text(map.name)
                        .font(.system(size: 15))
                        .foregroundStyle(palette.ink1)

                    Spacer()

                    HStack(spacing: 10) {
                        Button {
                            move(index, by: -1)
                        } label: {
                            Image(systemName: "chevron.up")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(index == 0 ? palette.ink4 : palette.ink2)
                        }
                        .buttonStyle(.plain)
                        .disabled(index == 0)

                        Button {
                            move(index, by: 1)
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(index == store.config.maps.count - 1 ? palette.ink4 : palette.ink2)
                        }
                        .buttonStyle(.plain)
                        .disabled(index == store.config.maps.count - 1)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)

                if index < store.config.maps.count - 1 {
                    divider
                }
            }
        }
        .card(palette)
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

            divider

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

            divider

            HStack(spacing: 10) {
                Button {
                    store.reset()
                    loadCurrentState()
                    notice = "已重置为默认配置"
                } label: {
                    Text("重置为默认配置")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(palette.accent)
                }
                .buttonStyle(.plain)

                Spacer()

                if !notice.isEmpty {
                    Text(notice)
                        .font(.system(size: 11))
                        .foregroundStyle(palette.ink3)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
        }
        .card(palette)
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

    // MARK: - 零件

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(TypeScale.section)
            .foregroundStyle(palette.ink3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 20)
            .padding(.bottom, 8)
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
        .padding(.vertical, 11)
    }

    @ViewBuilder
    private func thumbnail(_ base: String) -> some View {
        if let image = MapArt.image(for: base) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            palette.fill
        }
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
            secondsPerMap: store.config.secondsPerMap
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
        return Date().addingTimeInterval(Double(store.config.secondsPerMap))
    }

    private func loadCurrentState() {
        minutesText = String(store.config.secondsPerMap / 60)
        if store.isCalibrated, let slot = store.currentSlot(at: .now) {
            selectedIndex = store.config.maps.firstIndex(of: slot.map) ?? 0
            switchTime = slot.end
        } else {
            selectedIndex = 0
            switchTime = suggestedSwitchTime()
        }
    }

    private func apply() {
        if let minutes = Int(minutesText), minutes >= 1, minutes <= 480 {
            store.setSecondsPerMap(minutes * 60)
        }
        store.calibrate(currentMapIndex: selectedIndex, nextSwitchAt: resolvedSwitchTime)
        notice = "已校准"
    }

    private func move(_ index: Int, by offset: Int) {
        let target = index + offset
        guard store.config.maps.indices.contains(index), store.config.maps.indices.contains(target) else {
            return
        }
        store.moveMaps(from: IndexSet(integer: index), to: target > index ? target + 1 : target)
    }
}
