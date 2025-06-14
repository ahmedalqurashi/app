//
//  ContentView.swift
//  SnapFocus
//
//  Created by Ahmed Alqurashi on 31/05/2025.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var timerStore: TimerStore
    let calendar = Calendar.current
    var taskTrails: [UUID: [(start: Date, end: Date, isFocus: Bool)]]
    @State private var showSheet = false
    @State private var timerRunning = false
    @State private var lastWorkBlockId: UUID? = nil
    @State private var timerColor: Color = Color.gray
    @State private var timerPausedColor: Color = Color(red: 0.1, green: 0.4, blue: 1.0) // vivid deep blue
    @State private var timerActiveColor: Color = Color(red: 0.6, green: 0.1, blue: 1.0) // vivid deep purple
    @State private var timerDefaultColor: Color = Color.gray
    @State private var selectedMode: String = "Pomodoro"
    let modes = ["Pomodoro", "Huberman"]
    @Namespace private var statusAnim
    @Environment(\.scenePhase) private var scenePhase
    @State private var lastBlockType: String = "work" // "work" or "break"
    @State private var blockStartTime: Date = Date()
    @State private var showDatePicker: Bool = false
    @State private var previousSessionState: SessionState = .none
    
    private let darkPurple = Color(red: 0.4, green: 0.0, blue: 0.7)
    
    // Block sheet state
    @State private var showBlockSheet = false
    @State private var selectedBlock: ScheduleTask? = nil
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                TodayHeader(
                    statusText: statusText,
                    statusColor: statusColor,
                    workTime: liveWorkTotal,
                    breakTime: liveBreakTotal,
                    activeWork: isWorkTimerActive,
                    activeBreak: isBreakTimerActive,
                    selectedDate: $timerStore.selectedDate,
                    showDatePicker: $showDatePicker
                )
                timelineSection
            }
            .background(Color.black)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        .sheet(isPresented: $showDatePicker) {
            VStack {
                DatePicker(
                    "Select Date",
                    selection: $timerStore.selectedDate,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .colorScheme(.dark)
                .background(Color.black)
                Button("Done") { showDatePicker = false }
                    .padding()
            }
            .padding()
            .background(Color.black)
        }
        .onChange(of: timerStore.sessionState) { _ in timerStore.save() }
        .onChange(of: timerStore.runningBucket) { _ in timerStore.save() }
        .onChange(of: timerStore.bucketStart) { _ in timerStore.save() }
        .onChange(of: timerStore.workTotal) { _ in timerStore.save() }
        .onChange(of: timerStore.breakTotal) { _ in timerStore.save() }
        .onChange(of: timerStore.scheduledTasksByDate) { _ in timerStore.save() }
        .onChange(of: timerStore.selectedDate) { _ in timerStore.save() }
    }
    
    private var timelineSection: some View {
        TimelineView(tasks: timerStore.scheduledTasks, sessionState: timerStore.sessionState, selectedDate: timerStore.selectedDate) { task, now, debug, paused in
            let trail = taskTrails[task.id] ?? []
            TaskBlockView(task: task, hourWidth: 150, now: now, debugMode: debug, isPausedByUser: timerStore.sessionState == .paused, trail: trail)
                .onTapGesture {
                    selectedBlock = task
                    showBlockSheet = true
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showBlockSheet) {
            if let block = selectedBlock {
                BlockInfoSheet(
                    block: block,
                    onDelete: {
                        if let idx = timerStore.scheduledTasks.firstIndex(where: { $0.id == block.id }) {
                            var tasks = timerStore.scheduledTasks
                            tasks.remove(at: idx)
                            timerStore.scheduledTasks = tasks
                        }
                        showBlockSheet = false
                    },
                    onClose: { showBlockSheet = false },
                    scheduledTasks: .constant(timerStore.scheduledTasks)
                )
                .presentationDetents([.fraction(0.45)])
            }
        }
    }
    
    private var statusColor: Color {
        if isWorkTimerActive { Color(red:0.6, green:0.1, blue:1) }
        else if isBreakTimerActive { Color(red:0.1, green:0.4, blue:1) }
        else { .white }
    }
    
    private struct TodayHeader: View {
        let statusText: String
        let statusColor: Color
        let workTime: TimeInterval
        let breakTime: TimeInterval
        let activeWork: Bool
        let activeBreak: Bool
        @Binding var selectedDate: Date
        @Binding var showDatePicker: Bool

        private var formattedDate: String {
            let weekdayFormatter = DateFormatter()
            weekdayFormatter.dateFormat = "EEEE"
            let monthFormatter = DateFormatter()
            monthFormatter.dateFormat = "MMM"
            let dayFormatter = DateFormatter()
            dayFormatter.dateFormat = "d"
            let weekday = weekdayFormatter.string(from: selectedDate)
            let month = monthFormatter.string(from: selectedDate)
            let day = dayFormatter.string(from: selectedDate)
            return "\(weekday), \(month)\(day)"
        }

        var body: some View {
            let workColor = Color(red: 0.6, green: 0.1, blue: 1.0)
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(statusText)
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(statusColor)
                        .transition(.opacity)
                        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: statusText)
                        .id(statusText)
                        .offset(y: -15)

                    Text(formattedDate)
                        .font(.system(size: 12.4, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.top, 8)
                        .onTapGesture { showDatePicker = true }
                }

                Spacer()

                VStack(spacing: 1) {
                    HStack(spacing: 6) {
                        if activeWork {
                            Rectangle()
                                .fill(workColor)
                                .frame(width: 5, height: 22)
                                .cornerRadius(2)
                        }
                        TimerDisplayView(timeValue: workTime, isActive: activeWork, color: workColor, showBullet: false)
                    }
                    HStack(spacing: 6) {
                        if activeBreak {
                            Rectangle()
                                .fill(Color(red: 0.1, green: 0.4, blue: 1.0))
                                .frame(width: 5, height: 22)
                                .cornerRadius(2)
                        }
                        TimerDisplayView(timeValue: breakTime, isActive: activeBreak, color: Color(red: 0.1, green: 0.4, blue: 1.0), showBullet: false)
                    }
                }
                .padding(.top, 2)
                .padding(.trailing, 15)
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 8)
        }
    }
    
    private var isWorkTimerActive: Bool {
        if let currentBlock = activeBlock(at: timerStore.now) {
            return (currentBlock.category == .focus || currentBlock.category == .manualFocus) && timerStore.sessionState == .work
        }
        return false
    }

    private var isBreakTimerActive: Bool {
        timerStore.sessionState == .breakSession
    }

    private var statusText: String {
        if isWorkTimerActive { return "Working" }
        if isBreakTimerActive { return "Resting" }
        return "Ready"
    }
    private var currentDayDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMd"
        return formatter.string(from: Date())
    }

    private var workTimerString: String {
        let total = Int(timerStore.workTotal)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }

    private var breakTimerString: String {
        let total = Int(timerStore.breakTotal)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
    
    // Returns the latest overlapping block (manual focus wins over older blocks)
    private func activeBlock(at date: Date) -> ScheduleTask? {
        timerStore.scheduledTasks
            .filter { ($0.startTime ... $0.endTime).contains(date) }
            .max(by: { $0.startTime < $1.startTime })
    }

    // Computed properties for live totals
    private var liveWorkTotal: TimeInterval {
        var total = timerStore.workTotal
        if timerStore.sessionState == .work, let start = timerStore.bucketStart {
            total += timerStore.now.timeIntervalSince(start)
        }
        return max(0, total)
    }
    private var liveBreakTotal: TimeInterval {
        var total = timerStore.breakTotal
        if timerStore.sessionState == .breakSession, let start = timerStore.bucketStart {
            total += timerStore.now.timeIntervalSince(start)
        }
        return max(0, total)
    }
}

