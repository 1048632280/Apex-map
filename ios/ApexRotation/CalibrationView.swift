import SwiftUI
import UIKit

private struct ListOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct CalibrationView: View {
    @ObservedObject var store: ConfigStore

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var selectedIndex = 0
    @State private var switchTime = Date()
    @State private var hours = 4
    @State private var minutes = 30
    @State private var durationExpanded = false
    @State private var listOffset: CGFloat = 0
    @State private var suppressCollapse = false
    @State private var notice = ""

    private var palette: Palette { .forScheme(colorScheme) }
    private var durationSeconds: Int { max(300, hours * 3600 + minutes * 60) }
    private var catalog: [MapEntry] { SeedMaps.entries }

    var body: some View {
        NavigationView {
            List {
                seasonSection
                orderSection
                calibrationSection
                durationSection
                dataSection
            }
            .listStyle(.insetGrouped)
            .coordinateSpace(name: "calibration")
            .onPreferenceChange(ListOffsetKey.self) { value in
                let delta = abs(value - listOffset)
                listOffset = value
                guard durationExpanded, !suppressCollapse else { return }
                if delta > 8 {
                    durationExpanded = false
                    commitDuration()
                }
            }
            .navigationTitle("校准")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        collapseDuration()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    EditButton()
                }
            }
            .onAppear { loadCurrentState() }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - 本赛季地图

    private var seasonSection: some View {
        Section {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 92), spacing: 8)],
                spacing: 8
            ) {
                ForEach(catalog) { map in
                    seasonCell(map)
                }
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
        } header: {
            Text("本赛季地图")
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: ListOffsetKey.self,
                            value: geo.frame(in: .named("calibration")).minY
                        )
                    }
                )
        }
    }

    private func seasonCell(_ map: MapEntry) -> some View {
        let selected = store.config.maps.contains { $0.slug == map.slug }

        return Button {
            collapseDuration()
            store.toggleMap(map)
            loadCurrentState()
        } label: {
            ZStack(alignment: .topTrailing) {
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
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(selected ? palette.accent : Color.clear, lineWidth: 2)
                )
                .opacity(selected ? 1 : 0.42)

                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(palette.accent)
                        .padding(5)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - 轮换顺序

    private var orderSection: some View {
        Section {
            ForEach(store.config.maps) { map in
                HStack(spacing: 10) {
                    thumbnail(map.thumb, size: 26, radius: 6)
                    Text(map.name)
                        .foregroundStyle(palette.ink1)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
            .onMove { source, destination in
                store.moveMaps(from: source, to: destination)
                loadCurrentState()
            }
        } header: {
            Text("轮换顺序")
        }
    }

    // MARK: - 当前地图

    private var calibrationSection: some View {
        Section {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 92), spacing: 8)],
                spacing: 8
            ) {
                ForEach(Array(store.config.maps.enumerated()), id: \.element.id) { index, map in
                    currentCell(map, index: index)
                }
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))

            HStack {
                Text("这张图结束于")
                Spacer(minLength: 8)
                DatePicker("", selection: $switchTime, displayedComponents: .hourAndMinute)
                    .labelsHidden()
            }
            .simultaneousGesture(TapGesture().onEnded { collapseDuration() })

            Button {
                collapseDuration()
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
            Text("当前地图")
        }
    }

    private func currentCell(_ map: MapEntry, index: Int) -> some View {
        Button {
            collapseDuration()
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

    // MARK: - 时长

    private var durationSection: some View {
        Section {
            Button {
                toggleDuration()
            } label: {
                HStack {
                    Text("每张图时长")
                        .foregroundStyle(palette.ink1)
                    Spacer(minLength: 8)
                    Text(TimeFormat.duration(seconds: durationSeconds))
                        .foregroundStyle(palette.ink2)
                    Image(systemName: durationExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.ink4)
                }
            }
            .buttonStyle(.plain)

            if durationExpanded {
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
            }
        } header: {
            Text("轮换时长")
        }
    }

    // MARK: - 数据

    private var dataSection: some View {
        Section {
            Button {
                collapseDuration()
                UIPasteboard.general.string = store.exportText()
                notice = "已复制"
            } label: {
                Text("复制配置 JSON")
            }
            .buttonStyle(.plain)

            Button {
                collapseDuration()
                importFromPasteboard()
            } label: {
                Text("从剪贴板导入")
            }
            .buttonStyle(.plain)

            Button {
                collapseDuration()
                store.reset()
                loadCurrentState()
                notice = "已重置"
            } label: {
                Text("重置为默认配置")
                    .foregroundStyle(palette.accent)
            }
            .buttonStyle(.plain)

            if !notice.isEmpty {
                Text(notice)
                    .font(.system(size: 12))
                    .foregroundStyle(palette.ink4)
            }
        } header: {
            Text("数据")
        }
    }

    // MARK: - 行为

    private func toggleDuration() {
        if durationExpanded {
            collapseDuration()
        } else {
            suppressCollapse = true
            withAnimation(.easeInOut(duration: 0.2)) {
                durationExpanded = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                suppressCollapse = false
            }
        }
    }

    private func collapseDuration() {
        guard durationExpanded else { return }
        durationExpanded = false
        commitDuration()
    }

    private func commitDuration() {
        if hours == 0 && minutes == 0 {
            minutes = 5
        }
        let seconds = max(300, hours * 3600 + minutes * 60)
        store.setSecondsPerMap(seconds)
    }

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

        guard !store.config.maps.isEmpty else {
            selectedIndex = 0
            return
        }
        selectedIndex = min(selectedIndex, store.config.maps.count - 1)

        if store.isCalibrated, let slot = store.currentSlot(at: .now),
           let index = store.config.maps.firstIndex(where: { $0.slug == slot.map.slug }) {
            selectedIndex = index
            switchTime = slot.end
        } else {
            switchTime = suggestedSwitchTime()
        }
    }

    private func apply() {
        commitDuration()
        store.calibrate(currentMapIndex: selectedIndex, nextSwitchAt: resolvedSwitchTime)
        dismiss()
    }

    private func importFromPasteboard() {
        guard let text = UIPasteboard.general.string else {
            notice = "剪贴板为空"
            return
        }
        if store.importText(text) {
            loadCurrentState()
            notice = "已导入"
        } else {
            notice = "无效配置"
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
}
