import SwiftUI
import UIKit
import UserNotifications
import WidgetKit

struct ShareItems: Identifiable {
    let id = UUID()
    let items: [Any]
}

struct ReactionAsk: Identifiable {
    let id: UUID
    let name: String
}

enum Sheet: Identifiable {
    case settings, paywall, milestone(Int), share
    var id: String {
        switch self {
        case .settings: "settings"
        case .paywall: "paywall"
        case .milestone(let n): "milestone\(n)"
        case .share: "share"
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var data: ToyData { didSet { if data != oldValue { persist() } } }
    @Published var path: [UUID] = []
    @Published var sheet: Sheet?
    @Published var asking: ReactionAsk?
    @Published var activity: ShareItems?
    @Published var addingBin = false
    @Published var toast: String?
    @Published var reviewSignal = 0
    @Published var now = Date()

    let testing: Bool
    let expired: Bool
    let store: ToyStore
    let purchases = Purchases.shared
    private var toastTask: Task<Void, Never>?
    @Published private(set) var presentingSwapMilestone = false
    private var pendingMilestone: Int?
    private var savedRotation = false

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        testing = Launch.has("-ui-testing", in: arguments)
        expired = Launch.has("-expired", in: arguments) || Launch.has("-paywall", in: arguments)
        store = ToyStore.shared(testID: testing ? (Launch.value("-data-id", in: arguments) ?? "x") : nil)
        if testing && Launch.has("-reset", in: arguments) { store.reset() }
        _ = try? FileManager.default.createDirectory(at: store.photos, withIntermediateDirectories: true)
        data = store.load() ?? ToyData(roomName: L.t("room.default"))
        if testing, let fixture = Launch.value("-fixture", in: arguments) {
            data = Fixtures.data(fixture, store: store)
        }
    }

    func start() async {
        await purchases.start(now: Date(), testing: testing, expired: expired)
        now = Date()
        if Launch.has("-paywall") { sheet = .paywall }
    }

    func becameActive() {
        if !testing, let fresh = store.load(), fresh != data { data = fresh }
        now = Date()
    }

    private func persist() {
        savedRotation = store.save(data)
        guard !testing else { return }
        Reminder.schedule(data)
        WidgetCenter.shared.reloadAllTimelines()
    }

    var hasPro: Bool { purchases.hasPro(at: now) }
    var room: UUID { data.currentRoom }
    var roomName: String { data.rooms.first { $0.id == room }?.name ?? "" }
    var outBins: [Bin] { Rotation.out(data, room: room) }
    var storedBins: [Bin] { Rotation.stored(data, room: room) }
    var nextBin: Bin? { Rotation.next(data, room: room) }
    func bin(_ id: UUID) -> Bin? { data.bins.first { $0.id == id } }

    func photo(_ name: String?) -> UIImage? {
        guard let name, let url = store.photoURL(name) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    func notify(_ text: String) {
        toast = text
        toastTask?.cancel()
        toastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            if !Task.isCancelled { self.toast = nil }
        }
    }


    func swap(bringOut chosen: UUID? = nil) {
        let before = data.swaps
        var next = data
        let closed = Rotation.swap(&next, room: room, bringOut: chosen, now: Date())
        if next.swaps > before && !testing { next.coreReviewProgress = .recording(next.coreReviewProgress) }
        data = next
        now = Date()
        path = []
        if let closed, let bin = bin(closed) {
            asking = ReactionAsk(id: bin.id, name: bin.displayName)
        }
        if data.swaps > before {
            if savedRotation && !testing { CoreReview.shared.record(data.coreReviewProgress) }
            afterSwap()
        }
        requestNotifications()
    }

    func react(_ reaction: Reaction?) {
        if let ask = asking, let reaction { Rotation.react(&data, bin: ask.id, reaction) }
        asking = nil
        if let value = pendingMilestone {
            pendingMilestone = nil
            presentingSwapMilestone = true
            later(0.8) {
                self.sheet = .milestone(value)
                self.presentingSwapMilestone = false
            }
        }
    }

    private func afterSwap() {
        if data.swaps >= 10 && !data.milestones.shownTen {
            data.milestones.shownTen = true
            pendingMilestone = 10
        } else if let first = data.firstSwap, Rotation.days(from: first, to: Date()) >= 90, !data.milestones.shownThreeMonths {
            data.milestones.shownThreeMonths = true
            pendingMilestone = 90
        }
        if !testing && savedRotation { reviewSignal += 1 }
    }

    func requestSwapReview(_ request: () -> Void) {
        var next = data.review
        guard CoreReview.shared.attempt(ifEligible: { next.shouldAsk(swaps: data.swaps) }, request) else { return }
        data.review = next
    }

    func later(_ seconds: Double = 0.9, _ work: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            work()
        }
    }

