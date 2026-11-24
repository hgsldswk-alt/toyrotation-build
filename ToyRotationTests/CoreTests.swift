import Foundation
import XCTest

final class CoreTests: XCTestCase {
    private let day: TimeInterval = 86_400
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func sample() -> ToyData {
        var data = ToyData(roomName: "Playroom")
        let room = data.currentRoom
        for n in 1...4 { data.bins.append(Bin(roomID: room, number: n)) }
        data.bins[1].outings = [Outing(start: now - 30 * day, end: now - 23 * day)]
        data.bins[2].outings = [Outing(start: now - 20 * day, end: now - 13 * day)]
        data.bins[0].outings = [Outing(start: now - 3 * day)]
        return data
    }

    func testOutAndStoredOrder() {
        let data = sample()
        XCTAssertEqual(Rotation.out(data, room: data.currentRoom).map(\.number), [1])
        XCTAssertEqual(Rotation.stored(data, room: data.currentRoom).map(\.number), [4, 2, 3])
        XCTAssertEqual(Rotation.next(data, room: data.currentRoom)?.number, 4)
    }

    func testDaysOutAndLeft() {
        let data = sample()
        let bin = data.bins[0]
        XCTAssertEqual(Rotation.dayOut(bin, now: now), 4)
        XCTAssertEqual(Rotation.daysLeft(bin, settings: data.settings, now: now), 4)
        XCTAssertEqual(Rotation.daysStored(data.bins[1], now: now), 23)
        XCTAssertNil(Rotation.daysStored(data.bins[3], now: now))
    }

    func testSwapNextClosesOldestAndOpensNext() {
        var data = sample()
        let closed = Rotation.swap(&data, room: data.currentRoom, now: now)
        XCTAssertEqual(closed, data.bins[0].id)
        XCTAssertFalse(data.bins[0].isOut)
        XCTAssertTrue(data.bins[3].isOut)
        XCTAssertEqual(data.swaps, 1)
        XCTAssertEqual(data.firstSwap, now)
    }

    func testSwapChosenAndCapacity() {
        var data = sample()
        data.settings.outCount = 2
        let closed = Rotation.swap(&data, room: data.currentRoom, bringOut: data.bins[2].id, now: now)
        XCTAssertNil(closed, "room not full: nothing goes back")
        XCTAssertEqual(Rotation.out(data, room: data.currentRoom).count, 2)
        XCTAssertEqual(data.swaps, 0)
        XCTAssertNil(Rotation.swap(&data, room: data.currentRoom, bringOut: data.bins[2].id, now: now), "already out")
    }

    func testReactionAndFavorite() {
        var data = sample()
        Rotation.swap(&data, room: data.currentRoom, now: now)
        Rotation.react(&data, bin: data.bins[0].id, .loved)
        XCTAssertEqual(data.bins[0].outings.last?.reaction, .loved)
        XCTAssertEqual(data.bins[0].lovedRate, 1)
        XCTAssertEqual(Rotation.favorite(data)?.number, 1)
        XCTAssertNil(Rotation.favorite(ToyData(roomName: "x")))
    }

    func testRoomsAreSeparate() {
        var data = sample()
        let other = Room(name: "Bedroom")
        data.rooms.append(other)
        data.bins.append(Bin(roomID: other.id, number: 1))
        XCTAssertEqual(Rotation.stored(data, room: data.currentRoom).count, 3)
        XCTAssertEqual(Rotation.next(data, room: other.id)?.roomID, other.id)
        XCTAssertEqual(Rotation.nextNumber(data, room: other.id), 2)
        XCTAssertEqual(Rotation.nextNumber(data, room: data.currentRoom), 5)
    }

    func testDueDate() {
        var data = sample()
        data.settings.reminderHour = 9
        let due = Rotation.dueDate(data, room: data.currentRoom)!
        let cal = Calendar.current
        XCTAssertEqual(cal.component(.hour, from: due), 9)
        XCTAssertEqual(Rotation.days(from: now - 3 * day, to: due), 7)
    }

    func testSetupCode() throws {
        var data = sample()
        data.settings.cycleDays = 5
        data.rooms.append(Room(name: "Bedroom"))
        let code = SetupCode.make(data)
        let p = try XCTUnwrap(SetupCode.decode("try this \(code) !"))
        XCTAssertEqual(p.cycleDays, 5)
        XCTAssertEqual(p.rooms, ["Playroom", "Bedroom"])
        var mine = ToyData(roomName: "Playroom")
        SetupCode.apply(p, to: &mine, allowRooms: false)
        XCTAssertEqual(mine.settings.cycleDays, 5)
        XCTAssertEqual(mine.rooms.count, 1)
        SetupCode.apply(p, to: &mine, allowRooms: true)
        XCTAssertEqual(mine.rooms.map(\.name), ["Playroom", "Bedroom"])
        XCTAssertNil(SetupCode.decode("TOY1:zzz"))
        XCTAssertNil(SetupCode.decode("hello"))
    }

    func testCoreReviewRequiresThreeActionsOnTwoLocalDates() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        let firstDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: 23)))
        let nextDay = firstDay.addingTimeInterval(2 * 3600)
        let empty = try JSONDecoder().decode(CoreReviewProgress.self, from: Data("{}".utf8))
        XCTAssertFalse(empty.isEligible)
        var progress = CoreReviewProgress.recording(empty, at: firstDay, calendar: calendar)
        var twoDays = progress
        twoDays.record(at: nextDay, calendar: calendar)
        XCTAssertFalse(twoDays.isEligible)
        progress.record(at: firstDay, calendar: calendar)
        XCTAssertFalse(progress.isEligible)

        var sameDay = progress
        sameDay.record(at: firstDay, calendar: calendar)
        XCTAssertFalse(sameDay.isEligible)

        let data = try JSONEncoder().encode(progress)
        progress = try JSONDecoder().decode(CoreReviewProgress.self, from: data)
        progress.record(at: nextDay, calendar: calendar)
        XCTAssertTrue(progress.isEligible)
    }

    func testReviewAfterFourthSwap() {
        var gate = ReviewGate()
        XCTAssertFalse(gate.shouldAsk(swaps: 3))
        XCTAssertTrue(gate.shouldAsk(swaps: 4))
        XCTAssertFalse(gate.shouldAsk(swaps: 5))
    }

    func testStringsLocalized() {
        for key in ["bin.default", "home.swap.days", "reaction.loved", "widget.swap", "notify.title"] {
            XCTAssertNotEqual(L.t(key), key)
        }
    }
}
