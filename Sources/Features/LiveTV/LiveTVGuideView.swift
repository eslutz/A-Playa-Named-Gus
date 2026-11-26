import SwiftUI

struct LiveTVGuideView: View {
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.scenePhase) private var scenePhase
    @StoredContentPolicy private var policy
    let store: LiveTVStore
    @Binding var day: Date?
    @Binding var reset: Int
    let play: (ItemRef) -> Void

    @State private var now = Date.now
    @State private var selection: LiveTVGuideProgram?
    @State private var playbackAfterDismissal: ItemRef?

    private var calendar: Calendar {
        .autoupdatingCurrent
    }

    private var days: [Date] {
        LiveTVGuideWindow.days(from: now, calendar: calendar)
    }

    private var selectedDay: Date {
        if let day, days.contains(day) {
            return day
        }
        return calendar.startOfDay(for: now)
    }

    private var rows: [LiveTVGuideRow] {
        let programs = store.guide.programs.filter {
            policy.admits(MediaItem(officialRating: $0.rating, type: .liveProgram))
        }
        let groups = Dictionary(grouping: programs, by: \.channelID)
        return store.channels.compactMap { channel in
            guard let id = channel.id, policy.admits(channel), let airings = groups[id] else { return nil }
            return LiveTVGuideRow(id: id, channel: channel, programs: airings.sorted {
                ($0.start, $0.end, $0.id) < ($1.start, $1.end, $1.id)
            })
        }
    }

    private var guideState: LoadState {
        let state = store.guide.state
        guard state == .loaded, !store.guide.programs.isEmpty, store.channels.isEmpty else { return state }
        return store.sectionState(.channels)
    }

    var body: some View {
        VStack(spacing: ContentSpacing.group) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    dayPicker
                    nowButton
                    #if !os(tvOS)
                        Spacer(minLength: 0)
                    #endif
                    refreshButton
                    #if os(tvOS)
                        Spacer(minLength: 0)
                    #endif
                }
                VStack { dayPicker; HStack { nowButton; refreshButton } }
            }
            .padding(.horizontal)

            let rows = rows
            LoadingStateView(
                state: guideState, isEmpty: rows.isEmpty, emptyTitle: LiveTVSection.guide.emptyTitle,
                emptySymbol: "calendar", retryAction: { Task { await refresh() } }, preservesContent: true
            ) {
                if let window = store.guide.window, window.day == selectedDay {
                    GeometryReader { geometry in
                        if geometry.size.width >= 700, !textSize.isAccessibilitySize {
                            LiveTVGuideGrid(rows: rows, window: window, now: now, rowButton: airingButton)
                        } else {
                            scheduleList(rows)
                        }
                    }
                    .id(LoadID(day: selectedDay, reset: reset))
                }
            }
        }
        .task(id: LoadID(day: selectedDay, reset: reset)) {
            let date = selectedDay
            if store.guide.window?.day != date || store.guide.state == .idle || reset != 0 {
                await load(day: date)
            }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            now = .now
            await store.guide.loadRecordingPermission(session: store.session)
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
                now = .now
            }
        }
        .gusTVTask(item: $selection, onDismiss: {
            if let reference = playbackAfterDismissal {
                playbackAfterDismissal = nil
                play(reference)
            }
        }) { program in
            if let channel = store.channels.first(where: { $0.id == program.channelID }) {
                LiveTVAiringView(program: program, channel: channel, store: store) { reference in
                    playbackAfterDismissal = reference
                    selection = nil
                }
            }
        }
    }

    private struct LoadID: Equatable, Hashable {
        let day: Date
        let reset: Int
    }

    private var dayPicker: some View {
        Menu {
            ForEach(days, id: \.self) { date in
                Button {
                    day = date
                } label: {
                    if date == selectedDay {
                        Label(date.formatted(.dateTime.weekday(.wide).month().day()), systemImage: "checkmark")
                    } else {
                        Text(date, format: .dateTime.weekday(.wide).month().day())
                    }
                }
            }
        } label: {
            Label(selectedDay.formatted(.dateTime.weekday(.abbreviated).month().day()), systemImage: "calendar")
        }
        .accessibilityLabel("Guide Date")
        .accessibilityValue(selectedDay.formatted(date: .complete, time: .omitted))
        .accessibilityIdentifier("LiveTV.guide.date")
    }

    private var nowButton: some View {
        Button("Now") {
            now = .now
            day = nil
            reset += 1
        }
        .accessibilityIdentifier("LiveTV.guide.now")
    }

    private var refreshButton: some View {
        Button("Refresh", systemImage: "arrow.clockwise") { Task { await refresh() } }
            .labelStyle(.iconOnly)
            .accessibilityIdentifier("LiveTV.guide.refresh")
    }

    private func load(day: Date) async {
        let window = LiveTVGuideWindow(day: day, now: now, calendar: calendar)
        await store.guide.load(window, session: store.session)
    }

    private func refresh() async {
        // Keep the current viewport and its time origin on a refresh.
        let date = selectedDay
        let window = store.guide.window.flatMap { $0.day == date ? $0 : nil }
            ?? LiveTVGuideWindow(day: date, now: now, calendar: calendar)
        async let guide: Void = store.guide.load(window, session: store.session)
        async let channels: Void = store.reload(.channels)
        async let timers: Void = store.reload(.scheduled)
        async let permission: Void = store.guide.loadRecordingPermission(session: store.session)
        _ = await(guide, channels, timers, permission)
    }

    private func scheduleList(_ rows: [LiveTVGuideRow]) -> some View {
        List(rows) { row in
            Section {
                ForEach(row.programs) { program in
                    airingButton(program, row.channel.displayTitle, false)
                }
            } header: {
                Text(row.channel.displayTitle)
            }
        }
        .listStyle(.plain)
        .refreshable { await refresh() }
        .accessibilityIdentifier("LiveTV.guide.list")
    }

    private func airingButton(_ program: LiveTVGuideProgram, _ channel: String, _ inGrid: Bool) -> some View {
        let scheduled = store.hasScheduled(program)
        let live = program.start <= now && now < program.end
        return Button {
            selection = program
        } label: {
            VStack(alignment: .leading, spacing: ContentSpacing.caption) {
                Text(program.name)
                    .font(.headline)
                    .lineLimit(inGrid ? 1 : nil)
                HStack(spacing: ContentSpacing.group) {
                    Text(program.timeText)
                    if scheduled {
                        Image(systemName: "record.circle")
                    } else if live, !inGrid {
                        Text("On Now")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(inGrid ? 1 : nil)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(inGrid ? ContentSpacing.group : 0)
            .background {
                if inGrid {
                    RoundedRectangle(cornerRadius: 8).fill(.quaternary)
                }
            }
            .clipped()
            .contentShape(.rect)
        }
        #if !os(tvOS)
        .buttonStyle(.plain)
        #endif
        .accessibilityLabel(Text(program.name))
        .accessibilityValue(accessibilityValue(program, channel: channel, scheduled: scheduled, live: live))
        .accessibilityIdentifier("LiveTV.guide.airing." + program.id)
    }

    private func accessibilityValue(_ program: LiveTVGuideProgram, channel: String, scheduled: Bool, live: Bool) -> Text {
        if scheduled {
            Text("\(channel), \(program.timeText), Scheduled")
        } else if live {
            Text("\(channel), \(program.timeText), On Now")
        } else {
            Text("\(channel), \(program.timeText)")
        }
    }
}

private struct LiveTVGuideRow: Identifiable {
    let id: String
    let channel: MediaItem
    let programs: [LiveTVGuideProgram]

    var lanes: [[LiveTVGuideProgram]] {
        var lanes: [[LiveTVGuideProgram]] = []
        for program in programs {
            if let index = lanes.firstIndex(where: { ($0.last?.end ?? .distantPast) <= program.start }) {
                lanes[index].append(program)
            } else {
                lanes.append([program])
            }
        }
        return lanes
    }
}

private struct LiveTVGuideGrid<AiringButton: View>: View {
    let rows: [LiveTVGuideRow]
    let window: LiveTVGuideWindow
    let now: Date
    @ViewBuilder let rowButton: (LiveTVGuideProgram, String, Bool) -> AiringButton
    @State private var horizontalOffset: CGFloat = 0

    #if os(tvOS)
        private let channelWidth: CGFloat = 260
        private let halfHourWidth: CGFloat = 220
        private let laneHeight: CGFloat = 104
    #else
        private let channelWidth: CGFloat = 160
        private let halfHourWidth: CGFloat = 140
        private let laneHeight: CGFloat = 66
    #endif

    private var timelineWidth: CGFloat {
        distance(to: window.end)
    }

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            LazyVStack(alignment: .leading, spacing: 1, pinnedViews: [.sectionHeaders]) {
                Section {
                    ForEach(rows) { row in
                        let lanes = row.lanes
                        HStack(alignment: .top, spacing: 0) {
                            pinnedChannel(Text(row.channel.displayTitle).font(.headline), height: CGFloat(lanes.count) * laneHeight)
                            VStack(spacing: 0) {
                                ForEach(lanes.indices, id: \.self) { index in
                                    lane(lanes[index], channel: row.channel.displayTitle)
                                }
                            }
                        }
                    }
                } header: {
                    HStack(spacing: 0) {
                        pinnedChannel(Text("Channels").font(.headline), height: laneHeight)
                        timeHeader
                    }
                    .background(.background)
                    .accessibilityHidden(true)
                }
            }
        }
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            max(0, geometry.contentOffset.x + geometry.contentInsets.leading)
        } action: { _, offset in
            horizontalOffset = offset
        }
        #if os(tvOS)
        .focusSection()
        #endif
        .accessibilityIdentifier("LiveTV.guide.grid")
    }

    private var timeHeader: some View {
        let slots = Int((window.end.timeIntervalSince(window.start) / 1800).rounded(.up))
        return HStack(spacing: 0) {
            ForEach(0 ..< slots, id: \.self) { offset in
                let date = window.start.addingTimeInterval(Double(offset) * 1800)
                Text(date, format: .dateTime.hour().minute())
                    .font(.subheadline.monospacedDigit())
                    .padding(.leading, ContentSpacing.group)
                    .frame(width: min(halfHourWidth, timelineWidth - distance(to: date)), alignment: .leading)
            }
        }
        .frame(height: laneHeight)
    }

    private func pinnedChannel(_ label: Text, height: CGFloat) -> some View {
        label
            .lineLimit(2)
            .padding(.horizontal, ContentSpacing.group)
            .frame(width: channelWidth, height: height, alignment: .leading)
            .background(.background)
            .offset(x: horizontalOffset)
            .zIndex(1)
    }

    private func lane(_ programs: [LiveTVGuideProgram], channel: String) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(programs) { program in
                let start = distance(to: max(window.start, program.start))
                let end = distance(to: min(window.end, program.end))
                rowButton(program, channel, true)
                    .frame(width: max(1, end - start - 2), height: laneHeight - 2)
                    .offset(x: start)
            }
            if window.start <= now, now < window.end {
                Rectangle()
                    .fill(.tint)
                    .frame(width: 1, height: laneHeight)
                    .offset(x: distance(to: now))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: timelineWidth, height: laneHeight, alignment: .topLeading)
    }

    private func distance(to date: Date) -> CGFloat {
        CGFloat(date.timeIntervalSince(window.start) / 1800) * halfHourWidth
    }
}

