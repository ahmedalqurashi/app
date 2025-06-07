import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 1 // 0 = profile, 1 = home, 2 = settings
    @State private var showSheet = false
    @State private var scheduledTasks: [ScheduleTask] = []
    @State private var now: Date = Date()
    @State private var timer: Timer? = nil
    @State private var sessionState: SessionState = .none
    @State private var timelineShouldResetScroll = false
    @State private var sessionResetSignal: Int = 0
    @State private var dragOffset: CGFloat = 0
    @State private var previousSessionState: SessionState? = nil
    @State private var taskTrails: [UUID: [(start: Date, end: Date, isFocus: Bool)]] = [:]

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                ZStack {
                    // Timeline background pulse
                    Color.black.ignoresSafeArea()
                    if isCurrentTaskActive {
                        Color.purple.opacity(isGlowing ? 0.10 : 0.04)
                            .ignoresSafeArea()
                            .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: isGlowing)
                    }
                    Group {
                        switch selectedTab {
                        case 0: Text("Profile").foregroundColor(.white)
                        case 1: ContentView(scheduledTasks: $scheduledTasks, sessionState: $sessionState, taskTrails: taskTrails, resetScroll: $timelineShouldResetScroll)
                        case 2: Text("Settings").foregroundColor(.white)
                        default: ContentView(scheduledTasks: $scheduledTasks, sessionState: $sessionState, taskTrails: taskTrails, resetScroll: $timelineShouldResetScroll)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Custom Tab Bar
            HStack {
                Spacer()
                TabBarButton(icon: "person.crop.circle", isSelected: selectedTab == 0) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        selectedTab = 0
                    }
                }
                Spacer()
                // Center arrow button
                Spacer()
                TabBarButton(icon: "gearshape.fill", isSelected: selectedTab == 2) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        selectedTab = 2
                    }
                }
                Spacer()
            }
            .frame(height: 60)
            .background(
                Color(.systemGray6)
                    .opacity(0.15)
                    .blur(radius: 10)
                    .ignoresSafeArea(edges: .bottom)
            )
            .overlay(
                ZStack {
                    if sessionState == .paused {
                        PauseLottieView()
                            .frame(width: 60, height: 60)
                            .offset(y: -40)
                            .transition(.opacity)
                    }
                    Image(systemName: "arrowtriangle.up.fill")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(buttonColor)
                        .frame(width: 64, height: 64)
                        .background(
                            Circle()
                                .fill(buttonColor)
                                .shadow(color: isGlowing ? buttonColor.opacity(0.7) : .clear, radius: isGlowing ? 24 : 10)
                        )
                        .scaleEffect(isGlowing ? 1.12 : 1.0)
                        .offset(y: buttonYOffset)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    dragOffset = max(0, value.translation.height)
                                }
                                .onEnded { value in
                                    if dragOffset > 60 && (sessionState == .work || sessionState == .breakSession) {
                                        previousSessionState = sessionState
                                        sessionState = .paused
                                    } else if dragOffset < -40 && sessionState == .paused {
                                        sessionState = previousSessionState ?? .work
                                    }
                                    dragOffset = 0
                                }
                        )
                        .onTapGesture {
                            switch sessionState {
                            case .none:
                                showSheet = true
                            case .work:
                                sessionState = .breakSession
                            case .breakSession, .paused:
                                sessionState = .work
                            }
                        }
                }
            )
        }
        .sheet(isPresented: $showSheet) {
            MinimalDarkSheet { hours, start, end in
                guard let start = start, let hours = Double(hours) else { return }
                let totalWorkSeconds = hours * 3600
                let workBlock: TimeInterval = 25 * 60
                let breakBlock: TimeInterval = 5 * 60
                var blockSpecs: [(name: String, duration: TimeInterval, category: TaskCategory)] = []
                var remainingWork = totalWorkSeconds
                while remainingWork > 0 {
                    let thisWorkDuration = min(workBlock, remainingWork)
                    blockSpecs.append(("Work", thisWorkDuration, .focus))
                    remainingWork -= thisWorkDuration
                    if remainingWork > 0 {
                        blockSpecs.append(("Break", breakBlock, .freeTime))
                    }
                }
                var blocks: [ScheduleTask] = []
                var accumulated: TimeInterval = 0
                let calendar = Calendar.current
                for (i, spec) in blockSpecs.enumerated() {
                    let blockStartRaw = start.addingTimeInterval(accumulated)
                    // Snap start to the exact minute (zero seconds)
                    let snappedStart = calendar.date(bySettingHour: calendar.component(.hour, from: blockStartRaw),
                                                     minute: calendar.component(.minute, from: blockStartRaw),
                                                     second: 0,
                                                     of: blockStartRaw) ?? blockStartRaw
                    let rawEnd = snappedStart.addingTimeInterval(spec.duration)
                    // Snap end to the exact minute (zero seconds)
                    let snappedEnd = calendar.date(bySettingHour: calendar.component(.hour, from: rawEnd),
                                                   minute: calendar.component(.minute, from: rawEnd),
                                                   second: 0,
                                                   of: rawEnd) ?? rawEnd
                    let duration = snappedEnd.timeIntervalSince(snappedStart)
                    blocks.append(ScheduleTask(name: spec.name, startTime: snappedStart, duration: duration, category: spec.category))
                    // Debug print
                    let hourHeight: CGFloat = 120 // Keep in sync with TimelineView
                    let offset = (CGFloat(calendar.component(.hour, from: snappedStart)) + CGFloat(calendar.component(.minute, from: snappedStart)) / 60.0) * hourHeight
                    print("Block #\(i): \(spec.name) | Start: \(snappedStart) | End: \(snappedEnd) | Duration: \(duration) | Offset: \(offset)")
                    accumulated += duration
                }
                // Remove any tasks that overlap with the new blocks
                let newStart = start
                let newEnd = start.addingTimeInterval(accumulated)
                let filtered = scheduledTasks.filter { task in
                    let taskEnd = task.startTime.addingTimeInterval(task.duration)
                    return taskEnd <= newStart || task.startTime >= newEnd
                }
                scheduledTasks = filtered + blocks
                showSheet = false
            }
        }
        .onAppear {
            startTimer()
            if isCurrentTaskActive && !sessionState.paused && isCurrentTaskWorkSession {
                isGlowing = true
            } else {
                isGlowing = false
            }
        }
        .onDisappear {
            stopTimer()
        }
        .onChange(of: isCurrentTaskActive) { active in
            if active && !sessionState.paused && isCurrentTaskWorkSession {
                isGlowing = true
            } else {
                isGlowing = false
            }
        }
        .onChange(of: sessionState.paused) { paused in
            if paused {
                isGlowing = false
            } else if isCurrentTaskActive && isCurrentTaskWorkSession {
                isGlowing = true
            }
        }
        .onChange(of: isCurrentTaskWorkSession) { isWork in
            if isWork && isCurrentTaskActive && !sessionState.paused {
                isGlowing = true
            }
        }
        .onChange(of: selectedTab) { newTab in
            if newTab == 1 {
                timelineShouldResetScroll = true
            }
        }
        .onChange(of: currentTimerMode) { _ in
            sessionResetSignal += 1
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            timelineShouldResetScroll = true
        }
        // Attach the glow overlay to the very outer container
        .overlay(
            GlowingEdgeView(isActive: isGlowing && isCurrentTaskWorkSession)
                .ignoresSafeArea()
        )
        .overlay(
            sessionState == .paused ?
                Color.black.opacity(0.4).ignoresSafeArea().transition(.opacity)
                : nil
        )
    }

    private var isCurrentTaskActive: Bool {
        let calendar = Calendar.current
        return scheduledTasks.contains { task in
            calendar.compare(now, to: task.startTime, toGranularity: .minute) != .orderedAscending &&
            calendar.compare(now, to: task.endTime, toGranularity: .minute) == .orderedAscending
        }
    }

    private var isCurrentTaskWorkSession: Bool {
        let calendar = Calendar.current
        return scheduledTasks.contains { task in
            calendar.compare(now, to: task.startTime, toGranularity: .minute) != .orderedAscending &&
            calendar.compare(now, to: task.endTime, toGranularity: .minute) == .orderedAscending &&
            task.category == .focus
        }
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            let previousNow = now
            now = Date()
            updateTrail(previousNow: previousNow, currentNow: now)
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func updateTrail(previousNow: Date, currentNow: Date) {
        // Find the current task
        let calendar = Calendar.current
        guard let currentTask = scheduledTasks.first(where: { task in
            calendar.compare(currentNow, to: task.startTime, toGranularity: .minute) != .orderedAscending &&
            calendar.compare(currentNow, to: task.endTime, toGranularity: .minute) == .orderedAscending
        }) else { return }
        let isFocus = isGlowing && !sessionState.paused && currentTask.category == .focus
        let taskId = currentTask.id
        let minuteStart = calendar.date(bySetting: .second, value: 0, of: previousNow) ?? previousNow
        let minuteEnd = calendar.date(bySetting: .second, value: 0, of: currentNow) ?? currentNow
        var intervals = taskTrails[taskId] ?? []
        if let last = intervals.last, last.isFocus == isFocus, calendar.isDate(last.end, equalTo: minuteStart, toGranularity: .minute) {
            // Extend the last interval
            intervals[intervals.count - 1].end = minuteEnd
        } else {
            // Start a new interval
            intervals.append((start: minuteStart, end: minuteEnd, isFocus: isFocus))
        }
        taskTrails[taskId] = intervals
    }

    private var currentTimerMode: TimerView.Mode? {
        if isCurrentTaskWorkSession && !sessionState.paused {
            return .work
        } else if isCurrentTaskBreakSession {
            return .breakTime
        } else {
            return nil
        }
    }

    private var timerBlockStartTime: Date? {
        let now = Date()
        let calendar = Calendar.current
        if let currentBlock = scheduledTasks.first(where: { t in
            calendar.compare(now, to: t.startTime, toGranularity: .minute) != .orderedAscending &&
            calendar.compare(now, to: t.endTime, toGranularity: .minute) == .orderedAscending
        }) {
            return currentBlock.startTime
        }
        return nil
    }

    private func timerString(from start: Date) -> String {
        let now = Date()
        let elapsed = Int(now.timeIntervalSince(start))
        let minutes = (elapsed % 3600) / 60
        let seconds = elapsed % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private var isCurrentTaskBreakSession: Bool {
        let calendar = Calendar.current
        return scheduledTasks.contains { task in
            calendar.compare(now, to: task.startTime, toGranularity: .minute) != .orderedAscending &&
            calendar.compare(now, to: task.endTime, toGranularity: .minute) == .orderedAscending &&
            (task.category == .freeTime || (task.category == .focus && sessionState.paused))
        }
    }

    private let darkPurple = Color(red: 0.4, green: 0.0, blue: 0.7)

    private var buttonColor: Color {
        switch sessionState {
        case .none, .paused: return Color(.systemGray4)
        case .work: return Color.purple
        case .breakSession: return Color.blue
        }
    }

    private var isGlowing: Bool {
        sessionState == .work
    }

    private var buttonYOffset: CGFloat {
        switch sessionState {
        case .none, .paused: return 0
        case .work, .breakSession: return -32
        }
    }
}

struct TabBarButton: View {
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(isSelected ? .blue : .gray)
                .frame(width: 44, height: 44)
        }
    }
}