struct MinimalDarkSheet: View {
    @State private var intendedHours: String = ""
    @State private var startHour: String = ""
    @State private var startMinute: String = ""
    @State private var endHour: String = ""
    @State private var endMinute: String = ""
    @State private var startIsPM: Bool = false
    @State private var endIsPM: Bool = false
    @State private var selectedMode: Int = 0 // 0 = Pomodoro, 1 = Huberman
    let modes = ["Pomodoro", "Huberman"]
    var onExecute: (String, Date?, Date?, Int) -> Void
    @Binding var selectedDate: Date
    
    private var startTime: Date? {
        guard let hourRaw = Int(startHour), let minute = Int(startMinute), hourRaw >= 1, hourRaw <= 12, minute < 60 else { return nil }
        let hour = (hourRaw % 12) + (startIsPM ? 12 : 0)
        let now = Date()
        return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: now)
    }
    private var endTime: Date? {
        guard let hourRaw = Int(endHour), let minute = Int(endMinute), hourRaw >= 1, hourRaw <= 12, minute < 60 else { return nil }
        let hour = (hourRaw % 12) + (endIsPM ? 12 : 0)
        let now = Date()
        return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: now)
    }
    var allInputsFilled: Bool {
        !intendedHours.isEmpty && startTime != nil && endTime != nil
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 24) {
                Picker("Mode", selection: $selectedMode) {
                    ForEach(0..<modes.count, id: \.self) { i in
                        Text(modes[i])
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 8)
                .padding(.top, 8)
                .frame(maxWidth: 320)
                if selectedMode == 0 {
                    // Pomodoro UI
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Start Time")
                                .font(.headline)
                                .foregroundColor(.white)
                            Spacer()
                            Picker("AM/PM", selection: $startIsPM) {
                                Text("AM").tag(false)
                                Text("PM").tag(true)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 100)
                        }
                        TimeInputCardView(hour: $startHour, minute: $startMinute, title: "", subtitle: "")
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 20)
                    .background(Color(red: 28/255, green: 28/255, blue: 30/255))
                    .cornerRadius(20)
                    .shadow(color: Color.black.opacity(0.18), radius: 8, x: 0, y: 4)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("End Time")
                                .font(.headline)
                                .foregroundColor(.white)
                            Spacer()
                            Picker("AM/PM", selection: $endIsPM) {
                                Text("AM").tag(false)
                                Text("PM").tag(true)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 100)
                        }
                        TimeInputCardView(hour: $endHour, minute: $endMinute, title: "", subtitle: "")
                            .onChange(of: endHour) { newValue in
                                autoToggleEndIsPM()
                            }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 20)
                    .background(Color(red: 28/255, green: 28/255, blue: 30/255))
                    .cornerRadius(20)
                    .shadow(color: Color.black.opacity(0.18), radius: 8, x: 0, y: 4)
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(!intendedHours.isEmpty ? Color.blue : Color.gray.opacity(0.5))
                                .frame(width: 14, height: 14)
                            Text("Intended Hours")
                                .font(.headline)
                                .foregroundColor(.white)
                        }
                        Text("How many hours do you intend to work?")
                            .font(.subheadline)
                            .foregroundColor(Color(white: 0.7))
                        TextField("Enter hours", text: $intendedHours)
                            .keyboardType(.numberPad)
                            .padding(12)
                            .background(Color(.systemGray5).opacity(0.18))
                            .cornerRadius(12)
                            .foregroundColor(.white)
                            .font(.title2)
                            .multilineTextAlignment(.center)
                    }
                    .padding(20)
                    .background(Color(red: 28/255, green: 28/255, blue: 30/255))
                    .cornerRadius(20)
                    .shadow(color: Color.black.opacity(0.18), radius: 8, x: 0, y: 4)
                    Spacer()
                    Button(action: {
                        onExecute(intendedHours, startTime, endTime, selectedMode)
                    }) {
                        Text("Execute")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(allInputsFilled ? Color.blue : Color.gray.opacity(0.1))
                            .cornerRadius(16)
                            .animation(.easeInOut, value: allInputsFilled)
                    }
                    .padding(.bottom, 32)
                    .padding(.horizontal, 8)
                    .disabled(!allInputsFilled)
                } else if selectedMode == 1 {
                    // Huberman UI (identical for now, but can be customized later)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Start Time")
                                .font(.headline)
                                .foregroundColor(.white)
                            Spacer()
                            Picker("AM/PM", selection: $startIsPM) {
                                Text("AM").tag(false)
                                Text("PM").tag(true)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 100)
                        }
                        TimeInputCardView(hour: $startHour, minute: $startMinute, title: "", subtitle: "")
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 20)
                    .background(Color(red: 28/255, green: 28/255, blue: 30/255))
                    .cornerRadius(20)
                    .shadow(color: Color.black.opacity(0.18), radius: 8, x: 0, y: 4)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("End Time")
                                .font(.headline)
                                .foregroundColor(.white)
                            Spacer()
                            Picker("AM/PM", selection: $endIsPM) {
                                Text("AM").tag(false)
                                Text("PM").tag(true)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 100)
                        }
                        TimeInputCardView(hour: $endHour, minute: $endMinute, title: "", subtitle: "")
                            .onChange(of: endHour) { newValue in
                                autoToggleEndIsPM()
                            }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 20)
                    .background(Color(red: 28/255, green: 28/255, blue: 30/255))
                    .cornerRadius(20)
                    .shadow(color: Color.black.opacity(0.18), radius: 8, x: 0, y: 4)
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(!intendedHours.isEmpty ? Color.blue : Color.gray.opacity(0.5))
                                .frame(width: 14, height: 14)
                            Text("Intended Hours")
                                .font(.headline)
                                .foregroundColor(.white)
                        }
                        Text("How many hours do you intend to work?")
                            .font(.subheadline)
                            .foregroundColor(Color(white: 0.7))
                        TextField("Enter hours", text: $intendedHours)
                            .keyboardType(.numberPad)
                            .padding(12)
                            .background(Color(.systemGray5).opacity(0.18))
                            .cornerRadius(12)
                            .foregroundColor(.white)
                            .font(.title2)
                            .multilineTextAlignment(.center)
                    }
                    .padding(20)
                    .background(Color(red: 28/255, green: 28/255, blue: 30/255))
                    .cornerRadius(20)
                    .shadow(color: Color.black.opacity(0.18), radius: 8, x: 0, y: 4)
                    Spacer()
                    Button(action: {
                        onExecute(intendedHours, startTime, endTime, selectedMode)
                    }) {
                        Text("Execute")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(allInputsFilled ? Color.blue : Color.gray.opacity(0.1))
                            .cornerRadius(16)
                            .animation(.easeInOut, value: allInputsFilled)
                    }
                    .padding(.bottom, 32)
                    .padding(.horizontal, 8)
                    .disabled(!allInputsFilled)
                }
            }
            .padding(.top, 32)
            .padding(.horizontal, 20)
        }
        .onAppear {
            autoFillStartTime()
        }
    }

    private func autoFillStartTime() {
        let now = Date()
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)
        let isPM = hour >= 12
        let hour12 = hour % 12 == 0 ? 12 : hour % 12
        withAnimation {
            startHour = String(format: "%02d", hour12)
            startMinute = String(format: "%02d", minute)
            startIsPM = isPM
        }
    }

    private func autoToggleEndIsPM() {
        guard let startHourInt = Int(startHour), let endHourInt = Int(endHour), !startIsPM else { return }
        // Only auto-toggle if start time is AM
        if endHourInt <= startHourInt && endHourInt != 0 {
            withAnimation {
                endIsPM = true
            }
        } else if endHourInt > startHourInt && endHourInt < 12 {
            withAnimation {
                endIsPM = false
            }
        }
        // If endHourInt is 12 or more, keep PM (user can override)
    }
}

