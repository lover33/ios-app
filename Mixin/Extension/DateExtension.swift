import UIKit
import CoreMedia

extension DateFormatter {

    static let dayDate = DateFormatter(dateFormat: Localized.DATE_FORMAT_DAY)
    static let weekDate = DateFormatter(dateFormat: "EEEE")
    static let month = DateFormatter(dateFormat: Localized.DATE_FORMAT_MONTH)
    static let date = DateFormatter(dateFormat: "MMM d, yyyy")
    static let dateSimple = DateFormatter(dateFormat: Localized.DATE_FORMAT_DATE)
    static let dateFull = DateFormatter(dateFormat: "yyyy-MM-dd HH:mm:ss")
    static let yyyymmdd = DateFormatter(dateFormat: "yyyyMMdd")
    static let MMMddHHmm = DateFormatter(dateFormat: Localized.DATE_FORMAT_TRANSATION)
    static let filename = DateFormatter(dateFormat: "yyyy-MM-dd_HH:mm:ss")
    
    convenience init(dateFormat: String) {
        self.init()
        self.dateFormat = dateFormat
        self.locale = Locale.current
        self.timeZone = TimeZone.current
    }

    static let iso8601Full: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ"
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.timeZone = TimeZone(abbreviation: "UTC")
        return formatter
    }()

    static let localFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone.current
        return formatter
    }()
}

func currentTimeInMiliseconds() -> UInt64 {
    let currentDate = Date()
    let since1970 = currentDate.timeIntervalSince1970
    return UInt64(since1970 * 1000)
}

extension Date {

    private static let sourceTimeZone = TimeZone(identifier: "UTC")!
    private static let destinationTimeZone = NSTimeZone.local

    func toUTCString() -> String {
        return DateFormatter.iso8601Full.string(from: self)
    }

    func toLocalDate() -> Date {
        let destinationGMTOffset = Date.destinationTimeZone.secondsFromGMT(for: self)
        let sourceGMTOffset = Date.sourceTimeZone.secondsFromGMT(for: self)
        return Date(timeInterval: TimeInterval(destinationGMTOffset - sourceGMTOffset), since: self)
    }

    func nanosecond() -> Int64 {
        let nanosecond: Int64 = Int64(Calendar.current.dateComponents([.nanosecond], from: self).nanosecond ?? 0)
        return Int64(self.timeIntervalSince1970 * 1000000000) + nanosecond
    }

    func timeAgo() -> String {
        let now = Date()
        let nowDateComponents = Calendar.current.dateComponents([.day], from: now)
        let dateComponents = Calendar.current.dateComponents([.day], from: self)
        let days = Date().timeIntervalSince(self) / 86400
        if days < 1 && nowDateComponents.day == dateComponents.day {
            return DateFormatter.dayDate.string(from: self)
        } else if days < 7 {
            return DateFormatter.weekDate.string(from: self).capitalized
        } else {
            return DateFormatter.dateSimple.string(from: self)
        }
    }

    func timeHoursAndMinutes() -> String {
        return DateFormatter.dayDate.string(from: self)
    }

    func timeDayAgo() -> String {
        let now = Date()
        let nowDateComponents = Calendar.current.dateComponents([.day, .year, .weekOfYear], from: now)
        let dateComponents = Calendar.current.dateComponents([.day, .year, .weekOfYear], from: self)

        if nowDateComponents.day == dateComponents.day {
            return Localized.CHAT_TIME_TODAY
        } else {
            if nowDateComponents.year == dateComponents.year && nowDateComponents.weekOfYear == dateComponents.weekOfYear {
                return DateFormatter.weekDate.string(from: self)
            } else if nowDateComponents.year == dateComponents.year {
                return DateFormatter.month.string(from: self)
            } else {
                return DateFormatter.date.string(from: self)
            }
        }
    }
}

let mediaDurationFormatter: DateComponentsFormatter = {
    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = [.minute, .second]
    formatter.zeroFormattingBehavior = [.pad]
    formatter.unitsStyle = .positional
    return formatter
}()

let millisecondsPerSecond: Double = 1000
let nanosecondsPerSecond: CMTimeScale = 1000000000
