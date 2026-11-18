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
    @State private var showDuration = false

    private var palette: Palette { .forScheme(colorScheme) }
    private var durationSeconds: Int { max(300, hours * 3600 + minutes * 60) }

    var body: some View {
        NavigationView {
            List {
                mapSection
                durationSection
                orderSection
                dataSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("校准")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .onAppear { loadCurrentState() }
            .onChange(of: hours) { _ in commitDuration() }
            .onChange(of: minutes) { _ in commitDuration() }
            .sheet(isPresented: $showDuration) {
                DurationPickerSheet(hours: $hours, minutes: $minutes)
                    .compactSheet()
            }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - 当前状态

    private var mapSection: some View {
        Section {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 92), spacing: 8)],
                spacing: 8
            ) {
                ForEach(Array(store.config.maps.enumerated()), id: \.element.id) { index, map in
                    mapCell(map, index: index)
                }
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))

            HStack {
                Text("这张图结束于")
                Spacer(minLength: 8)
                DatePicker("", selection: $switchTime, displayedComponents: .hourAndMinute)
                    .labelsHidden()
            }

            Text(previewText)
                .font(.system(size: 12))
                .foregroundStyle(palette.ink3)

            Button {
                apply()
            } label: {
                Text("应用校准")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(palette.onAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        palette.accent,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!isPlausible)
            .opacity(isPlausible ? 1 : 0.45)
        } header: {
            Text("现在游戏里是哪张图")
        }
    }

    private func mapCell(_ map: MapEntry, index: Int) -> some View {
        Button {
            selectedIndex = index
            switchTime = suggestedSwitchTime()
        } label: {
            ZStack(alignment: .bottomLeading) {
                Color.clear
                    .frame(height: 58)
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
            .frame(height: 58)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(selectedIndex == index ? palette.accent : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 时长（点开再弹滚轮）

    private var durationSection: some View {
        Section {
            Button {
                showDuration = true
            } label: {
                HStack {
                    Text("每张图时长")
                        .foregroundStyle(palette.ink1)
                    Spacer(minLength: 8)
                    Text(TimeFormat.duration(seconds: durationSeconds))
                        .foregroundStyle(palette.ink2)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.ink4)
                }
            }
            .buttonStyle(.plain)
        } header: {
            Text("轮换")
        } footer: {
            Text("修改时长会平移之后所有时间点，改完建议重新校准一次。")
        }
    }

    // MARK: - 顺序

    private var orderSection: some View {
        Section {
            ForEach(Array(store.config.maps.enumerated()), id: \.element.id) { index, map in
                HStack(spacing: 10) {
                    thumbnail(map.thumb, size: 26, radius: 6)

                    Text(map.name)
                        .foregroundStyle(palette.ink1)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Button {
                        move(index, by: -1)
                    } label: {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(index == 0 ? palette.ink4 : palette.ink2)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .disabled(index == 0)

                    Button {
                        move(index, by: 1)
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(index == store.config.maps.count - 1 ? palette.ink4 : palette.ink2)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .disabled(index == store.config.maps.count - 1)
                }
            }
        } header: {
            Text("轮换顺序")
        } footer: {
            Text("顺序决定当前地图之后依次出现哪些图。")
        }
    }

    // MARK: - 数据

    private var dataSection: some View {
        Section {
            Button {
                UIPasteboard.general.string = store.exportText()
                notice = "配置 JSON 已复制"
            } label: {
                Text("复制配置 JSON")
            }
            .buttonStyle(.plain)

            Button {
                importFromPasteboard()
            } label: {
                Text("从剪贴板导入")
            }
            .buttonStyle(.plain)

            Button {
                store.reset()
                loadCurrentState()
                notice = "已重置"
            } label: {
                Text("重置为默认配置")
                    .foregroundStyle(palette.accent)
            }
            .buttonStyle(.plain)
        } header: {
            Text("数据")
        } footer: {
            if !notice.isEmpty {
                Text(notice)
            }
        }
    }

    // MARK: - 零件

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
        if hours == 0 && minutes == 0 {
            minutes = 5
            return
        }
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

// MARK: - 时长滚轮

private struct DurationPickerSheet: View {
    @Binding var hours: Int
    @Binding var minutes: Int

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private var total: Int { max(300, hours * 3600 + minutes * 60) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("每张图时长")
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
                Button("完成") { dismiss() }
                    .font(.system(size: 17, weight: .semibold))
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 2)

            Text(TimeFormat.duration(seconds: total))
                .font(.system(size: 30, weight: .bold, design: .monospaced))
                .foregroundStyle(colorScheme == .dark ? .white : .black)
                .padding(.vertical, 4)

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
                    ForEach(Array(stride(from: 0, to: 60, by: 5)), id: \.self) { value in
                        Text("\(value) 分").tag(value)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)
                .clipped()
            }
            .frame(height: 150)
            .padding(.horizontal, 10)

            Spacer(minLength: 0)
        }
        .background(Color(uiColor: .systemBackground))
    }
}

// MARK: - iOS 16+ 的半高 sheet

extension View {
    @ViewBuilder
    func compactSheet() -> some View {
        if #available(iOS 16.0, *) {
            self.presentationDetents([.height(360)])
        } else {
            self
        }
    }
}
