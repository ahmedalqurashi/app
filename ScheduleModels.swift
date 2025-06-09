import SwiftUI

public struct ScheduleTask: Identifiable, Equatable {
    public let id: UUID
    public let name: String
    public let startTime: Date
    public let duration: TimeInterval
    public let category: TaskCategory
    
    public var endTime: Date {
        return startTime.addingTimeInterval(duration)
    }
    
    public init(id: UUID = UUID(), name: String, startTime: Date, duration: TimeInterval, category: TaskCategory) {
        self.id = id
        self.name = name
        self.startTime = startTime
        self.duration = duration
        self.category = category
    }
    
    public static func == (lhs: ScheduleTask, rhs: ScheduleTask) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.startTime == rhs.startTime && lhs.duration == rhs.duration && lhs.category == rhs.category
    }
}

public enum TaskCategory: String, CaseIterable {
    case focus = "Focus"
    case admin = "Admin"
    case freeTime = "Free Time"
    case manualFocus = "Manual Focus"
    
    public var color: Color {
        switch self {
        case .focus: return Color.blue.opacity(0.7)
        case .admin: return Color.purple.opacity(0.7)
        case .freeTime: return Color.green.opacity(0.7)
        case .manualFocus: return Color.purple
        }
    }
} 
