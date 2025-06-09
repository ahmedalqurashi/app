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
    @State private var ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack(alignment: .bottom) {
            mainContent
            customTabBar
        }
        .onReceive(ticker) { _ in
            let newNow = Date()
            // 1. First extend / correct the manual block
            if sessionState == .work, let i = scheduledTasks.lastIndex(where: { $0.category == .manualFocus && $0.startTime <= newNow }) {
                let start = scheduledTasks[i].startTime
                let live = newNow.timeIntervalSince(start) + 2 // keep it ahead
                scheduledTasks[i] = scheduledTasks[i].withDuration(live)
            }
            // 2. Then use it for the trail & UI
            if [.work, .breakSession].contains(sessionState) {
                updateTrail(previousNow: now, currentNow: newNow)
            }
            // Only update 'now' for the current session; remove per-session timer logic
            now = newNow
        }
        .sheet(isPresented: $showSheet) {
            MinimalDarkSheet { intended, start, end in
                showSheet = false
                if let s = start, let e = end {
                    let task = ScheduleTask(
                        name: "Focus",
                        startTime: s,
                        duration: e.timeIntervalSince(s),
                        category: .focus
                    )
                    scheduledTasks.append(task)
                    sessionState = .work
                    timelineShouldResetScroll.toggle()
                }
            }
        }
    }
