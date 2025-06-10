import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 1 // 0 = profile, 1 = home, 2 = settings
    @State private var showSheet = false
    //@State private var scheduledTasks: [ScheduleTask] = []
    @State private var now: Date = Date()
    @State private var timer: Timer? = nil
    @State private var sessionState: SessionState = .none
    @State private var timelineShouldResetScroll = false
    @State private var sessionResetSignal: Int = 0
    @State private var dragOffset: CGFloat = 0
    @State private var previousSessionState: SessionState? = nil
    @State private var taskTrails: [UUID: [(start: Date, end: Date, isFocus: Bool)]] = [:]
    @State private var ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var sessionStartTime: Date? = nil
    @State private var totalWorkTime: TimeInterval = 0
    @State private var totalBreakTime: TimeInterval = 0
    @State private var totalTimerStart: Date? = nil
    @State private var runningBucketState: SessionState = .none
    @State private var autoSwitchStates: Bool = false
    @State private var selectedMode: Int = 0
    @State private var scheduledTasksByDate: [Date: [ScheduleTask]] = [:]
    @State private var selectedDate: Date = Date()

    var body: some View {
        ZStack(alignment: .bottom) {
            mainContent
            customTabBar
        }
        .onReceive(ticker) { _ in
            let newNow = Date()
            let dateKey = normalizedDate(selectedDate)
            // 1. First extend / correct the manual block
            if sessionState == .work, let i = (scheduledTasksByDate[dateKey] ?? []).lastIndex(where: { $0.category == .manualFocus && $0.startTime <= newNow }) {
                var tasks = scheduledTasksByDate[dateKey] ?? []
                let start = tasks[i].startTime
                let live = newNow.timeIntervalSince(start) // exact seconds
                tasks[i] = tasks[i].withDuration(live)
                scheduledTasksByDate[dateKey] = tasks
            }
            // 2. Then use it for the trail & UI
            if [.work, .breakSession].contains(sessionState) {
                updateTrail(previousNow: now, currentNow: newNow)
            }
            // --- AUTO STATE SWITCHING LOGIC ---
            if autoSwitchStates {
                let previousBlock = (scheduledTasksByDate[dateKey] ?? []).first(where: { $0.contains(date: now) })
                let currentBlock = (scheduledTasksByDate[dateKey] ?? []).first(where: { $0.contains(date: newNow) })
                if previousBlock?.id != currentBlock?.id, let block = currentBlock {
                    // Only switch if entering a new block
                    if (block.category == .focus || block.category == .manualFocus) && sessionState != .work {
                        // Entering a work block, switch to work mode
                        handleTapToWork()
                    } else if block.category == .freeTime && sessionState != .breakSession {
                        // Entering a break block, switch to break mode
                        handleTapToBreak()
                    }
                }
            }
            // Only update 'now' for the current session; remove per-session timer logic
            now = newNow
        }
        .sheet(isPresented: $showSheet) {
            MinimalDarkSheet(onExecute: { intended, start, end, mode in
                showSheet = false
                if let s = start, let e = end, let hours = Double(intended) {
                    let startNow = Date()
                    let totalWorkDuration = hours * 3600 // hours to seconds
                    if mode == 1 {
                        // Huberman mode
                        applyHubermanSessions(startTime: startNow, endTime: e, totalWorkDuration: totalWorkDuration)
                        if let _ = scheduledTasksByDate[normalizedDate(selectedDate)]?.first(where: { $0.name == "Huberman Focus" }) {
                            now = startNow
                            sessionState = .work
                            sessionStartTime = startNow
                            openBucket(for: .work, customStartTime: startNow)
                            sessionResetSignal += 1
                        }
                    } else {
                        // Pomodoro mode (default)
                        applyPomodoroSessions(startTime: startNow, endTime: e, totalWorkDuration: totalWorkDuration)
                        if let _ = scheduledTasksByDate[normalizedDate(selectedDate)]?.first(where: { $0.name == "Pomodoro Focus" }) {
                            now = startNow
                            sessionState = .work
                            sessionStartTime = startNow
                            openBucket(for: .work, customStartTime: startNow)
                            sessionResetSignal += 1
                        }
                    }
                    timelineShouldResetScroll.toggle()
                }
            }, selectedDate: $selectedDate)
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
                // Remove Group and use switch directly
                switch selectedTab {
                case 0: AnyView(Text("Profile").foregroundColor(.white))
                case 1: AnyView(ContentView(
                    scheduledTasks: Binding(
                        get: { scheduledTasksByDate[normalizedDate(selectedDate)] ?? [] },
                        set: { scheduledTasksByDate[normalizedDate(selectedDate)] = $0 }
                    ),
                    sessionState: $sessionState,
                    taskTrails: taskTrails,
                    resetScroll: $timelineShouldResetScroll,
                    now: $now,
                    selectedDate: $selectedDate,
                    workTotal: liveWorkTotal,
                    breakTotal: liveBreakTotal
                ))
                case 2: AnyView(settingsView)
                default: AnyView(ContentView(
                    scheduledTasks: Binding(
                        get: { scheduledTasksByDate[normalizedDate(selectedDate)] ?? [] },
                        set: { scheduledTasksByDate[normalizedDate(selectedDate)] = $0 }
                    ),
                    sessionState: $sessionState,
                    taskTrails: taskTrails,
                    resetScroll: $timelineShouldResetScroll,
                    now: $now,
                    selectedDate: $selectedDate,
                    workTotal: liveWorkTotal,
                    breakTotal: liveBreakTotal
                ))
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
            (task.startTime ... task.endTime).contains(now)
        }
    }

    private var isCurrentTaskWorkSession: Bool {
        scheduledTasks.contains { task in
            (task.startTime ... task.endTime).contains(now) && (task.category == .focus || task.category == .manualFocus)
        } && sessionState == .work
    }

    private var isCurrentTaskBreakSession: Bool {
        scheduledTasks.contains { task in
            (task.startTime ... task.endTime).contains(now) && (task.category == .freeTime || (task.category == .focus && sessionState != .paused))
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
        // If not on the home tab, switch to home first
        if selectedTab != 1 {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                selectedTab = 1
            }
            return
        }
        // Always close the running bucket before opening a new one
        closeRunningBucket()               // ① stop current bucket
        finaliseManualFocusIfRunning()     // ② clamp task duration
        switch sessionState {              // handle *current* state
        case .none:
            let start = Date()
            now  = start                 // kick ‘now’ forward *before* the header draws
            var tasks = scheduledTasks
            tasks.append(
                ScheduleTask(name: "ManualFocus", label: "Manual Focus Block",
                             startTime: start,
                             duration: 12 * 60 * 60, // 12 hours generous
                             category: .manualFocus)
            )
            scheduledTasksByDate[normalizedDate(selectedDate)] = tasks
            sessionState     = .work       // ③ move to next state
            sessionStartTime = start
            // Only open the work bucket after closing the previous one
            openBucket(for: .work, customStartTime: start)
            timelineShouldResetScroll.toggle()
        case .work:
            now = Date()
            sessionState     = .breakSession
            sessionStartTime = now
            // Only open the break bucket after closing the previous one
            openBucket(for: .breakSession)
            sessionResetSignal += 1
        case .breakSession, .paused:
            let start = Date()
            now = start                  // kick ‘now’ forward on resume
            var tasks = scheduledTasks
            tasks.append(
                ScheduleTask(name: "ManualFocus", label: "Manual Focus Block",
                             startTime: start,
                             duration: 12 * 60 * 60, // 12 hours generous
                             category: .manualFocus)
            )
            scheduledTasksByDate[normalizedDate(selectedDate)] = tasks
            sessionState     = .work
            sessionStartTime = start
            // Only open the work bucket after closing the previous one
            openBucket(for: .work)
            sessionResetSignal += 1
        }
        assertTimerStateConsistency()
    }

    private func handleDrag(_ dy: CGFloat) {
        if dy > 24, [.work, .breakSession].contains(sessionState) {
            // Always close the running bucket before opening a new one
            closeRunningBucket()           // stop work or break bucket
            finaliseManualFocusIfRunning() // clamp task duration
            previousSessionState = sessionState
            sessionState         = .paused
            sessionStartTime     = nil
            // When paused, timer must be nil
            openBucket(for: .paused)       // nothing accrues while paused
        } else if dy < -24, sessionState == .paused {
            now                  = Date()
            let start = now
            now = start                  // kick ‘now’ forward on resume
            var tasks = scheduledTasks
            tasks.append(
                ScheduleTask(name: "ManualFocus", label: "Manual Focus Block",
                             startTime: start,
                             duration: 12 * 60 * 60, // 12 hours generous
                             category: .manualFocus)
            )
            scheduledTasksByDate[normalizedDate(selectedDate)] = tasks
            let resumed = previousSessionState ?? .work
            // Always close the running bucket before opening a new one
            closeRunningBucket()
            sessionState         = resumed
            sessionStartTime     = start
            // Only open the work bucket after closing the previous one
            openBucket(for: resumed)       // reopen the right bucket
            sessionResetSignal  += 1
        }
        dragOffset = 0
        assertTimerStateConsistency()
    }

    // Helper to get the current session's elapsed time in seconds
    private var currentSessionElapsedTime: Int {
        guard let start = sessionStartTime,
              sessionState == .work || sessionState == .breakSession else {
            return 0
        }
        return Int(Date().timeIntervalSince(start))
    }

    private func closeRunningBucket() {
        guard let start = totalTimerStart else { return }
        let elapsed = Date().timeIntervalSince(start)
        switch runningBucketState {
        case .work:
            totalWorkTime  += elapsed
        case .breakSession:
            totalBreakTime += elapsed
        default:
            break
        }
        totalTimerStart = nil
        runningBucketState = .none
    }

    /// Open a fresh bucket if the new state needs one.
    private func openBucket(for newState: SessionState, customStartTime: Date? = nil) {
        guard newState == .work || newState == .breakSession else {
            totalTimerStart   = nil
            runningBucketState = .none
            return
        }
        // If a bucket is already open, close it first –– protects against double-open
        if runningBucketState == newState, totalTimerStart != nil {
            closeRunningBucket()
        }
        totalTimerStart   = customStartTime ?? Date()
        runningBucketState = newState
    }

    /// Work total that is always correct, paused or running.
    private var liveWorkTotal: TimeInterval {
        var total = totalWorkTime                // frozen seconds
        // Only accrue live delta while *really* in work and bucket is open
        if sessionState == .work, runningBucketState == .work, let start = totalTimerStart {
            total += Date().timeIntervalSince(start)
        }
        // Defensive: never show a negative or non-finite value
        if !total.isFinite || total < 0 { return 0 }
        return total
    }

    private var liveBreakTotal: TimeInterval {
        var total = totalBreakTime
        if sessionState == .breakSession, runningBucketState == .breakSession, let start = totalTimerStart {
            total += Date().timeIntervalSince(start)
        }
        if !total.isFinite || total < 0 { return 0 }
        return total
    }

    /// Debug assertion to ensure timer is only running in valid states
    private func assertTimerStateConsistency() {
        if sessionState == .paused || sessionState == .none {
            assert(totalTimerStart == nil, "Timer should not be running while paused or none")
        }
        if (sessionState == .work || sessionState == .breakSession) {
            // It's OK for totalTimerStart to be nil if just switched, but not for long
        }
    }

    private func format(_ t: TimeInterval) -> String {
        let m = Int(t) / 60, s = Int(t) % 60
        return String(format: "%02d:%02d", m, s)
    }

    private func finaliseManualFocusIfRunning() {
        if let idx = scheduledTasks.lastIndex(where: {
            $0.category == .manualFocus &&
            $0.startTime <= Date() &&
            $0.endTime   > Date()
        }) {
            var tasks = scheduledTasks
            let start = tasks[idx].startTime
            let actual = Date().timeIntervalSince(start)
            tasks[idx] = tasks[idx].withDuration(actual)
            scheduledTasksByDate[normalizedDate(selectedDate)] = tasks
        }
    }

    // Pomodoro session generator
    private func applyPomodoroSessions(startTime: Date, endTime: Date, totalWorkDuration: TimeInterval) {
        // Clear previous Pomodoro blocks (optional: you may want to filter only Pomodoro blocks)
        var tasks = scheduledTasks
        tasks.removeAll(where: { $0.name == "Pomodoro Focus" || $0.name == "Pomodoro Break" || $0.name == "Pomodoro Long Break" })
        
        let focusBlockDuration: TimeInterval = 25 * 60
        let shortBreakDuration: TimeInterval = 5 * 60
        let longBreakDuration: TimeInterval = 30 * 60
        let blocksPerCycle = 4
        
        var current = startTime
        var workAccum: TimeInterval = 0
        
        while workAccum < totalWorkDuration && current < endTime {
            // One Pomodoro cycle
            for i in 0..<blocksPerCycle {
                // Focus block
                if workAccum >= totalWorkDuration || current >= endTime { break }
                let focusEnd = min(current.addingTimeInterval(focusBlockDuration), endTime)
                let actualFocusDuration = focusEnd.timeIntervalSince(current)
                if actualFocusDuration > 0 {
                    tasks.append(ScheduleTask(
                        name: "Pomodoro Focus",
                        label: "Pomodoro Focus Block",
                        startTime: current,
                        duration: actualFocusDuration,
                        category: .focus
                    ))
                    workAccum += actualFocusDuration
                    current = focusEnd
                }
                // If we've hit work duration or end time, stop
                if workAccum >= totalWorkDuration || current >= endTime { break }
                // Break block (short, except after last focus in cycle)
                if i < blocksPerCycle - 1 {
                    let breakEnd = min(current.addingTimeInterval(shortBreakDuration), endTime)
                    let actualBreakDuration = breakEnd.timeIntervalSince(current)
                    if actualBreakDuration > 0 {
                        tasks.append(ScheduleTask(
                            name: "Pomodoro Break",
                            label: "Pomodoro Break Block",
                            startTime: current,
                            duration: actualBreakDuration,
                            category: .freeTime
                        ))
                        current = breakEnd
                    }
                }
            }
            // After 4 focus blocks, add a long break if time allows
            if workAccum < totalWorkDuration && current < endTime {
                let longBreakEnd = min(current.addingTimeInterval(longBreakDuration), endTime)
                let actualLongBreakDuration = longBreakEnd.timeIntervalSince(current)
                if actualLongBreakDuration > 0 {
                    tasks.append(ScheduleTask(
                        name: "Pomodoro Long Break",
                        label: "Pomodoro Long Break Block",
                        startTime: current,
                        duration: actualLongBreakDuration,
                        category: .freeTime
                    ))
                    current = longBreakEnd
                }
            }
        }
        scheduledTasksByDate[normalizedDate(selectedDate)] = tasks
    }

    // Huberman session generator
    private func applyHubermanSessions(startTime: Date, endTime: Date, totalWorkDuration: TimeInterval) {
        // Clear previous Huberman blocks (optional: you may want to filter only Huberman blocks)
        var tasks = scheduledTasks
        tasks.removeAll(where: { $0.name == "Huberman Focus" || $0.name == "Huberman Break" })
        
        let focusBlockDuration: TimeInterval = 90 * 60
        let breakBlockDuration: TimeInterval = 15 * 60
        
        var current = startTime
        var workAccum: TimeInterval = 0
        
        while workAccum < totalWorkDuration && current < endTime {
            // Focus block
            if workAccum >= totalWorkDuration || current >= endTime { break }
            let focusEnd = min(current.addingTimeInterval(focusBlockDuration), endTime)
            let actualFocusDuration = focusEnd.timeIntervalSince(current)
            if actualFocusDuration > 0 {
                tasks.append(ScheduleTask(
                    name: "Huberman Focus",
                    label: "Huberman Focus Block",
                    startTime: current,
                    duration: actualFocusDuration,
                    category: .focus
                ))
                workAccum += actualFocusDuration
                current = focusEnd
            }
            // If we've hit work duration or end time, stop
            if workAccum >= totalWorkDuration || current >= endTime { break }
            // Break block
            let breakEnd = min(current.addingTimeInterval(breakBlockDuration), endTime)
            let actualBreakDuration = breakEnd.timeIntervalSince(current)
            if actualBreakDuration > 0 {
                tasks.append(ScheduleTask(
                    name: "Huberman Break",
                    label: "Huberman Break Block",
                    startTime: current,
                    duration: actualBreakDuration,
                    category: .freeTime
                ))
                current = breakEnd
            }
        }
        scheduledTasksByDate[normalizedDate(selectedDate)] = tasks
    }

    private var settingsView: some View {
        VStack(spacing: 24) {
            Spacer().frame(height: 32)
            HStack {
                Text("Settings")
                    .font(.largeTitle).bold()
                    .foregroundColor(.white)
                Spacer()
            }
            .padding(.horizontal, 24)
            // Auto state switching card
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(.systemGray6).opacity(0.18))
                    .frame(height: 74)
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Auto state switching between blocks")
                            .font(.headline)
                            .foregroundColor(.white)
                        // Text("Automatically switch between work and break modes")
                        //     .font(.subheadline)
                        //     .foregroundColor(Color(white: 0.8))
                    }
                    Spacer()
                    Toggle("", isOn: $autoSwitchStates)
                        .labelsHidden()
                }
                .padding(.horizontal, 22)
            }
            .padding(.horizontal, 18)
            Spacer()
        }
        .background(Color.black.ignoresSafeArea())
    }

    // --- AUTO SWITCH HELPERS ---
    private func handleTapToWork() {
        // This mimics the work state transition from handleTap
        closeRunningBucket()
        finaliseManualFocusIfRunning()
        sessionState = .work
        sessionStartTime = now
        openBucket(for: .work, customStartTime: now)
        sessionResetSignal += 1
    }

    private func handleTapToBreak() {
        // This mimics the break state transition from handleTap
        closeRunningBucket()
        finaliseManualFocusIfRunning()
        sessionState = .breakSession
        sessionStartTime = now
        openBucket(for: .breakSession, customStartTime: now)
        sessionResetSignal += 1
    }

    // Helper to normalize a date to midnight (for dictionary keys)
    private func normalizedDate(_ date: Date) -> Date {
        let cal = Calendar.current
        return cal.startOfDay(for: date)
    }

    // Helper to get or set tasks for the selected date
    private var scheduledTasks: [ScheduleTask] {
        get { scheduledTasksByDate[normalizedDate(selectedDate)] ?? [] }
        set { scheduledTasksByDate[normalizedDate(selectedDate)] = newValue }
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
        precondition(new > 0 && new.isFinite, "Duration must be positive & finite")
        return .init(id: self.id, name: name, label: label, startTime: startTime, duration: new, category: category)
    }
} 