struct StatusCard: View {
    var title: String
    var subtitle: String
    var showInput: Bool = false
    @Binding var inputText: String
    var showTimeSlot: Bool = false
    @Binding var startTime: Date?
    @Binding var endTime: Date?
    
    init(title: String, subtitle: String, showInput: Bool = false, inputText: Binding<String> = .constant(""), showTimeSlot: Bool = false, startTime: Binding<Date?> = .constant(nil), endTime: Binding<Date?> = .constant(nil)) {
        self.title = title
        self.subtitle = subtitle
        self.showInput = showInput
        self._inputText = inputText
        self.showTimeSlot = showTimeSlot
        self._startTime = startTime
        self._endTime = endTime
    }
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.systemGray6).opacity(0.12))
                .shadow(color: Color.black.opacity(0.18), radius: 8, x: 0, y: 4)
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(
                            (showInput && !inputText.isEmpty) ||
                            (showTimeSlot && startTime != nil && endTime != nil)
                            ? Color.blue : Color.gray.opacity(0.5)
                        )
                        .frame(width: 16, height: 16)
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.white)
                    Spacer()
                }
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(Color(white: 0.85))
                if showInput {
                    TextField("Enter hours", text: $inputText)
                        .keyboardType(.numberPad)
                        .padding(12)
                        .background(Color(.systemGray5).opacity(0.18))
                        .cornerRadius(12)
                        .foregroundColor(.white)
                        .font(.title2)
                        .multilineTextAlignment(.center)
                }
                if showTimeSlot {
                    HStack(spacing: 12) {
                        TimePickerField(label: "From", selection: $startTime)
                        TimePickerField(label: "To", selection: $endTime)
                    }
                }
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 200)
    }
}