    private func requestNotifications() {
        guard !testing, data.settings.remind else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }


    var canAddBin: Bool { hasPro || data.bins.count < ToyData.freeBins }

    func startAddBin() {
        guard canAddBin else { sheet = .paywall; return }
        addingBin = true
    }

    func addBin(photo: UIImage?) {
        addingBin = false
        guard let photo else { return }
        var bin = Bin(roomID: room, number: Rotation.nextNumber(data, room: room))
        bin.photo = jpeg(photo).flatMap(store.savePhoto)
        data.bins.append(bin)
        if outBins.count < data.settings.outCount { Rotation.swap(&data, room: room, bringOut: bin.id, now: Date()) }
        notify(L.f("bin.added", bin.displayName))
    }

    func updateBin(_ id: UUID, _ change: (inout Bin) -> Void) {
        guard let i = data.bins.firstIndex(where: { $0.id == id }) else { return }
        change(&data.bins[i])
    }

    func retake(_ id: UUID, photo: UIImage?) {
        guard let photo, let name = jpeg(photo).flatMap(store.savePhoto) else { return }
        let old = bin(id)?.photo
        updateBin(id) { $0.photo = name }
        if let old { store.removePhoto(old) }
    }

    func delete(_ id: UUID) {
        if let name = bin(id)?.photo { store.removePhoto(name) }
        data.bins.removeAll { $0.id == id }
        path = []
    }

    func jpeg(_ image: UIImage) -> Data? {
        let longest = max(image.size.width, image.size.height)
        let scale = longest > 1400 ? 1400 / longest : 1
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }.jpegData(compressionQuality: 0.7)
    }


    func selectRoom(_ id: UUID) {
        guard hasPro || id == data.rooms.first?.id else { sheet = .paywall; return }
        data.currentRoom = id
    }

    func addRoom(_ name: String) {
        guard hasPro else { sheet = .paywall; return }
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(20))
        guard !trimmed.isEmpty else { return }
        let room = Room(name: trimmed)
        data.rooms.append(room)
        data.currentRoom = room.id
    }

    func copyCode() {
        UIPasteboard.general.string = L.t("code.intro") + "\n" + SetupCode.make(data)
        notify(L.t("code.copied"))
    }

    func pasteCode(_ text: String?) {
        guard let text, let payload = SetupCode.decode(text) else { return notify(L.t("code.none")) }
        SetupCode.apply(payload, to: &data, allowRooms: hasPro)
        notify(L.f("code.applied", payload.cycleDays))
    }


    func share(_ image: UIImage) {
        activity = ShareItems(items: [image, L.t("share.text")])
    }
}

