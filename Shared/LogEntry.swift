import Foundation

/// A timestamp-first entry. nil means that a detail has not been recorded.
/// For symptoms, nil means unknown and [] means explicitly no symptoms.
struct LogEntry: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var occurredAt: Date
    var createdAt: Date
    var updatedAt: Date
    var bristol: Int?
    var color: String?
    var amount: String?
    var effort: String?
    var symptoms: [String]?
    var durationMinutes: Int?
    var note: String?
    var deletedAt: Date?

    init(
        id: UUID = UUID(),
        occurredAt: Date = Date(),
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        bristol: Int? = nil,
        color: String? = nil,
        amount: String? = nil,
        effort: String? = nil,
        symptoms: [String]? = nil,
        durationMinutes: Int? = nil,
        note: String? = nil,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.occurredAt = DiaryDate.canonical(occurredAt)
        self.createdAt = DiaryDate.canonical(createdAt)
        self.updatedAt = DiaryDate.canonical(updatedAt)
        self.bristol = bristol
        self.color = color
        self.amount = amount
        self.effort = effort
        self.symptoms = symptoms
        self.durationMinutes = durationMinutes
        self.note = note
        self.deletedAt = deletedAt.map(DiaryDate.canonical)
    }

    var isDeleted: Bool { deletedAt != nil }

    /// Dates are canonicalized at the persistence boundary, including edited dates.
    func canonicalized() -> LogEntry {
        var value = self
        value.occurredAt = DiaryDate.canonical(occurredAt)
        value.createdAt = DiaryDate.canonical(createdAt)
        value.updatedAt = DiaryDate.canonical(updatedAt)
        value.deletedAt = deletedAt.map(DiaryDate.canonical)
        return value
    }

    func validate() throws {
        let dates = [occurredAt, createdAt, updatedAt] + (deletedAt.map { [$0] } ?? [])
        // Bound untrusted imports to representable ISO years 1970 ... 9999.
        guard dates.allSatisfy({
            let value = $0.timeIntervalSince1970
            return value.isFinite && value >= 0 && value <= 253_402_300_799.999
        }) else { throw DiaryStoreError.invalidEntry("Entry timestamps must be finite dates between 1970 and 9999.") }
        guard updatedAt >= createdAt else {
            throw DiaryStoreError.invalidEntry("An update cannot predate the entry's creation.")
        }
        if let deletedAt, deletedAt < createdAt || deletedAt > updatedAt {
            throw DiaryStoreError.invalidEntry("The deletion timestamp must fall between creation and the latest update.")
        }
        if let bristol, !(1...7).contains(bristol) {
            throw DiaryStoreError.invalidEntry("Bristol type must be between 1 and 7.")
        }
        if let durationMinutes, !(0...1_440).contains(durationMinutes) {
            throw DiaryStoreError.invalidEntry("Duration must be between 0 and 1,440 minutes.")
        }
        for (name, value, limit) in [
            ("Color", color, 80), ("Amount", amount, 80),
            ("Effort", effort, 80), ("Note", note, 10_000)
        ] {
            if let value, value.count > limit || value.contains("\0") {
                throw DiaryStoreError.invalidEntry("\(name) is too long or contains an unsupported null character.")
            }
        }
        if let symptoms {
            guard symptoms.count <= 30,
                  Set(symptoms).count == symptoms.count,
                  symptoms.allSatisfy({ !$0.isEmpty && $0.count <= 80 && !$0.contains("\0") }) else {
                throw DiaryStoreError.invalidEntry("Symptoms must be unique, nonempty labels of up to 80 characters (at most 30).")
            }
        }
    }
}

