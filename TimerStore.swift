import Foundation
import SwiftUI
import Combine

struct TimerSnapshot: Codable {
    var sessionState: SessionState
    var runningBucket: SessionState
    var bucketStart: Date?
    var workTotal: TimeInterval
    var breakTotal: TimeInterval
    var scheduledTasks: [ScheduleTask]
    var selectedDate: Date
}

// MARK: - TimeTrace model
struct TimeTrace: Identifiable, Codable {
    let id       = UUID()
    let start    : Date
    let end      : Date
    let isFocus  : Bool      // true = work, false = break
}

@MainActor
final class TimerStore: ObservableObject {
    @Published var sessionState: SessionState = .none
    @Published var runningBucket: SessionState = .none
    @Published var bucketStart: Date? = nil
    @Published var workTotal: TimeInterval = 0
    @Published var breakTotal: TimeInterval = 0
    @Published var scheduledTasksByDate: [Date:[ScheduleTask]] = [:]
    @Published var selectedDate: Date = Date()
    @Published var now: Date = Date()
    @Published var traces: [TimeTrace] = []

    private let key = "timerState"
    private let traceKey = "savedTimeTraces"
    private var heartbeat: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()

    init() {
        restore()
        if let data = UserDefaults.standard.data(forKey: traceKey),
           let saved = try? JSONDecoder().decode([TimeTrace].self, from: data) {
            traces = saved
        }
        heartbeat = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] date in self?.now = date }
        // Save whenever the app is about to vanish
        let willHide = [
            UIApplication.willResignActiveNotification,
            UIApplication.didEnterBackgroundNotification
        ]
        willHide.forEach { n in
            NotificationCenter.default.publisher(for: n)
                .sink { [weak self] _ in self?.save() }
                .store(in: &cancellables)
        }
        NotificationCenter.default.publisher(for: UIApplication.willTerminateNotification)
            .sink { [weak self] _ in
                Task {
                    await self?.closeCurrentTrace()
                    self?.save()
                }
            }
            .store(in: &cancellables)
    }

    func save() {
        let snap = TimerSnapshot(sessionState: sessionState,
                                 runningBucket: runningBucket,
                                 bucketStart: bucketStart,
                                 workTotal: workTotal,
                                 breakTotal: breakTotal,
                                 scheduledTasks: scheduledTasks,
                                 selectedDate: selectedDate)
        if let data = try? JSONEncoder().encode(snap) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func restore() {
        guard
            let data = UserDefaults.standard.data(forKey: key),
            let snap = try? JSONDecoder().decode(TimerSnapshot.self, from: data)
        else { return }
        apply(snap)
        // Only set runningBucket and bucketStart, do not mutate workTotal or breakTotal
        if let start = bucketStart {
            let now = Date()
            if now < start {
                bucketStart = now
            }
            runningBucket = sessionState // .work or .breakSession
            // Do NOT mutate workTotal/breakTotal here
        }
    }

    var scheduledTasks: [ScheduleTask] {
        get { scheduledTasksByDate[Calendar.current.startOfDay(for:selectedDate)] ?? [] }
        set { scheduledTasksByDate[Calendar.current.startOfDay(for:selectedDate)] = newValue }
    }

    func apply(_ snap: TimerSnapshot) {
        sessionState    = snap.sessionState
        runningBucket   = snap.runningBucket
        bucketStart     = snap.bucketStart
        workTotal       = snap.workTotal
        breakTotal      = snap.breakTotal
        selectedDate    = snap.selectedDate
        scheduledTasksByDate = [Calendar.current.startOfDay(for:snap.selectedDate): snap.scheduledTasks]
    }

    func normalizedDate(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    @MainActor
    func applyPomodoroSessions(startTime: Date,
                              endTime: Date,
                              totalWorkDuration: TimeInterval)
    {
        var tasks = scheduledTasks
        tasks.removeAll { $0.name.hasPrefix("Pomodoro") }

        let focus  : TimeInterval = 25*60
        let shortB : TimeInterval =  5*60
        let longB  : TimeInterval = 30*60
        let cycle  = 4

        var current = startTime
        var done    : TimeInterval = 0

        while done < totalWorkDuration && current < endTime {
            for i in 0..<cycle where done < totalWorkDuration && current < endTime {
                // focus
                let end = min(current.addingTimeInterval(focus), endTime)
                tasks.append(ScheduleTask(name:"Pomodoro Focus",
                                          label:"Pomodoro Focus Block",
                                          startTime: current,
                                          duration: end.timeIntervalSince(current),
                                          category:.focus))
                done   += end.timeIntervalSince(current)
                current = end
                guard done < totalWorkDuration && current < endTime else { break }
                // short break except after last focus
                if i < cycle-1 {
                    let bEnd = min(current.addingTimeInterval(shortB), endTime)
                    tasks.append(ScheduleTask(name:"Pomodoro Break",
                                              label:"Pomodoro Break Block",
                                              startTime: current,
                                              duration: bEnd.timeIntervalSince(current),
                                              category:.freeTime))
                    current = bEnd
                }
            }
            // long break
            if done < totalWorkDuration && current < endTime {
                let bEnd = min(current.addingTimeInterval(longB), endTime)
                tasks.append(ScheduleTask(name:"Pomodoro Long Break",
                                          label:"Pomodoro Long Break Block",
                                          startTime: current,
                                          duration: bEnd.timeIntervalSince(current),
                                          category:.freeTime))
                current = bEnd
            }
        }
        scheduledTasks = tasks
    }

    @MainActor
    func applyHubermanSessions(startTime: Date,
                              endTime: Date,
                              totalWorkDuration: TimeInterval)
    {
        var tasks = scheduledTasks
        tasks.removeAll { $0.name.hasPrefix("Huberman") }

        let focus : TimeInterval = 90*60
        let brk   : TimeInterval = 15*60

        var current = startTime
        var done    : TimeInterval = 0

        while done < totalWorkDuration && current < endTime {
            let fEnd = min(current.addingTimeInterval(focus), endTime)
            tasks.append(ScheduleTask(name:"Huberman Focus",
                                      label:"Huberman Focus Block",
                                      startTime: current,
                                      duration: fEnd.timeIntervalSince(current),
                                      category:.focus))
            done   += fEnd.timeIntervalSince(current)
            current = fEnd
            guard done < totalWorkDuration && current < endTime else { break }
            let bEnd = min(current.addingTimeInterval(brk), endTime)
            tasks.append(ScheduleTask(name:"Huberman Break",
                                      label:"Huberman Break Block",
                                      startTime: current,
                                      duration: bEnd.timeIntervalSince(current),
                                      category:.freeTime))
            current = bEnd
        }
        scheduledTasks = tasks
    }

    @MainActor
    func closeCurrentTrace(at date: Date = Date()) {
        guard let start = bucketStart else { return }
        let elapsed = date.timeIntervalSince(start)
        if sessionState == .work         { workTotal  += elapsed }
        else if sessionState == .breakSession { breakTotal += elapsed }
        traces.append(
            TimeTrace(start: start,
                      end:   date,
                      isFocus: sessionState == .work)
        )
        bucketStart   = nil
        runningBucket = .none
        saveTraces()
    }

    func hardResetTimers() {
        workTotal     = 0
        breakTotal    = 0
        bucketStart   = nil
        runningBucket = .none
        sessionState  = .none
        save()
    }

    func transition(to newState: SessionState) {
        if sessionState == .work || sessionState == .breakSession {
            closeCurrentTrace()
        }
        sessionState  = newState
        bucketStart   = (newState == .work || newState == .breakSession) ? Date() : nil
    }

    func saveTraces() {
        if let data = try? JSONEncoder().encode(traces) {
            UserDefaults.standard.set(data, forKey: traceKey)
        }
    }
} 