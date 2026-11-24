import Foundation

enum Launch {
    static let freePeriod = false
    static func isFree(arguments: [String]) -> Bool {
        freePeriod && !arguments.contains(where: { ["-paid-mode", "-paywall", "-expired"].contains($0) })
    }
    static var isFree: Bool { isFree(arguments: ProcessInfo.processInfo.arguments) }
    static func has(_ flag: String, in args: [String] = ProcessInfo.processInfo.arguments) -> Bool { args.contains(flag) }
    static func value(_ flag: String, in args: [String] = ProcessInfo.processInfo.arguments) -> String? {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
}

struct Room: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
}

enum Reaction: String, Codable, CaseIterable, Identifiable {
    case loved, okay, ignored
    var id: String { rawValue }
    var key: String { "reaction.\(rawValue)" }
}

struct Outing: Codable, Equatable {
    var start: Date
    var end: Date?
    var reaction: Reaction?
}

struct Bin: Codable, Identifiable, Equatable {
    var id = UUID()
    var roomID: UUID
    var number: Int
    var name = ""
    var photo: String?
    var note = ""
    var outings: [Outing] = []
    var created = Date()

    var isOut: Bool { outings.last.map { $0.end == nil } ?? false }
    var outSince: Date? { isOut ? outings.last?.start : nil }
    var lastBack: Date? { outings.last(where: { $0.end != nil })?.end }
    var finishedOutings: [Outing] { outings.filter { $0.end != nil } }

    var lovedCount: Int { outings.filter { $0.reaction == .loved }.count }
    var lovedRate: Double? {
        let rated = outings.filter { $0.reaction != nil }
        return rated.isEmpty ? nil : Double(lovedCount) / Double(rated.count)
    }
}

struct ToySettings: Codable, Equatable {
    var cycleDays = 7
    var outCount = 1
    var remind = true
    var reminderHour = 9
    var reminderMinute = 0

    static let cycleChoices = [3, 5, 7, 10, 14]
    static let outChoices = [1, 2, 3]
}

struct Milestones: Codable, Equatable {
    var shownTen = false
    var shownThreeMonths = false
}

struct ReviewGate: Codable, Equatable {
    private(set) var requested = false

    mutating func shouldAsk(swaps: Int) -> Bool {
        guard !requested, swaps >= 4 else { return false }
        requested = true
        return true
    }
}

struct ToyData: Codable, Equatable {
    var coreReviewProgress: CoreReviewProgress?
    var rooms: [Room]
    var currentRoom: UUID
    var bins: [Bin] = []
    var settings = ToySettings()
    var swaps = 0
    var firstSwap: Date?
    var milestones = Milestones()
    var review = ReviewGate()

    init(roomName: String) {
        let room = Room(name: roomName)
        rooms = [room]
        currentRoom = room.id
    }

    static let freeBins = 6
}

enum Rotation {
    static func bins(_ data: ToyData, room: UUID) -> [Bin] { data.bins.filter { $0.roomID == room } }

    static func out(_ data: ToyData, room: UUID) -> [Bin] {
        bins(data, room: room).filter(\.isOut).sorted { ($0.outSince ?? .distantPast) < ($1.outSince ?? .distantPast) }
    }

    static func stored(_ data: ToyData, room: UUID) -> [Bin] {
        bins(data, room: room).filter { !$0.isOut }.sorted { a, b in
            switch (a.lastBack, b.lastBack) {
            case (nil, nil): return a.number < b.number
            case (nil, _): return true
            case (_, nil): return false
            case let (x?, y?): return x == y ? a.number < b.number : x < y
            }
        }
    }

    static func next(_ data: ToyData, room: UUID) -> Bin? { stored(data, room: room).first }