private struct LiveTVAiringView: View {
    @Environment(\.dismiss) private var dismiss
    @StoredContentPolicy private var policy
    let program: LiveTVGuideProgram
    let channel: MediaItem
    let store: LiveTVStore
    let play: (ItemRef) -> Void

    @State private var confirmation: Confirmation?
    @State private var isReviewing = false
    @State private var error: String?
    @State private var now = Date.now

    private struct Confirmation {
        let retry: Bool
    }

    private var isAdmitted: Bool {
        policy.admits(MediaItem(officialRating: program.rating, type: .liveProgram)) && policy.admits(channel)
    }

    private var confirmationTitle: LocalizedStringKey {
        confirmation?.retry == true ? "Retry Recording Request?" : "Record Program?"
    }

    var body: some View {
        NavigationStack {
            List {
                if isAdmitted {
                    Section {
                        Text(channel.displayTitle)
                        Text(program.start, format: .dateTime.weekday(.wide).month().day())
                        Text(program.timeText)
                    }
                    actions
                } else {
                    RestrictedContentView()
                }
            }
            .navigationTitle(isAdmitted ? program.name : String(localized: "Restricted Content"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    GusCloseButton { dismiss() }
                }
            }
            .task {
                while !Task.isCancelled {
                    now = .now
                    do { try await Task.sleep(for: .seconds(15)) } catch { return }
                }
            }
            .onChange(of: isAdmitted) { _, allowed in
                if !allowed {
                    confirmation = nil
                }
            }
            .alert(confirmationTitle, isPresented: Binding(
                get: { confirmation != nil },
                set: {
                    if !$0 {
                        confirmation = nil
                    }
                }
            ), presenting: confirmation) { confirmation in
                Button(confirmation.retry ? "Send Again" : "Record") {
                    Task { await record(retry: confirmation.retry) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { confirmation in
                if confirmation.retry {
                    Text("The DVR currently lists no timer for \(program.name) on \(channel.displayTitle) at \(startText). The previous request is still unconfirmed.")
                } else {
                    Text("Record \(program.name) on \(channel.displayTitle) at \(startText)?")
                }
            }
        }
    }

    private var actions: some View {
        Section {
            if program.start <= now, now < program.end {
                Button("Watch Live", systemImage: "play.fill") {
                    tune()
                }
                .accessibilityIdentifier("LiveTV.guide.watch")
                #if os(iOS)
                    VideoPlaybackSetupButton(item: channel) { selection in
                        tune(selection.applying(to: PlaybackRequest(item: channel)))
                    }
                #endif
            }
            if store.hasScheduled(program) {
                Label("Scheduled", systemImage: "checkmark.circle")
            } else if program.end > now, store.guide.canRecord {
                recordingControls
            }
            if let error {
                Text(error).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var recordingControls: some View {
        let outcome = store.guide.recordingOutcomes[program.id]
        if outcome == .accepted || outcome == .uncertain {
            Text(outcome == .accepted
                ? "Recording request accepted. Check the schedule to confirm."
                : "Recording request unconfirmed. Check the schedule before trying again.")
                .foregroundStyle(.secondary)
        }
        if isReviewing || outcome == .pending {
            ProgressView()
        } else {
            Button(outcome == .accepted || outcome == .uncertain ? "Check Recording" : "Record", systemImage: "record.circle") {
                Task { await review() }
            }
            .accessibilityIdentifier("LiveTV.guide.record")
        }
    }

    private var startText: String {
        program.start.formatted(date: .abbreviated, time: .shortened)
    }

    private func tune(_ request: PlaybackRequest? = nil) {
        guard store.session.isActive, program.admitted, ContentRatingGate.admitsStored(channel),
              program.start <= .now, program.end > .now else { return }
        play(ItemRef(item: channel, serverID: store.session.server.id, userID: store.session.user.id, playbackRequest: request))
    }

    private func review() async {
        guard !isReviewing else { return }
        isReviewing = true
        error = nil
        defer { isReviewing = false }
        do {
            let result = try await store.guide.review(program, session: store.session)
            guard isAdmitted else { return }
            switch result {
            case .ready: confirmation = Confirmation(retry: false)
            case .unconfirmed: confirmation = Confirmation(retry: true)
            case .scheduled: await store.reload(.scheduled, superseding: true)
            }
        } catch {
            show(error)
        }
    }

    private func record(retry: Bool) async {
        error = nil
        do {
            try await store.guide.record(program, retry: retry, session: store.session)
            await store.reload(.scheduled, superseding: true)
        } catch {
            show(error)
        }
    }

    private func show(_ thrown: Error) {
        let failure = GusError(from: thrown)
        guard store.session.isActive, !failure.isCancellation else { return }
        failure.handleIfUnauthorized(session: store.session)
        error = failure.localizedDescription
    }
}

private extension LiveTVGuideProgram {
    var timeText: String {
        (start ..< end).formatted(.interval.hour().minute())
    }
}