struct TimePickerField: View {
    var label: String
    @Binding var selection: Date?
    @State private var showPicker = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(Color(white: 0.7))
            Button(action: { showPicker = true }) {
                HStack {
                    Text(selection != nil ? formattedTime(selection!) : "Select")
                        .foregroundColor(.white)
                        .font(.title3)
                    Spacer()
                    Image(systemName: "clock")
                        .foregroundColor(.blue)
                }
                .padding(10)
                .background(Color(.systemGray5).opacity(0.18))
                .cornerRadius(10)
            }
            .sheet(isPresented: $showPicker) {
                VStack {
                    DatePicker(
                        "",
                        selection: Binding(
                            get: { selection ?? defaultTime },
                            set: { selection = $0 }
                        ),
                        displayedComponents: .hourAndMinute
                    )
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .colorScheme(.dark)
                    .background(Color.black)
                    Button("Done") { showPicker = false }
                        .padding()
                }
                .presentationDetents([.fraction(0.3)])
                .background(Color.black)
            }
        }
    }
    private var defaultTime: Date {
        Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
    }
    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mma"
        return formatter.string(from: date)
    }
}

struct TimeInputCardView: View {
    @Binding var hour: String
    @Binding var minute: String
    var title: String = "Time"
    var subtitle: String = "Enter time in 12-hour format"
    
