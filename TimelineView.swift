import SwiftUI

struct TimelineView<Content: View>: View {
    let tasks: [ScheduleTask]
    let sessionState: SessionState
    let selectedDate: Date
    let content: (ScheduleTask, Date, Bool, Bool) -> Content
    let hourHeight: CGFloat = 120 //was 80
    let slotsInDay = 48 // 24 hours * 2 (every 30 minutes)
    let labelSpacing: CGFloat = 16 // Adjust this value for more or less space
    
    @State private var isGlowing = false
    @State private var debugMode = false
    @State private var debugHour: Double = 9.0 // Start at 9 AM
    @State private var scrollProxyRef: ScrollViewProxy?
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var timerStore: TimerStore
    private var currentTimeMarkerID: String { "currentTime-\(Int(Date().timeIntervalSince1970))" }
    
    @State private var showTraceSheet = false
    @State private var selectedTrace: TimeTrace? = nil
    
    init(tasks: [ScheduleTask], sessionState: SessionState, selectedDate: Date, @ViewBuilder content: @escaping (ScheduleTask, Date, Bool, Bool) -> Content) {
        self.tasks = tasks
        self.sessionState = sessionState
        self.selectedDate = selectedDate
        self.content = content
    }
    
    private let calendar = Calendar.current
    private let hourFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mma"
        return formatter
    }()
    
    var body: some View {
        VStack {
            timelineContent()
        }
        .onAppear {
            requestCentering()
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                requestCentering()
            }
        }
        .sheet(isPresented: $showTraceSheet) {
            if let trace = selectedTrace {
                TraceInfoSheet(trace: trace,
                              onDelete: {
                                  if let idx = timerStore.traces.firstIndex(where: { $0.id == trace.id }) {
                                      timerStore.traces.remove(at: idx)
                                      timerStore.saveTraces()
                                      timerStore.recalculateTotalsFromTraces()
                                  }
                                  showTraceSheet = false
                              },
                              onUpdate: { updatedTrace in
                                  if let idx = timerStore.traces.firstIndex(where: { $0.id == updatedTrace.id }) {
                                      timerStore.traces[idx] = updatedTrace
                                      timerStore.saveTraces()
                                      timerStore.recalculateTotalsFromTraces()
                                  }
                                  showTraceSheet = false
                              },
                              onClose: { showTraceSheet = false })
                    .presentationDetents([.medium, .large])
            }
        }
    }
    
    private func formatHour(_ hour: Int) -> String {
        let date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: Date())!
        return hourFormatter.string(from: date)
    }
    
    private func formatHourMinute(hour: Int, minute: Int) -> String {
        let date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: Date())!
        return hourFormatter.string(from: date)
    }
    
    private func timeToPosition(_ date: Date) -> CGFloat {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let hour = CGFloat(components.hour ?? 0)
        let minute = CGFloat(components.minute ?? 0)
        let totalHours = hour + (minute / 60.0)
        return totalHours * hourHeight
    }
    
    private func taskHeight(_ task: ScheduleTask) -> CGFloat {
        let durationHours = task.duration / 3600
        return CGFloat(durationHours) * hourHeight //-3 was placed here to make the task height smaller
    }
    
    private func formattedDebugTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: date)
    }
    
    private func requestCentering() {
        guard let proxy = scrollProxyRef else { return }
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.5)) {
                proxy.scrollTo("currentTime", anchor: .top)
            }
        }
    }
    
    // MARK: - Private helpers      (root view)
    @ViewBuilder
    private func timelineContent() -> some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                Color.clear.onAppear { scrollProxyRef = proxy }
                let now = selectedDate
                HStack(alignment: .top, spacing: 0) {
                    HourLabels(
                        slots: slotsInDay,
                        hourHeight: hourHeight,
                        formatter: formatHour
                    )
                    .frame(width: 54) // Fixed width for time labels

                    ZStack(alignment: .top) {
                        GridLines(slots: slotsInDay, hourHeight: hourHeight)
                        // --- COMPLETED TRACES --------------------------------------------------
                        ForEach(timerStore.traces
                                .filter { calendar.isDate($0.start, inSameDayAs: selectedDate) }) { t in
                            let yStart = timeToPosition(t.start)
                            let yEnd   = timeToPosition(t.end)
                            let color  = t.isFocus
                                        ? Color(red: 0.6, green: 0.1, blue: 1.0)   // purple
                                        : Color(red: 0.1, green: 0.4, blue: 1.0)   // blue
                            RoundedRectangle(cornerRadius: 3)
                                .fill(color.opacity(0.24))
                                .frame(maxWidth: .infinity)
                                .frame(height: max(2, yEnd - yStart))
                                .offset(y: yStart)
                                .zIndex(1)                 // below the live trace, above grid lines
                                .onLongPressGesture(minimumDuration: 1.0) {
                                    selectedTrace = t
                                    showTraceSheet = true
                                }
                        }
                        // --- LIVE TRACE (current bucket) --------------------------------------
                        if Calendar.current.isDateInToday(selectedDate),
                           let bucketStart = timerStore.bucketStart,
                           (timerStore.sessionState == .work || timerStore.sessionState == .breakSession)
                        {
                            let color  = timerStore.sessionState == .work
                                         ? Color(red: 0.6, green: 0.1, blue: 1.0)
                                         : Color(red: 0.1, green: 0.4, blue: 1.0)
                            let yStart = timeToPosition(bucketStart)
                            let yEnd   = timeToPosition(timerStore.now)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(color.opacity(0.28))
                                .frame(maxWidth: .infinity)
                                .frame(height: max(2, yEnd - yStart))
                                .offset(y: yStart)
                                .zIndex(2)                 // sits on top of finished traces
                                .animation(.linear(duration: 1), value: timerStore.now)
                        }
                        TaskLayer(
                            tasks: tasks.sorted { $0.startTime < $1.startTime },
                            now: now,
                            hourHeight: hourHeight,
                            content: content,
                            isPausedByUser: sessionState == .paused
                        )
                        Color.clear
                            .frame(height: 1)
                            .alignmentGuide(.top) { _ in -timeToPosition(now) }
                            .id("currentTime")
                        if Calendar.current.isDateInToday(selectedDate) {
                            Rectangle()
                                .fill(Color(red: 1, green: 0.84, blue: 0))
                                .frame(height: 2)
                                .offset(y: timeToPosition(Date()))
                                .zIndex(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                }
                .padding(.horizontal, 8)
            }
        }
    }
    
    var timeScaleColor: Color? {
        switch sessionState {
        case .work: return .purple
        case .breakSession: return .blue
        default: return nil
        }
    }
}

