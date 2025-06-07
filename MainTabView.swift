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
            mainContent
            customTabBar
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
                    case 1: ContentView(scheduledTasks: $scheduledTasks, sessionState: $sessionState, taskTrails: taskTrails, resetScroll: $timelineShouldResetScroll)
                    case 2: Text("Settings").foregroundColor(.white)
                    default: ContentView(scheduledTasks: $scheduledTasks, sessionState: $sessionState, taskTrails: taskTrails, resetScroll: $timelineShouldResetScroll)
                    }
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
        .background(
            Color(.systemGray6)
                .opacity(0.15)
                .blur(radius: 10)
                .ignoresSafeArea(edges: .bottom)
        )
        .overlay(triangleButtonOverlay)
    }

    private var triangleButtonOverlay: some View {
        let dragRange: ClosedRange<CGFloat> = -32...32   // finger travel

        return VStack(spacing: 12) {         // TIMER ▶︎ always above BUTTON
            // ── bullet + timer ───────────────────────
            if let mode = sessionTimerMode {
                HStack(spacing: 4) {
                    Circle()
                        .fill(sessionAccentColor)
                        .frame(width: 8, height: 8)
                    TimerView(mode: mode,
                              isActive: sessionState != .paused,
                              resetSignal: sessionResetSignal)
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
        }
        // ⬇︎ move BOTH timer and button together
        .offset(y: buttonYOffset + dragOffset)
        .contentShape(Rectangle())            // correct hit-test
        // ── gestures on the whole stack ─────────────────────────────
        .highPriorityGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    dragOffset = dragRange.clamp(value.translation.height)
                }
                .onEnded { value in
                    if value.translation.height > 24,
                       [.work, .breakSession].contains(sessionState) {
                        previousSessionState = sessionState
                        sessionState         = .paused
                    } else if value.translation.height < -24,
                              sessionState == .paused {
                        sessionState         = previousSessionState ?? .work
                        sessionResetSignal  += 1
                    }
                    dragOffset = 0
                }
        )
        .simultaneousGesture(
            TapGesture()
                .onEnded {
                    switch sessionState {
                    case .none:
                        showSheet = true
                    case .work:
                        sessionState = .breakSession
                        sessionResetSignal += 1
                    case .breakSession, .paused:
                        sessionState = .work
                        sessionResetSignal += 1
                    }
                }
        )
        // smooth motion for finger-drag **and** session state change
        .animation(.interactiveSpring(), value: dragOffset)
        .animation(.spring(response: 0.35, dampingFraction: 0.8),
                   value: sessionState)
        .padding(.bottom, 4)
        .zIndex(2)
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
        let isFocus = isGlowing && sessionState != .paused && currentTask.category == .focus
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

    private var isCurrentTaskBreakSession: Bool {
        let calendar = Calendar.current
        return scheduledTasks.contains { task in
            calendar.compare(now, to: task.startTime, toGranularity: .minute) != .orderedAscending &&
            calendar.compare(now, to: task.endTime, toGranularity: .minute) == .orderedAscending &&
            (task.category == .freeTime || (task.category == .focus && sessionState != .paused))
        }
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

    private var isGlowing: Bool { sessionState == .work }

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
            .onChange(of: resetSignal) {
                if resetSignal != lastResetSignal {
                    sessionTimer = 0
                    lastResetSignal = resetSignal
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

private extension ClosedRange where Bound == CGFloat {
    func clamp(_ value: CGFloat) -> CGFloat {
        min(max(lowerBound, value), upperBound)
    }
} 