    enum Field: Hashable {
        case hour, minute
    }
    
    @FocusState private var focusedField: Field?
    @State private var hourInputTimer: Timer? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !title.isEmpty {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.white)
            }
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(Color(white: 0.7))
            }
            HStack(spacing: 8) {
                TextField("HH", text: $hour)
                    .keyboardType(.numberPad)
                    .focused($focusedField, equals: .hour)
                    .frame(width: 54, height: 48)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(12)
                    .foregroundColor(.white)
                    .font(.system(size: 28, weight: .medium, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .onChange(of: hour) { newValue in
                        let filtered = newValue.filter { $0.isNumber }
                        if filtered.count > 2 {
                            hour = String(filtered.prefix(2))
                        } else {
                            hour = filtered
                        }
                        hourInputTimer?.invalidate()
                        if hour.count == 1 {
                            if let first = hour.first, first == "1" {
                                // Wait for possible 10, 11, 12
                                hourInputTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { _ in
                                    focusedField = .minute
                                }
                            } else if let first = hour.first, ("2"..."9").contains(first) {
                                focusedField = .minute
                            }
                        } else if hour.count == 2 {
                            // If user enters 10, 11, 12
                            focusedField = .minute
                        }
                    }
                Text(":")
                    .font(.system(size: 28, weight: .medium, design: .monospaced))
                    .foregroundColor(.white)
                TextField("MM", text: $minute)
                    .keyboardType(.numberPad)
                    .focused($focusedField, equals: .minute)
                    .frame(width: 54, height: 48)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(12)
                    .foregroundColor(.white)
                    .font(.system(size: 28, weight: .medium, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .onChange(of: minute) { newValue in
                        let filtered = newValue.filter { $0.isNumber }
                        if filtered.count > 2 {
                            minute = String(filtered.prefix(2))
                        } else {
                            minute = filtered
                        }
                    }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 20)
        .background(Color(red: 28/255, green: 28/255, blue: 30/255))
        .cornerRadius(20)
        .shadow(color: Color.black.opacity(0.18), radius: 8, x: 0, y: 4)
        .onDisappear {
            hourInputTimer?.invalidate()
        }
    }
}

struct TimeInputCardView_Previews: PreviewProvider {
    @State static var hour = ""
    @State static var minute = ""
    static var previews: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            TimeInputCardView(hour: $hour, minute: $minute)
                .padding()
        }
        .preferredColorScheme(.dark)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(taskTrails: [:])
    }
}