struct TaskBlockView: View {
    let task: ScheduleTask
    let hourWidth: CGFloat // Not used in vertical, but kept for compatibility
    let now: Date
    let debugMode: Bool
    let isPausedByUser: Bool // not used anymore, but kept for compatibility
    let trail: [(start: Date, end: Date, isFocus: Bool)]
    
    var body: some View {
        let calendar = Calendar.current
        let taskStart = task.startTime
        let taskEnd = task.endTime
        let totalDuration = taskEnd.timeIntervalSince(taskStart)
        return ZStack(alignment: .top) {
            // Render the trail as vertical highlights
            GeometryReader { geo in
                let height = geo.size.height
                ForEach(0..<trail.count, id: \.self) { i in
                    let interval = trail[i]
                    let intervalStart = max(interval.start, taskStart)
                    let intervalEnd = min(interval.end, taskEnd)
                    let startFrac = intervalStart.timeIntervalSince(taskStart) / totalDuration
                    let endFrac = intervalEnd.timeIntervalSince(taskStart) / totalDuration
                    let segHeight = max(0, (endFrac - startFrac) * height)
                    let yOffset = max(0, startFrac * height)
                    Rectangle()
                        .fill((task.category == .focus || task.category == .manualFocus) && interval.isFocus ? Color.purple : Color.blue.opacity(0.7))
                        .frame(height: segHeight)
                        .offset(y: yOffset)
                        .animation(.easeInOut(duration: 1), value: trail.count)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            // Render the default background for the rest of the task
            if task.category != .manualFocus {
                RoundedRectangle(cornerRadius: 8)
                    .fill(task.category.color.opacity(0.3))
            }
            // Optional: add a border or shadow
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.black.opacity(0.2), lineWidth: 1)
        }
    }
}

// struct TimelineView_Previews: PreviewProvider {
//     static var previews: some View {
//         let calendar = Calendar.current
//         let now = Date()
//         let sampleTasks = [
//             ScheduleTask(name: "Deep Work", label: "Deep Work Block", startTime: calendar.date(bySettingHour: 9, minute: 0, second: 0, of: now)!, duration: 2 * 3600, category: .focus),
//             ScheduleTask(name: "Team Meeting", label: "Team Meeting Block", startTime: calendar.date(bySettingHour: 11, minute: 30, second: 0, of: now)!, duration: 1 * 3600, category: .admin),
//             ScheduleTask(name: "Lunch Break", label: "Lunch Break Block", startTime: calendar.date(bySettingHour: 13, minute: 0, second: 0, of: now)!, duration: 1 * 3600, category: .freeTime),
//             ScheduleTask(name: "Project Planning", label: "Project Planning Block", startTime: calendar.date(bySettingHour: 14, minute: 0, second: 0, of: now)!, duration: 1.5 * 3600, category: .focus)
//         ]
//         TimelineView(tasks: sampleTasks, sessionState: .work, selectedDate: now, content: { task, now, debugMode, _ in
//             TaskBlockView(task: task, hourWidth: 150, now: now, debugMode: debugMode, isPausedByUser: false, trail: [])
//         })
//     }
// }

/// 30-min and hour grid lines
private struct GridLines: View {
    let slots: Int
    let hourHeight: CGFloat
    var body: some View {
        ForEach(0..<slots, id: \.self) { slot in
            if slot.isMultiple(of: 2) {
                Rectangle()
                    .fill(.white.opacity(0.15))
                    .frame(height: 1)
                    .offset(y: CGFloat(slot) * (hourHeight/2))
            } else {
                Path { p in
                    let y = CGFloat(slot) * (hourHeight/2) + 0.5
                    p.move(to: .init(x: 0, y: y))
                    p.addLine(to: .init(x: 1_000, y: y))
                }
                .stroke(style: .init(lineWidth: 1, dash: [3,4]))
                .foregroundColor(.white.opacity(0.15))
            }
        }
    }
}

/// Hour labels on the left
private struct HourLabels: View {
    let slots: Int
    let hourHeight: CGFloat
    let formatter: (Int)->String
    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<slots, id: \.self) { slot in
                let hour = slot / 2
                ZStack(alignment: .top) {
                    Rectangle()
                        .fill(.white.opacity(0.15))
                        .frame(height: 1)
                        .frame(width: 0.1)
                        .offset(y: 1)
                    if slot.isMultiple(of: 2) {
                        Text(formatter(hour))
                            .font(.system(size: 12.4, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                            .frame(width: 54, alignment: .trailing)
                            .offset(y: -30)
                    }
                }
                .frame(height: hourHeight/2)
            }
        }
    }
}

/// All task blocks
private struct TaskLayer<Content: View>: View {
    let tasks: [ScheduleTask]
    let now: Date
    let hourHeight: CGFloat
    let content: (ScheduleTask, Date, Bool, Bool) -> Content
    let isPausedByUser: Bool
    var body: some View {
        ForEach(tasks) { task in
            let cal = Calendar.current
            let isCurrent =
                cal.compare(now, to: task.startTime, toGranularity: .minute) != .orderedAscending &&
                cal.compare(now, to: task.endTime,   toGranularity: .minute) == .orderedAscending
            content(task, now, /*debugMode*/ false,
                    isPausedByUser && isCurrent && task.category == .focus)
                .frame(maxWidth: .infinity)
                .frame(height: CGFloat(task.duration/3600)*hourHeight)
                .offset(y: timeToPosition(task.startTime, hourHeight: hourHeight))
                .padding(.vertical, 3)
        }
    }
    private func timeToPosition(_ date: Date, hourHeight: CGFloat) -> CGFloat {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (CGFloat(c.hour ?? 0) + CGFloat(c.minute ?? 0)/60) * hourHeight
    }
} 