//  ZStack {
//             Color.black.ignoresSafeArea()
//             GlowingEdgeView(isActive: true)
//         }
    private var mainContent: some View {
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
                    case 1: ContentView(scheduledTasks: $scheduledTasks, sessionState: $sessionState, taskTrails: taskTrails, resetScroll: $timelineShouldResetScroll, now: $now)
                    case 2: Text("Settings").foregroundColor(.white)
                    default: ContentView(scheduledTasks: $scheduledTasks, sessionState: $sessionState, taskTrails: taskTrails, resetScroll: $timelineShouldResetScroll, now: $now)
                    }
                }
                if isCurrentTaskWorkSession {
                    GlowingEdgeView(isActive: true)
                } 
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var customTabBar: some View {
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
        // .background(
        //     Color(.systemGray6)
        //         .opacity(0.15)
        //         .blur(radius: 10)
        //         .ignoresSafeArea(edges: .bottom)
        // )
        .overlay(triangleButtonOverlay)
    }

    private var triangleButtonOverlay: some View {
        let dragRange: ClosedRange<CGFloat> = -32...32   // finger travel
        let elapsedTime = currentSessionElapsedTime
        return VStack(spacing: 12) {         // TIMER ▶︎ always above BUTTON
            // ── bullet + timer ───────────────────────
            if let mode = sessionTimerMode {
                HStack(spacing: 4) {
                    Circle()
                        .fill(sessionAccentColor)
                        .frame(width: 8, height: 8)
                    TimerView(mode: mode,
                              isActive: sessionState != .paused,
                              resetSignal: sessionResetSignal,
                              elapsedTime: elapsedTime)
                }
            }

            // ── arrow button ─────────────────────────
            ZStack {
                Circle()
                    .fill(sessionAccentColor)
                    .shadow(color: isGlowing ? sessionAccentColor.opacity(0.7) : .clear,
                            radius: isGlowing ? 24 : 10)
                Image(systemName: "arrowtriangle.up.fill")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(.white)
            }
            .frame(width: 64, height: 64)
            .gesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { value in
                        dragOffset = dragRange.clamp(value.translation.height)
                    }
                    .onEnded { value in
                        handleDrag(value.translation.height)
                    }
            )
            .onTapGesture {
                handleTap()
            }
            .onLongPressGesture {
                showSheet = true
            }
        }
        // ⬇︎ move BOTH timer and button together
        .offset(y: buttonYOffset + dragOffset)
        .contentShape(Rectangle())            // correct hit-test
        // smooth motion for finger-drag **and** session state change
        .animation(.interactiveSpring(), value: dragOffset)
        .animation(.spring(response: 0.35, dampingFraction: 0.8),
                   value: sessionState)
        .padding(.bottom, 4)
        .zIndex(2)
    }

    private var isCurrentTaskActive: Bool {
        scheduledTasks.contains { task in
            task.startTime <= now && now < task.endTime
        }
    }

    private var isCurrentTaskWorkSession: Bool {
        scheduledTasks.contains { task in
            task.startTime <= now && now < task.endTime && (task.category == .focus || task.category == .manualFocus)
        } && sessionState == .work
    }

    private var isCurrentTaskBreakSession: Bool {
        scheduledTasks.contains { task in
            task.startTime <= now && now < task.endTime && (task.category == .freeTime || (task.category == .focus && sessionState != .paused))
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
        guard let currentTask = scheduledTasks.first(where: { $0.contains(date: currentNow) })
        else { return }
        let isWorkSecond = (sessionState == .work)
        var intervals = taskTrails[currentTask.id] ?? []
        if let last = intervals.last,
           last.isFocus == isWorkSecond,
           Calendar.current.isDate(last.end, equalTo: previousNow, toGranularity: .second) {
            intervals[intervals.count - 1].end = currentNow
        } else {
            intervals.append((start: previousNow, end: currentNow, isFocus: isWorkSecond))
        }
        taskTrails[currentTask.id] = intervals
    }

    private var currentTimerMode: TimerView.Mode? {
        if isCurrentTaskWorkSession && sessionState != .paused {
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

    private let darkPurple = Color(red: 0.4, green: 0.0, blue: 0.7)

    // MARK: – session accent colours  (place near other constants)
    private let workAccent  = Color(red: 0.6, green: 0.1, blue: 1.0)  // same as TimerView
    private let breakAccent = Color(red: 0.1, green: 0.4, blue: 1.0)

    private var sessionAccentColor: Color {
        switch sessionState {
        case .work:         return workAccent
        case .breakSession: return breakAccent
        default:            return Color(.systemGray4)
        }
    }

    private var buttonColor: Color { sessionAccentColor }

    private var isGlowing: Bool { sessionState == .work && isCurrentTaskWorkSession }

    private var buttonYOffset: CGFloat {
        switch sessionState {
        case .none, .paused: return 0
        case .work, .breakSession: return -60
        }
    }

    private var sessionTimerMode: TimerView.Mode? {
        switch sessionState {
        case .work:         return .work
        case .breakSession: return .breakTime
        default:            return nil        // hide when .none or .paused
        }
    }

    private func handleTap() {
        switch sessionState {
        case .none:
            let start = Date()
            scheduledTasks.append(
                ScheduleTask(name: "ManualFocus",
                             startTime: start,
                             duration: 12 * 60 * 60, // 12 hours generous
                             category: .manualFocus)
            )
            sessionState = .work
            timelineShouldResetScroll.toggle()
        case .work:
            // Finalize the current manual focus task if it exists
            if let idx = scheduledTasks.lastIndex(where: { $0.category == .manualFocus && $0.startTime <= Date() && $0.endTime > Date() }) {
                let start = scheduledTasks[idx].startTime
                let actualDuration = Date().timeIntervalSince(start)
                scheduledTasks[idx] = scheduledTasks[idx].withDuration(actualDuration)
            }
            sessionState = .breakSession
            sessionResetSignal += 1
        case .breakSession, .paused:
            let start = Date()
            scheduledTasks.append(
                ScheduleTask(name: "ManualFocus",
                             startTime: start,
                             duration: 12 * 60 * 60, // 12 hours generous
                             category: .manualFocus)
            )
            sessionState = .work
            sessionResetSignal += 1
        }
    }

    private func handleDrag(_ dy: CGFloat) {
        if dy > 24, [.work, .breakSession].contains(sessionState) {
            // Finalize the current manual focus task if it exists
            if let idx = scheduledTasks.lastIndex(where: { $0.category == .manualFocus && $0.startTime <= Date() && $0.endTime > Date() }) {
                let start = scheduledTasks[idx].startTime
                let actualDuration = Date().timeIntervalSince(start)
                scheduledTasks[idx] = scheduledTasks[idx].withDuration(actualDuration)
            }
            previousSessionState = sessionState
            sessionState         = .paused
        } else if dy < -24, sessionState == .paused {
            let start = Date()
            scheduledTasks.append(
                ScheduleTask(name: "ManualFocus",
                             startTime: start,
                             duration: 12 * 60 * 60, // 12 hours generous
                             category: .manualFocus)
            )
            sessionState         = previousSessionState ?? .work
            sessionResetSignal  += 1
        }
        dragOffset = 0
    }

    // Helper to get the current session's elapsed time in seconds
    private var currentSessionElapsedTime: Int {
        return 0
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
    let elapsedTime: Int
    var bodyColor: Color {
        mode == .work ? Color(red: 0.6, green: 0.1, blue: 1.0) : Color(red: 0.1, green: 0.4, blue: 1.0)
    }
    var shadowColor: Color {
        bodyColor.opacity(0.7)
    }
    var body: some View {
        Text(String(format: "%02d:%02d", elapsedTime / 60, elapsedTime % 60))
            .font(.system(size: 22, weight: .bold, design: .monospaced))
            .foregroundColor(isActive ? bodyColor : Color.gray)
            .shadow(color: isActive ? shadowColor : .clear, radius: 8, x: 0, y: 0)
            .padding(.horizontal, 9)
            .padding(.vertical, 10)
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

private extension ClosedRange where Bound == CGFloat {
    func clamp(_ value: CGFloat) -> CGFloat {
        min(max(lowerBound, value), upperBound)
    }
}

extension ScheduleTask {
    func contains(date: Date) -> Bool {
        startTime ... endTime ~= date
    }

    func withDuration(_ new: TimeInterval) -> ScheduleTask {
        .init(id: self.id, name: name, startTime: startTime, duration: new, category: category)
    }
} 
