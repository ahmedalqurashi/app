import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 1 // 0 = profile, 1 = home, 2 = settings
    @State private var showSheet = false
    @State private var scheduledTasks: [ScheduleTask] = []
    @State private var now: Date = Date()
    @State private var timer: Timer? = nil
    @State private var isGlowing = false
    @State private var showBanner = false
    @State private var isPausedByUser = false
    @State private var taskTrails: [UUID: [(start: Date, end: Date, isFocus: Bool)]] = [:]
    @State private var timelineShouldResetScroll = false
    @State private var sessionResetSignal: Int = 0

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
                        case 1: ContentView(scheduledTasks: $scheduledTasks, isPausedByUser: $isPausedByUser, taskTrails: taskTrails, resetScroll: $timelineShouldResetScroll)
                        case 2: Text("Settings").foregroundColor(.white)
                        default: ContentView(scheduledTasks: $scheduledTasks, isPausedByUser: $isPausedByUser, taskTrails: taskTrails, resetScroll: $timelineShouldResetScroll)
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
                    // --- TIMER APPEARS HERE ---
                    if let timerMode = currentTimerMode {
                        TimerView(mode: timerMode, isActive: isCurrentTaskActive, resetSignal: sessionResetSignal)
                            .offset(y: -95)
                            //.offset(x: 1)
                            .zIndex(2)
                    }
                    // --- END TIMER ---
                    ZStack {
                        Image(systemName: "arrowtriangle.up.fill")
                            .font(.system(size: 36, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 64, height: 64)
                            .background(
                                Circle()
                                    .fill(isCurrentTaskActive ? darkPurple : Color(.systemGray4))
                                    .shadow(color: isCurrentTaskActive ? darkPurple.opacity((isGlowing && !isPausedByUser) ? 0.7 : 0.3) : Color(.systemGray4).opacity(0.2), radius: isCurrentTaskActive ? ((isGlowing && !isPausedByUser) ? 24 : 10) : 10)
                            )
                            .scaleEffect(isCurrentTaskActive && isGlowing && !isPausedByUser ? 1.12 : 1.0)
                            .animation(isCurrentTaskActive && !isPausedByUser ? .easeInOut(duration: 1.2).repeatForever(autoreverses: true) : .default, value: isGlowing)
                    }
                    .contentShape(Circle())
                    .offset(y: (selectedTab == 0 || selectedTab == 2) ? 0 : -32)
                    .animation(.spring(response: 0.4, dampingFraction: 0.7), value: selectedTab)
                    .onTapGesture {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                            if selectedTab == 0 || selectedTab == 2 {
                                selectedTab = 1 // Go to home
                            } else {
                                // Old pause/resume logic
                                if scheduledTasks.isEmpty {
                                    showSheet = true
                                } else if isCurrentTaskActive && isGlowing && !isPausedByUser {
                                    // Pause: stop glowing, set paused
                                    isPausedByUser = true
                                    isGlowing = false
                                } else if isCurrentTaskActive && !isGlowing && isPausedByUser {
                                    // Resume: start glowing, unset paused
                                    isPausedByUser = false
                                    isGlowing = true
                                }
                            }
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
            if isCurrentTaskActive && !isPausedByUser && isCurrentTaskWorkSession {
                isGlowing = true
            } else {
                isGlowing = false
            }
        }
        .onDisappear {
            stopTimer()
        }
        .onChange(of: isCurrentTaskActive) { active in
            if active && !isPausedByUser && isCurrentTaskWorkSession {
                isGlowing = true
            } else {
                isGlowing = false
            }
        }
        .onChange(of: isPausedByUser) { paused in
            if paused {
                isGlowing = false
            } else if isCurrentTaskActive && isCurrentTaskWorkSession {
                isGlowing = true
            }
        }
        .onChange(of: isCurrentTaskWorkSession) { isWork in
            if isWork && isCurrentTaskActive && !isPausedByUser {
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
        let isFocus = isGlowing && !isPausedByUser && currentTask.category == .focus
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
        if isCurrentTaskWorkSession && !isPausedByUser {
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
            (task.category == .freeTime || (task.category == .focus && isPausedByUser))
        }
    }

    private let darkPurple = Color(red: 0.4, green: 0.0, blue: 0.7)
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
            .padding(.horizontal, 24)
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
