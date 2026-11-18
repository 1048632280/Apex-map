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
    @State private var showDuration = false
    @State private var notice = ""
    @State private var dragStartIndex: Int?

    private var palette: Palette { .forScheme(colorScheme) }
    private var durationSeconds: Int { max(300, hours * 3600 + minutes * 60) }
    private let rowHeight: CGFloat = 44

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    seasonSection
                    orderSection
                    calibrationSection
                    durationSection
                    dataSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 2)
                .padding(.bottom, 36)
            }
        }
        .background(palette.page.ignoresSafeArea())
        .sheet(isPresented: $showDuration) {
            durationSheet
        }
        .onChange(of: showDuration) { presented in
            if !presented { commitDuration() }
        }
        .onAppear { loadCurrentState() }
    }

    // MARK: - 顶栏

    private var header: some View {
        ZStack {
            Text("校准")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(palette.ink1)

            HStack {
                Button("关闭") { dismiss() }
                    .font(.system(size: 16))
                    .foregroundStyle(palette.ink2)
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
    }

    // MARK: - 本赛季地图

    private var seasonSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("本赛季地图")

            card {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 92), spacing: 8)],
                    spacing: 8
                ) {
                    ForEach(SeedMaps.entries) { map in
                        seasonCell(map)
                    }
                }
                .padding(12)
            }
        }
    }

    private func seasonCell(_ map: MapEntry) -> some View {
        let selected = store.config.maps.contains { $0.slug == map.slug }

        return Button {
            store.toggleMap(map)
            loadCurrentState()
        } label: {
            ZStack(alignment: .topTrailing) {
                mapTile(map)
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(selected ? palette.accent : Color.clear, lineWidth: 2)
                    )
                    .opacity(selected ? 1 : 0.4)

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
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("轮换顺序")

            card {
                VStack(spacing: 0) {
                    ForEach(Array(store.config.maps.enumerated()), id: \.element.id) { index, map in
                        orderRow(map, index: index)

                        if index < store.config.maps.count - 1 {
                            divider.padding(.leading, 50)
                        }
                    }
                }
            }
        }
    }

    private func orderRow(_ map: MapEntry, index: Int) -> some View {
        HStack(spacing: 10) {
            thumbnail(map.thumb, size: 26, radius: 6)

            Text(map.name)
                .font(.system(size: 15))
                .foregroundStyle(palette.ink1)
                .lineLimit(1)

            Spacer(minLength: 8)

            Image(systemName: "line.3.horizontal")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.ink4)
                .frame(width: 44, height: rowHeight)
                .contentShape(Rectangle())
                .highPriorityGesture(dragGesture(for: map))
        }
        .padding(.leading, 14)
        .frame(height: rowHeight)
    }

    private func dragGesture(for map: MapEntry) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                if dragStartIndex == nil {
                    dragStartIndex = store.config.maps.firstIndex(where: { $0.slug == map.slug })
                }
                guard let start = dragStartIndex else { return }

                let steps = Int((value.translation.height / rowHeight).rounded())
                let target = max(0, min(store.config.maps.count - 1, start + steps))
                guard let current = store.config.maps.firstIndex(where: { $0.slug == map.slug }),
                      current != target else { return }

                withAnimation(.easeInOut(duration: 0.15)) {
                    store.moveMap(from: current, to: target)
                }
            }
            .onEnded { _ in
                dragStartIndex = nil
                loadCurrentState()
            }
    }

    // MARK: - 当前地图

    private var calibrationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("当前地图")

            card {
                VStack(spacing: 0) {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 92), spacing: 8)],
                        spacing: 8
                    ) {
                        ForEach(Array(store.config.maps.enumerated()), id: \.element.id) { index, map in
                            currentCell(map, index: index)
                        }
                    }
                    .padding(12)

                    divider

                    HStack {
                        Text("这张图结束于")
                            .font(.system(size: 15))
                            .foregroundStyle(palette.ink1)
                        Spacer(minLength: 8)
                        DatePicker("", selection: $switchTime, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)

                    Button {
                        commitDuration()
                        store.calibrate(currentMapIndex: selectedIndex, nextSwitchAt: resolvedSwitchTime)
                        dismiss()
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
                    .padding(12)
                }
            }
        }
    }

    private func currentCell(_ map: MapEntry, index: Int) -> some View {
        Button {
            selectedIndex = index
            switchTime = suggestedSwitchTime()
        } label: {
            mapTile(map)
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(selectedIndex == index ? palette.accent : Color.clear, lineWidth: 2)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 时长

    private var durationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("轮换时长")

            card {
                Button {
                    showDuration = true
                } label: {
                    HStack {
                        Text("每张图时长")
                            .font(.system(size: 15))
                            .foregroundStyle(palette.ink1)
                        Spacer(minLength: 8)
                        Text(TimeFormat.duration(seconds: durationSeconds))
                            .font(.system(size: 15, weight: .semibold, design: .monospaced))
                            .foregroundStyle(palette.ink2)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(palette.ink4)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 46)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var durationSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Text("每张图时长")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(palette.ink1)
                Spacer()
                Button("完成") { showDuration = false }
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(palette.ink1)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)

            Text(TimeFormat.duration(seconds: durationSeconds))
                .font(.system(size: 30, weight: .bold, design: .monospaced))
                .foregroundStyle(palette.ink1)
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
        .background(palette.page.ignoresSafeArea())
        .compactSheet()
    }

    // MARK: - 数据

    private var dataSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("数据")

            card {
                VStack(spacing: 0) {
                    dataRow("复制配置 JSON") {
                        UIPasteboard.general.string = store.exportText()
                        notice = "已复制"
                    }

                    divider

                    dataRow("从剪贴板导入") {
                        importFromPasteboard()
                    }

                    divider

                    dataRow("重置为默认配置", destructive: true) {
                        store.reset()
                        loadCurrentState()
                        notice = "已重置"
                    }

                    if !notice.isEmpty {
                        divider

                        HStack {
                            Text(notice)
                                .font(.system(size: 12))
                                .foregroundStyle(palette.ink4)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 14)
                        .frame(height: 36)
                    }
                }
            }
        }
    }

    private func dataRow(_ title: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 15))
                    .foregroundStyle(destructive ? palette.accent : palette.ink1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(height: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 零件

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(palette.ink3)
            .padding(.leading, 4)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .background(palette.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(palette.hairline, lineWidth: 1)
            )
    }

    private var divider: some View {
        Rectangle()
            .fill(palette.hairline)
            .frame(height: 1)
    }

    private func mapTile(_ map: MapEntry) -> some View {
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
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
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

    private func commitDuration() {
        if hours == 0 && minutes == 0 {
            minutes = 5
        }
        store.setSecondsPerMap(max(300, hours * 3600 + minutes * 60))
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