    static func days(from start: Date, to now: Date, calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: now)).day ?? 0
    }

    static func dayOut(_ bin: Bin, now: Date) -> Int { bin.outSince.map { days(from: $0, to: now) + 1 } ?? 0 }

    static func daysLeft(_ bin: Bin, settings: ToySettings, now: Date) -> Int {
        guard let since = bin.outSince else { return 0 }
        return settings.cycleDays - days(from: since, to: now)
    }

    static func dueDate(_ data: ToyData, room: UUID, calendar: Calendar = .current) -> Date? {
        guard let since = out(data, room: room).first?.outSince else { return nil }
        let day = calendar.date(byAdding: .day, value: data.settings.cycleDays, to: calendar.startOfDay(for: since)) ?? since
        return calendar.date(bySettingHour: data.settings.reminderHour, minute: data.settings.reminderMinute, second: 0, of: day)
    }

    static func daysStored(_ bin: Bin, now: Date) -> Int? { bin.lastBack.map { days(from: $0, to: now) } }

    @discardableResult
    static func swap(_ data: inout ToyData, room: UUID, bringOut chosen: UUID? = nil, now: Date) -> UUID? {
        guard let incoming = chosen ?? next(data, room: room)?.id,
              let inIndex = data.bins.firstIndex(where: { $0.id == incoming && $0.roomID == room }),
              !data.bins[inIndex].isOut else { return nil }
        var closed: UUID?
        let current = out(data, room: room)
        if current.count >= data.settings.outCount, let oldest = current.first,
           let i = data.bins.firstIndex(where: { $0.id == oldest.id }) {
            data.bins[i].outings[data.bins[i].outings.count - 1].end = now
            closed = oldest.id
        }
        data.bins[inIndex].outings.append(Outing(start: now))
        if closed != nil {
            data.swaps += 1
            if data.firstSwap == nil { data.firstSwap = now }
        }
        return closed
    }

    static func react(_ data: inout ToyData, bin: UUID, _ reaction: Reaction) {
        guard let i = data.bins.firstIndex(where: { $0.id == bin }),
              let j = data.bins[i].outings.lastIndex(where: { $0.end != nil }) else { return }
        data.bins[i].outings[j].reaction = reaction
    }

    static func favorite(_ data: ToyData, room: UUID? = nil) -> Bin? {
        let pool = room.map { bins(data, room: $0) } ?? data.bins
        return pool.filter { $0.lovedCount > 0 }.max { a, b in
            a.lovedCount == b.lovedCount ? (a.lovedRate ?? 0) < (b.lovedRate ?? 0) : a.lovedCount < b.lovedCount
        }
    }

    static func nextNumber(_ data: ToyData, room: UUID) -> Int {
        (bins(data, room: room).map(\.number).max() ?? 0) + 1
    }
}

enum SetupCode {
    static let prefix = "TOY1:"

    struct Payload: Codable, Equatable {
        var cycleDays: Int
        var outCount: Int
        var rooms: [String]
    }

    static func make(_ data: ToyData) -> String {
        let payload = Payload(cycleDays: data.settings.cycleDays, outCount: data.settings.outCount, rooms: data.rooms.map(\.name))
        let raw = (try? JSONEncoder().encode(payload)) ?? Data()
        return prefix + raw.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    static func decode(_ text: String) -> Payload? {
        guard text.count < 4_000, let start = text.range(of: prefix) else { return nil }
        let body = text[start.upperBound...].prefix { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        var b64 = body.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard !body.isEmpty, let raw = Data(base64Encoded: b64),
              var p = try? JSONDecoder().decode(Payload.self, from: raw),
              ToySettings.cycleChoices.contains(p.cycleDays), ToySettings.outChoices.contains(p.outCount),
              (1...8).contains(p.rooms.count) else { return nil }
        p.rooms = p.rooms.map { String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(20)) }.filter { !$0.isEmpty }
        return p.rooms.isEmpty ? nil : p
    }

    static func apply(_ p: Payload, to data: inout ToyData, allowRooms: Bool) {
        data.settings.cycleDays = p.cycleDays
        data.settings.outCount = p.outCount
        guard allowRooms else { return }
        for name in p.rooms where !data.rooms.contains(where: { $0.name == name }) {
            data.rooms.append(Room(name: name))
        }
    }
}