struct TimerDisplayView: View {
    let timeValue: TimeInterval
    let isActive: Bool
    let color: Color
    var showBullet: Bool = true
    var body: some View {
        let total = Int(timeValue)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        let timeString: String = hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, seconds) : String(format: "%02d:%02d", minutes, seconds)
        HStack(spacing: 8) {
            if showBullet && isActive {
                GeometryReader { geo in
                    Circle()
                        .fill(color)
                        .frame(width: geo.size.height / 2, height: geo.size.height / 2)
                        .position(x: geo.size.height / 4, y: geo.size.height / 2)
                }
                .frame(width: 16, height: 22) // Adjust as needed
            }
            Text(timeString)
                .font(.system(size: 22, weight: .bold, design: .monospaced))
                .foregroundColor(isActive ? color : Color.gray)
                .shadow(color: isActive ? color.opacity(0.7) : .clear, radius: 6, x: 0, y: 0)
                .frame(width: hours > 0 ? 100 : 74, alignment: .trailing)
                .padding(.vertical, 4)
        }
    }
}

struct BlockInfoSheet: View {
    @State private var editedLabel: String
    let block: ScheduleTask
    let onDelete: () -> Void
    let onClose: () -> Void
    @Binding var scheduledTasks: [ScheduleTask]
    
    init(block: ScheduleTask, onDelete: @escaping () -> Void, onClose: @escaping () -> Void, scheduledTasks: Binding<[ScheduleTask]>) {
        self.block = block
        self.onDelete = onDelete
        self.onClose = onClose
        self._scheduledTasks = scheduledTasks
        self._editedLabel = State(initialValue: block.label)
    }
    var body: some View {
        VStack(spacing: 24) {
            HStack {
                Text("Block Details")
                    .font(.title2).bold()
                    .foregroundColor(.white)
                Spacer()
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                        .font(.title2)
                        .padding(8)
                        .background(Color(.systemGray6).opacity(0.18))
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "calendar")
                        .foregroundColor(.blue)
                    Text("Date: ")
                        .foregroundColor(.gray)
                    Text(formattedDate(block.startTime))
                        .foregroundColor(.white)
                }
                HStack {
                    Image(systemName: "clock")
                        .foregroundColor(.purple)
                    Text("Time: ")
                        .foregroundColor(.gray)
                    Text("\(formattedTime(block.startTime)) - \(formattedTime(block.endTime))")
                        .foregroundColor(.white)
                }
                HStack(alignment: .top) {
                    Image(systemName: "pencil")
                        .foregroundColor(.green)
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("What to do:")
                            .foregroundColor(.gray)
                        TextField("Label", text: $editedLabel, onCommit: saveLabel)
                            .foregroundColor(.white)
                            .font(.body)
                            .padding(10)
                            .background(Color(.systemGray6).opacity(0.18))
                            .cornerRadius(10)
                            .onSubmit { saveLabel() }
                    }
                }
            }
            .font(.body)
            .padding(.horizontal)
            Spacer()
            Button(action: {
                saveLabel()
                onClose()
            }) {
                Text("Close")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(16)
            }
            .padding(.horizontal)
            .padding(.bottom, 12)
        }
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.black.opacity(0.92))
                .shadow(color: Color.black.opacity(0.18), radius: 16, x: 0, y: 8)
        )
        .padding(.horizontal, 8)
        .padding(.top, 8)
    }
    func formattedDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f.string(from: date)
    }
    func formattedTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeStyle = .short
        return f.string(from: date)
    }
    func saveLabel() {
        if let idx = scheduledTasks.firstIndex(where: { $0.id == block.id }) {
            var updated = scheduledTasks[idx]
            updated = ScheduleTask(id: updated.id, name: updated.name, label: editedLabel, startTime: updated.startTime, duration: updated.duration, category: updated.category)
            scheduledTasks[idx] = updated
        }
    }
}