struct TimerView: View {
    enum Mode {
        case work, breakTime
    }
    let mode: Mode
    let isActive: Bool
    let resetSignal: Int
    var bodyColor: Color {
        mode == .work ? Color(red: 0.6, green: 0.1, blue: 1.0) : Color(red: 0.1, green: 0.4, blue: 1.0)
    }
    var shadowColor: Color {
        bodyColor.opacity(0.7)
    }
    @State private var sessionTimer: Int = 0
    @State private var lastResetSignal: Int = 0
    var body: some View {
        Text(String(format: "%02d:%02d", sessionTimer / 60, sessionTimer % 60))
            .font(.system(size: 22, weight: .bold, design: .monospaced))
            .foregroundColor(isActive ? bodyColor : Color.gray)
            .shadow(color: isActive ? shadowColor : .clear, radius: 8, x: 0, y: 0)
            .padding(.horizontal, 9)
            .padding(.vertical, 10)
            //.background(
             //   Capsule()
              //      .fill(bodyColor.opacity(0.18))
           // )
            .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
                if isActive {
                    sessionTimer += 1
                }
            }
            .onChange(of: resetSignal) { newValue in
                if newValue != lastResetSignal {
                    sessionTimer = 0
                    lastResetSignal = newValue
                }
            }
    }
}

// struct GlowingEdgeView: View {
//     let isActive: Bool

//     var body: some View {
//         if isActive {
//             Color.purple.opacity(0.1)
//                 .ignoresSafeArea()
//                 .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: isActive)
//         }
//     }
// } 