enum Fixtures {
    @MainActor
    static func data(_ name: String, store: ToyStore) -> ToyData {
        var data = ToyData(roomName: L.t("room.default"))
        guard name != "empty" else { return data }
        let room = data.currentRoom
        let day: TimeInterval = 86_400
        let now = Date()
        let names = ["fixture.blocks", "fixture.cars", "fixture.pretend", "fixture.books", "fixture.puzzles", "fixture.music"]
        let colors: [(UIColor, UIColor)] = [
            (UIColor(red: 0.94, green: 0.76, blue: 0.35, alpha: 1), UIColor(red: 0.85, green: 0.52, blue: 0.23, alpha: 1)),
            (UIColor(red: 0.91, green: 0.63, blue: 0.36, alpha: 1), UIColor(red: 0.79, green: 0.44, blue: 0.23, alpha: 1)),
            (UIColor(red: 0.85, green: 0.54, blue: 0.63, alpha: 1), UIColor(red: 0.69, green: 0.36, blue: 0.47, alpha: 1)),
            (UIColor(red: 0.56, green: 0.72, blue: 0.85, alpha: 1), UIColor(red: 0.35, green: 0.53, blue: 0.71, alpha: 1)),
            (UIColor(red: 0.61, green: 0.77, blue: 0.60, alpha: 1), UIColor(red: 0.37, green: 0.60, blue: 0.36, alpha: 1)),
            (UIColor(red: 0.78, green: 0.65, blue: 0.87, alpha: 1), UIColor(red: 0.56, green: 0.42, blue: 0.69, alpha: 1)),
        ]
        let history: [[(Double, Reaction?)]] = [
            [(63, .loved), (35, .loved), (14, .okay)], [(49, .loved)], [(42, .okay), (21, .loved)],
            [(28, .ignored), (7, .loved)], [(56, .okay)], [(70, .loved), (21, nil)],
        ]
        for (i, key) in names.enumerated() {
            var bin = Bin(roomID: room, number: i + 1)
            bin.name = L.t(key)
            bin.photo = store.savePhoto(draw(colors[i], seed: i))
            bin.created = now.addingTimeInterval(-80 * day)
            for (ago, reaction) in history[i] {
                bin.outings.append(Outing(start: now.addingTimeInterval(-ago * day),
                                          end: now.addingTimeInterval(-(ago - 7) * day), reaction: reaction))
            }
            if i == 0 { bin.outings.append(Outing(start: now.addingTimeInterval(-3 * day))) }
            if i == 0 { bin.note = L.t("fixture.note") }
            data.bins.append(bin)
        }
        data.swaps = name == "milestone" ? 9 : 12
        data.firstSwap = now.addingTimeInterval(-70 * day)
        data.milestones.shownThreeMonths = true
        return data
    }

    static func draw(_ colors: (UIColor, UIColor), seed: Int) -> Data {
        let size = CGSize(width: 900, height: 700)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let cg = ctx.cgContext
            UIColor(red: 0.96, green: 0.93, blue: 0.88, alpha: 1).setFill()
            cg.fill(CGRect(origin: .zero, size: size))
            UIColor(red: 0.86, green: 0.80, blue: 0.72, alpha: 1).setFill()
            cg.fill(CGRect(x: 0, y: 520, width: 900, height: 180))
            let toys: [UIColor] = [.systemRed, .systemBlue, .systemYellow, .systemGreen, .systemOrange, .systemPurple]
            for k in 0..<7 {
                toys[(k + seed) % toys.count].setFill()
                let x = 220 + CGFloat((k * 67 + seed * 31) % 420), y = 200 + CGFloat((k * 41 + seed * 17) % 90)
                if (k + seed) % 2 == 0 {
                    UIBezierPath(roundedRect: CGRect(x: x, y: y, width: 110, height: 110), cornerRadius: 14).fill()
                } else {
                    UIBezierPath(ovalIn: CGRect(x: x, y: y, width: 110, height: 110)).fill()
                }
            }
            colors.0.setFill()
            UIBezierPath(roundedRect: CGRect(x: 150, y: 300, width: 600, height: 300), cornerRadius: 28).fill()
            colors.1.setFill()
            UIBezierPath(roundedRect: CGRect(x: 150, y: 300, width: 600, height: 54), cornerRadius: 20).fill()
            UIColor(white: 1, alpha: 0.85).setFill()
            UIBezierPath(roundedRect: CGRect(x: 360, y: 420, width: 180, height: 80), cornerRadius: 12).fill()
            let label = "\(seed + 1)" as NSString
            label.draw(at: CGPoint(x: 430, y: 425), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 60), .foregroundColor: colors.1])
        }
        return image.jpegData(compressionQuality: 0.75) ?? Data()
    }
}
