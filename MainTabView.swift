import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var timerStore: TimerStore
    @State private var selectedTab = 1 // 0 = profile, 1 = home, 2 = settings
    @State private var showSheet = false
    @State private var timelineShouldResetScroll = false
    @State private var taskTrails: [UUID: [(start: Date, end: Date, isFocus: Bool)]] = [:]
    @State private var dragOffset: CGFloat = 0
    @State private var sessionResetSignal: Int = 0
    @State private var timer: Timer? = nil
    @State private var now = Date()
    @State private var previousSessionState: SessionState? = nil
    @State private var autoSwitchStates: Bool = false
    @State private var selectedMode: Int = 0
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    // Helper for binding to TimerStore properties
    private func bind<Value>(_ keyPath: ReferenceWritableKeyPath<TimerStore, Value>) -> Binding<Value> {
        let store = timerStore // capture the value once
        return Binding(
            get: { store[keyPath: keyPath] },
            set: { store[keyPath: keyPath] = $0 }
        )
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            mainContent
            customTabBar
        }
        .sheet(isPresented: $showSheet) {
            MinimalDarkSheet(onExecute: { intended, start, end, mode in
                showSheet = false
                guard let s = start, let e = end, let hours = Double(intended) else { return }
                if mode == 1 {
                    timerStore.applyHubermanSessions(startTime: s, endTime: e, totalWorkDuration: hours * 3600)
                } else {
                    timerStore.applyPomodoroSessions(startTime: s, endTime: e, totalWorkDuration: hours * 3600)
                }
                timerStore.save()
                // ---- AUTO-START FIRST WORK SESSION ----
                DispatchQueue.main.async {
                    handleTapToWork()               // identical to pressing the button once
                    selectedTab = 1                 // jump back to "Home" if needed
                }
            }, selectedDate: bind(\.selectedDate))
        }
        .onAppear {
            // --- Restore sessionStartTime if timer is running after app relaunch ---
            if (timerStore.sessionState == .work || timerStore.sessionState == .breakSession),
               let bucketStart = timerStore.bucketStart {
                // sessionStartTime = bucketStart
            }
        }
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            ZStack {
                Color.black.ignoresSafeArea()
                if isCurrentTaskActive {
                    Color.purple.opacity(isGlowing ? 0.10 : 0.04)
                        .ignoresSafeArea()
                        .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: isGlowing)
                }
                switch selectedTab {
                case 0: AnyView(Text("Profile").foregroundColor(.white))
                case 1: AnyView(ContentView(taskTrails: taskTrails))
                case 2: AnyView(settingsView)
                default: AnyView(ContentView(taskTrails: taskTrails))
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
                              isActive: timerStore.sessionState != .paused,
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
                   value: timerStore.sessionState)
        .padding(.bottom, 4)
        .zIndex(2)
    }

    private var isCurrentTaskActive: Bool {
        timerStore.scheduledTasks.contains { task in
            (task.startTime ... task.endTime).contains(Date())
        }
    }

    private var isCurrentTaskWorkSession: Bool {
        timerStore.scheduledTasks.contains { task in
            (task.startTime ... task.endTime).contains(Date()) && (task.category == .focus || task.category == .manualFocus)
        } && timerStore.sessionState == .work
    }

    private var isCurrentTaskBreakSession: Bool {
        timerStore.scheduledTasks.contains { task in
            (task.startTime ... task.endTime).contains(Date()) && (task.category == .freeTime || (task.category == .focus && timerStore.sessionState != .paused))
        }
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            let previousNow = Date()
            now = Date()
            updateTrail(previousNow: previousNow, currentNow: now)
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func updateTrail(previousNow: Date, currentNow: Date) {
        guard let currentTask = timerStore.scheduledTasks.first(where: { $0.contains(date: currentNow) })
        else { return }
        let isWorkSecond = (timerStore.sessionState == .work)
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
        if isCurrentTaskWorkSession && timerStore.sessionState != .paused {
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
        if let currentBlock = timerStore.scheduledTasks.first(where: { t in
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
        switch timerStore.sessionState {
        case .work:         return workAccent
        case .breakSession: return breakAccent
        default:            return Color(.systemGray4)
        }
    }

    private var buttonColor: Color { sessionAccentColor }

    private var isGlowing: Bool {
        timerStore.sessionState == .work && isCurrentTaskWorkSession
    }

    private var buttonYOffset: CGFloat {
        switch timerStore.sessionState {
        case .none, .paused: return 0
        case .work, .breakSession: return -60
        }
    }

    private var sessionTimerMode: TimerView.Mode? {
        switch timerStore.sessionState {
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
        switch timerStore.sessionState {              // handle *current* state
        case .none:
            let start = Date()
            now  = start                 // kick 'now' forward *before* the header draws
            var tasks = timerStore.scheduledTasks
            tasks.append(
                ScheduleTask(name: "ManualFocus", label: "Manual Focus Block",
                             startTime: start,
                             duration: 12 * 60 * 60, // 12 hours generous
                             category: .manualFocus)
            )
            timerStore.scheduledTasksByDate[timerStore.normalizedDate(timerStore.selectedDate)] = tasks
            timerStore.transition(to: .work)       // ③ move to next state
            // Only open the work bucket after closing the previous one
            openBucket(for: .work, customStartTime: start)
            timelineShouldResetScroll.toggle()
        case .work:
            now = Date()
            timerStore.transition(to: .breakSession)
            // Only open the break bucket after closing the previous one
            openBucket(for: .breakSession)
            sessionResetSignal += 1
        case .breakSession, .paused:
            let start = Date()
            now = start                  // kick 'now' forward on resume
            var tasks = timerStore.scheduledTasks
            tasks.append(
                ScheduleTask(name: "ManualFocus", label: "Manual Focus Block",
                             startTime: start,
                             duration: 12 * 60 * 60, // 12 hours generous
                             category: .manualFocus)
            )
            timerStore.scheduledTasksByDate[timerStore.normalizedDate(timerStore.selectedDate)] = tasks
            timerStore.transition(to: .work)
            // Only open the work bucket after closing the previous one
            openBucket(for: .work)
            sessionResetSignal += 1
        }
        assertTimerStateConsistency()
    }

    private func handleDrag(_ dy: CGFloat) {
        if dy > 24, [.work, .breakSession].contains(timerStore.sessionState) {
            // Always close the running bucket before opening a new one
            closeRunningBucket()           // stop work or break bucket
            finaliseManualFocusIfRunning() // clamp task duration
            previousSessionState = timerStore.sessionState
            timerStore.transition(to: .paused)
            // When paused, timer must be nil
            openBucket(for: .paused)       // nothing accrues while paused
        } else if dy < -24, timerStore.sessionState == .paused {
            now                  = Date()
            let start = now
            now = start                  // kick 'now' forward on resume
            var tasks = timerStore.scheduledTasks
            tasks.append(
                ScheduleTask(name: "ManualFocus", label: "Manual Focus Block",
                             startTime: start,
                             duration: 12 * 60 * 60, // 12 hours generous
                             category: .manualFocus)
            )
            timerStore.scheduledTasksByDate[timerStore.normalizedDate(timerStore.selectedDate)] = tasks
            let resumed = previousSessionState ?? .work
            // Always close the running bucket before opening a new one
            closeRunningBucket()
            timerStore.transition(to: resumed)
            // Only open the work bucket after closing the previous one
            openBucket(for: resumed)       // reopen the right bucket
            sessionResetSignal  += 1
        }
        dragOffset = 0
        assertTimerStateConsistency()
    }

    // Helper to get the current session's elapsed time in seconds
    private var currentSessionElapsedTime: Int {
        guard let start = timerStore.bucketStart,
              timerStore.sessionState == .work || timerStore.sessionState == .breakSession else {
            return 0
        }
        return Int(timerStore.now.timeIntervalSince(start))
    }

    private func closeRunningBucket() {
        // TimerStore.transition(to:) will call closeCurrentTrace()
        // and move the elapsed seconds into the correct total.
        // Nothing to do here any more.
    }

    /// Open a fresh bucket if the new state needs one.
    private func openBucket(for newState: SessionState, customStartTime: Date? = nil) {
        guard newState == .work || newState == .breakSession else {
            timerStore.bucketStart   = nil
            timerStore.runningBucket = .none
            return
        }
        // If a bucket is already open, close it first –– protects against double-open
        if timerStore.runningBucket == newState, timerStore.bucketStart != nil {
            closeRunningBucket()
        }
        timerStore.bucketStart   = customStartTime ?? Date()
        timerStore.runningBucket = newState
    }

    /// Debug assertion to ensure timer is only running in valid states
    private func assertTimerStateConsistency() {
        if timerStore.sessionState == .paused || timerStore.sessionState == .none {
            assert(timerStore.bucketStart == nil, "Timer should not be running while paused or none")
        }
        if (timerStore.sessionState == .work || timerStore.sessionState == .breakSession) {
            // It's OK for bucketStart to be nil if just switched, but not for long
        }
    }

    private func format(_ t: TimeInterval) -> String {
        let m = Int(t) / 60, s = Int(t) % 60
        return String(format: "%02d:%02d", m, s)
    }

    private func finaliseManualFocusIfRunning() {
        if let idx = timerStore.scheduledTasks.lastIndex(where: {
            $0.category == .manualFocus &&
            $0.startTime <= Date() &&
            $0.endTime   > Date()
        }) {
            var tasks = timerStore.scheduledTasks
            let start = tasks[idx].startTime
            let actual = Date().timeIntervalSince(start)
            tasks[idx] = tasks[idx].withDuration(actual)
            timerStore.scheduledTasksByDate[timerStore.normalizedDate(timerStore.selectedDate)] = tasks
        }
    }

    // Pomodoro session generator
    private func applyPomodoroSessions(startTime: Date, endTime: Date, totalWorkDuration: TimeInterval) {
        // Clear previous Pomodoro blocks (optional: you may want to filter only Pomodoro blocks)
        var tasks = timerStore.scheduledTasks
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
        timerStore.scheduledTasksByDate[timerStore.normalizedDate(timerStore.selectedDate)] = tasks
    }

    // Huberman session generator
    private func applyHubermanSessions(startTime: Date, endTime: Date, totalWorkDuration: TimeInterval) {
        // Clear previous Huberman blocks (optional: you may want to filter only Huberman blocks)
        var tasks = timerStore.scheduledTasks
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
        timerStore.scheduledTasksByDate[timerStore.normalizedDate(timerStore.selectedDate)] = tasks
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
                    }
                    Spacer()
                    Toggle("", isOn: $autoSwitchStates)
                        .labelsHidden()
                }
                .padding(.horizontal, 22)
            }
            .padding(.horizontal, 18)
            // --- Reset Timers Card ---
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(.systemGray6).opacity(0.18))
                    .frame(height: 74)
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Reset timers")
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                    Spacer()
                    Button(action: resetTimers) {
                        Text("Reset")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(width: 70, height: 36)
                            .background(Color.red)
                            .cornerRadius(8)
                    }
                }
                .padding(.horizontal, 22)
            }
            .padding(.horizontal, 18)
            // --- Delete all work and break blocks Card ---
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(.systemGray6).opacity(0.18))
                    .frame(height: 74)
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Delete all work and break blocks")
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                    Spacer()
                    Button(action: deleteAllWorkAndBreakBlocks) {
                        Text("Reset")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(width: 70, height: 36)
                            .background(Color.red)
                            .cornerRadius(8)
                    }
                }
                .padding(.horizontal, 22)
            }
            .padding(.horizontal, 18)
            // --- Delete existing, current work and break traces Card ---
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(.systemGray6).opacity(0.18))
                    .frame(height: 74)
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Delete existing, current work and break traces")
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                    Spacer()
                    Button(action: deleteAllTraces) {
                        Text("Reset")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(width: 70, height: 36)
                            .background(Color.red)
                            .cornerRadius(8)
                    }
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
        closeRunningBucket()
        finaliseManualFocusIfRunning()
        let now = Date()
        timerStore.transition(to: .work)
        // Only open the work bucket after closing the previous one
        openBucket(for: .work, customStartTime: now)
        sessionResetSignal += 1                // forces TimerView to reset to 00:00
    }

    private func handleTapToBreak() {
        // This mimics the break state transition from handleTap
        closeRunningBucket()
        finaliseManualFocusIfRunning()
        timerStore.transition(to: .breakSession)
        // Only open the break bucket after closing the previous one
        openBucket(for: .breakSession, customStartTime: now)
        sessionResetSignal += 1
    }

    private func resetTimers() {
        timerStore.hardResetTimers()
        sessionResetSignal += 1 // keeps the arrow-button timer at 00:00
    }

    // --- DELETE ALL TRACES ---
    private func deleteAllTraces() {
        timerStore.traces.removeAll()
        timerStore.saveTraces()
    }

    // --- DELETE ALL WORK AND BREAK BLOCKS ---
    private func deleteAllWorkAndBreakBlocks() {
        var tasks = timerStore.scheduledTasks
        tasks.removeAll { $0.category == .focus || $0.category == .manualFocus || $0.category == .freeTime }
        timerStore.scheduledTasks = tasks
        timerStore.save()
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
