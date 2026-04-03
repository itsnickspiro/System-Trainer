import Foundation
import SwiftData

// MARK: - SwiftData Helpers

extension ModelContext {
    /// Save with error logging instead of silent try? suppression.
    func safeSave(file: String = #file, line: Int = #line) {
        do {
            try save()
        } catch {
            print("[SwiftData] Save failed at \((file as NSString).lastPathComponent):\(line): \(error)")
        }
    }
}

extension Date {
    /// Returns the start of the day for this date
    func startOfDay() -> Date {
        return Calendar.current.startOfDay(for: self)
    }
    
    /// Returns the end of the day for this date
    func endOfDay() -> Date {
        return Calendar.current.date(byAdding: DateComponents(day: 1, second: -1), to: startOfDay()) ?? self
    }
}

extension Calendar {
    /// True when `date` is strictly after today (start-of-day comparison).
    func isDateInFuture(_ date: Date) -> Bool {
        let todayStart = startOfDay(for: Date())
        let dateStart  = startOfDay(for: date)
        return dateStart > todayStart
    }
}