/// A user's explicit observation about a Gregorian civil day, never a bowel
/// movement. The timezone is captured when confirmed and never follows travel
/// or the device's later timezone. For today this means "as of updatedAt", not
/// a prediction for the rest of today. cancelledAt is a retained tombstone: backup
/// merge must not resurrect an older confirmation. Reconfirming is explicit.
struct DayStatus: Identifiable, Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case noBowelMovement }

    var id: UUID
    var kind: Kind
    var localDate: String
    var timeZoneIdentifier: String
    var createdAt: Date
    var updatedAt: Date
    var cancelledAt: Date?

    init(id: UUID = UUID(), kind: Kind = .noBowelMovement,
         localDate: String, timeZoneIdentifier: String,
         createdAt: Date = Date(), updatedAt: Date = Date(), cancelledAt: Date? = nil) {
        self.id = id
        self.kind = kind
        self.localDate = localDate
        self.timeZoneIdentifier = timeZoneIdentifier
        self.createdAt = DiaryDate.canonical(createdAt)
        self.updatedAt = DiaryDate.canonical(updatedAt)
        self.cancelledAt = cancelledAt.map(DiaryDate.canonical)
    }

    var isCancelled: Bool { cancelledAt != nil }
    /// Stable uniqueness within the timezone in which the observation was made.
    var dayKey: String { timeZoneIdentifier + "|" + localDate }

    /// Only matches a calendar column using the observation's original zone.
    /// Travel must not silently relabel another timezone's incomplete day.
    func matches(date: Date, calendar: Calendar = .current) -> Bool {
        timeZoneIdentifier == calendar.timeZone.identifier &&
        (try? Self.civilDate(on: date, calendar: calendar)) == localDate
    }

    static func civilDate(on date: Date, calendar: Calendar = .current) throws -> String {
        guard date.timeIntervalSince1970.isFinite else {
            throw DiaryStoreError.invalidEntry("The selected local day could not be determined.")
        }
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        let parts = gregorian.dateComponents([.era, .year, .month, .day], from: date)
        guard parts.era == 1, let year = parts.year, (1970...9999).contains(year),
              let month = parts.month, let day = parts.day else {
            throw DiaryStoreError.invalidEntry("The selected day must be between 1970 and 9999.")
        }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// Half-open interval with the saved timezone's actual DST boundaries.
    /// A nonexistent civil day (for example a date skipped by a timezone change)
    /// is rejected rather than normalized to a different date.
    func dayInterval() throws -> DateInterval {
        guard localDate.utf8.count == 10,
              localDate.utf8.enumerated().allSatisfy({ index, byte in
                  (index == 4 || index == 7) ? byte == 45 : (48...57).contains(byte)
              }), timeZoneIdentifier.count <= 100,
              let zone = TimeZone(identifier: timeZoneIdentifier) else {
            throw DiaryStoreError.invalidEntry("A day status requires YYYY-MM-DD and a valid timezone identifier.")
        }
        let parts = localDate.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1970...9999).contains(parts[0]) else {
            throw DiaryStoreError.invalidEntry("The confirmed local date is invalid.")
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        guard let noon = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)),
              try Self.civilDate(on: noon, calendar: calendar) == localDate,
              let interval = calendar.dateInterval(of: .day, for: noon) else {
            throw DiaryStoreError.invalidEntry("The confirmed local date does not exist in this timezone.")
        }
        return interval
    }

    func validate() throws {
        _ = try dayInterval()
        let dates = [createdAt, updatedAt] + (cancelledAt.map { [$0] } ?? [])
        guard dates.allSatisfy({ $0.timeIntervalSince1970.isFinite && $0.timeIntervalSince1970 >= 0 && $0.timeIntervalSince1970 <= 253_402_300_799.999 }),
              updatedAt >= createdAt else {
            throw DiaryStoreError.invalidEntry("Day-status timestamps must be valid and the update must not predate creation.")
        }
        if let cancelledAt, cancelledAt < createdAt || cancelledAt > updatedAt {
            throw DiaryStoreError.invalidEntry("The cancellation must fall between creation and the latest update.")
        }
    }
}

/// Missing logs are unknown, never inferred constipation or confirmed no-BM.
enum DiaryDayState: String, Codable, Sendable {
    case unknown
    case confirmedNoBowelMovement
    case recordedBowelMovement
}

