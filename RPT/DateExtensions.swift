import Foundation

extension Date {
    /// Returns the start of the day for this date
    func startOfDay() -> Date {
        return Calendar.current.startOfDay(for: self)
    }
    
    /// Returns the end of the day for this date
    func endOfDay() -> Date {
        return Calendar.current.date(byAdding: DateComponents(day: 1, second: -1), to: startOfDay())!
    }
}