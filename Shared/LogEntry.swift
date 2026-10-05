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

/// Stored instants have millisecond precision. Backups and CSV use UTC with a Z
/// suffix. Imports accept ISO 8601 timestamps with Z or an explicit UTC offset;
/// local display and day grouping must use the viewer's Calendar/TimeZone.
enum DiaryDate {
    static func canonical(_ value: Date) -> Date {
        guard value.timeIntervalSince1970.isFinite else { return value }
        return Date(timeIntervalSince1970: (value.timeIntervalSince1970 * 1_000).rounded() / 1_000)
    }

    static func string(_ value: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: canonical(value))
    }

    static func parse(_ value: String) -> Date? {
        // Requiring a timezone prevents silently treating a local wall time as UTC.
        // Check the whole input, since Foundation can otherwise normalize an
        // impossible date (for example February 30) instead of rejecting it.
        let pattern = #"\A\d{4}-(?:0[1-9]|1[0-2])-(?:0[1-9]|[12]\d|3[01])T(?:[01]\d|2[0-3]):[0-5]\d:[0-5]\d(?:\.\d{1,9})?(?:Z|[+-](?:[01]\d|2[0-3]):[0-5]\d)\z"#
        guard value.count <= 40, value.range(of: pattern, options: .regularExpression) != nil else { return nil }
        let components = value.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard components.count == 3 else { return nil }
        let year = components[0], month = components[1], day = components[2]
        let leapYear = year % 400 == 0 || (year % 4 == 0 && year % 100 != 0)
        let monthDays = [31, leapYear ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        guard year >= 1, day <= monthDays[month - 1] else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return canonical(date) }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value).map(canonical)
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