/// Stored instants have millisecond precision. Backups and CSV use UTC with a Z
/// suffix. Imports accept ISO 8601 timestamps with Z or an explicit UTC offset;
/// local display and day grouping must use the viewer's Calendar/TimeZone.
enum DiaryDate {
    // One cached codec per process. Its lock protects every formatter/regex
    // call across independent stores, widget intents, and concurrent tests.
    private static let codec = CachedDateCodec()

    static func canonical(_ value: Date) -> Date {
        guard value.timeIntervalSince1970.isFinite else { return value }
        return Date(timeIntervalSince1970: (value.timeIntervalSince1970 * 1_000).rounded() / 1_000)
    }

    static func string(_ value: Date) -> String {
        codec.string(canonical(value))
    }

    static func parse(_ value: String) -> Date? {
        codec.parse(value).map(canonical)
    }

    /// Next local-day boundary, strictly after date. Uses Calendar rather than
    /// adding 86,400 seconds, so spring/fall DST days and skipped midnight work.
    static func nextMidnight(after date: Date = Date(), calendar: Calendar = .current) -> Date? {
        guard date.timeIntervalSince1970.isFinite,
              let day = calendar.dateInterval(of: .day, for: date),
              day.end > date else { return nil }
        return day.end
    }

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(string(date))
        }
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            guard let date = parse(value) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected an ISO 8601 timestamp with a timezone.")
            }
            return date
        }
        return decoder
    }
}

/// ISO8601DateFormatter has mutable configuration. All three cached instances
/// remain private and are only accessed while holding lock; no formatter
/// configuration changes after initialization. JSON coders are not shared.
private final class CachedDateCodec: @unchecked Sendable {
    private let lock = NSLock()
    private let encoder: ISO8601DateFormatter
    private let fractionalParser: ISO8601DateFormatter
    private let wholeSecondParser: ISO8601DateFormatter
    private let timestampPattern: NSRegularExpression?

    init() {
        let output = ISO8601DateFormatter()
        output.timeZone = TimeZone(secondsFromGMT: 0)
        output.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fractional = ISO8601DateFormatter()
        fractional.timeZone = TimeZone(secondsFromGMT: 0)
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let wholeSecond = ISO8601DateFormatter()
        wholeSecond.timeZone = TimeZone(secondsFromGMT: 0)
        wholeSecond.formatOptions = [.withInternetDateTime]
        let pattern = #"\A\d{4}-(?:0[1-9]|1[0-2])-(?:0[1-9]|[12]\d|3[01])T(?:[01]\d|2[0-3]):[0-5]\d:[0-5]\d(?:\.\d{1,9})?(?:Z|[+-](?:[01]\d|2[0-3]):[0-5]\d)\z"#
        encoder = output
        fractionalParser = fractional
        wholeSecondParser = wholeSecond
        timestampPattern = try? NSRegularExpression(pattern: pattern)
    }

    func string(_ value: Date) -> String {
        lock.lock()
        defer { lock.unlock() }
        return encoder.string(from: value)
    }

    func parse(_ value: String) -> Date? {
        guard value.count <= 40 else { return nil }
        lock.lock()
        defer { lock.unlock() }
        // Requiring an explicit timezone prevents a local wall time silently
        // becoming UTC. Full-string matching also rejects trailing content.
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        guard timestampPattern?.firstMatch(in: value, range: range) != nil else { return nil }
        let components = value.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard components.count == 3 else { return nil }
        let year = components[0], month = components[1], day = components[2]
        let leapYear = year % 400 == 0 || (year % 4 == 0 && year % 100 != 0)
        let maximumDay: Int
        switch month {
        case 2: maximumDay = leapYear ? 29 : 28
        case 4, 6, 9, 11: maximumDay = 30
        default: maximumDay = 31
        }
        guard year >= 1, day <= maximumDay else { return nil }
        // The validated grammar locates the only possible dot after seconds.
        // Selecting a dedicated formatter avoids a failed parse followed by
        // mutating formatter options for every whole-second timestamp.
        return value.contains(".")
            ? fractionalParser.date(from: value)
            : wholeSecondParser.date(from: value)
    }
}
