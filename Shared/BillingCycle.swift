import Foundation

enum BillingCycle {
    /// Manual billing periods start at local midnight. A requested day such as
    /// the 31st is clamped independently in every month (Feb 28 -> Mar 31), so a
    /// short month never permanently moves the user's chosen billing day.
    static func dates(
        startDay: Int,
        now: Date,
        calendar: Calendar = .current
    ) -> (start: Date, end: Date) {
        let requestedDay = min(31, max(1, startDay))
        let monthStart = calendar.dateInterval(of: .month, for: now)?.start
            ?? calendar.startOfDay(for: now)

        func boundary(in month: Date) -> Date {
            let first = calendar.dateInterval(of: .month, for: month)?.start ?? month
            let dayCount = calendar.range(of: .day, in: .month, for: first)?.count ?? 28
            return calendar.date(byAdding: .day, value: min(requestedDay, dayCount) - 1, to: first) ?? first
        }

        let currentBoundary = boundary(in: monthStart)
        if now >= currentBoundary {
            let nextMonth = calendar.date(byAdding: .month, value: 1, to: monthStart)
                ?? calendar.dateInterval(of: .month, for: monthStart)?.end ?? monthStart
            return (currentBoundary, boundary(in: nextMonth))
        }
        let previousMonth = calendar.date(byAdding: .month, value: -1, to: monthStart) ?? monthStart
        return (boundary(in: previousMonth), currentBoundary)
    }
}
