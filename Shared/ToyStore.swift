import Foundation
import UserNotifications

struct ToyStore {
    static let group = "group.com.hgsldswk.toyrotation"
    static let widgetKind = "ToyRotationWidget"

    let folder: URL

    static func shared(testID: String? = nil) -> ToyStore {
        let fm = FileManager.default
        let base: URL
        if testID == nil, let group = fm.containerURL(forSecurityApplicationGroupIdentifier: group) {
            base = group
        } else {
            base = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
                ?? fm.temporaryDirectory
        }
        let folder = base.appendingPathComponent(testID.map { "ToyRotation-ui-\($0)" } ?? "ToyRotation", isDirectory: true)
        try? fm.createDirectory(at: folder.appendingPathComponent("photos", isDirectory: true), withIntermediateDirectories: true)
        return ToyStore(folder: folder)
    }

    var dataURL: URL { folder.appendingPathComponent("toys.json") }
    var photos: URL { folder.appendingPathComponent("photos", isDirectory: true) }

    func load() -> ToyData? {
        guard let raw = try? Data(contentsOf: dataURL) else { return nil }
        return try? JSONDecoder().decode(ToyData.self, from: raw)
    }

    @discardableResult func save(_ data: ToyData) -> Bool {
        do {
            let raw = try JSONEncoder().encode(data)
            try raw.write(to: dataURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return true
        } catch { return false }
    }

    func reset() { try? FileManager.default.removeItem(at: folder) }

    func photoURL(_ name: String) -> URL? {
        guard !name.isEmpty, !name.contains("/"), !name.contains("..") else { return nil }
        return photos.appendingPathComponent(name)
    }

    func savePhoto(_ jpeg: Data) -> String? {
        let name = UUID().uuidString + ".jpg"
        guard let url = photoURL(name), (try? jpeg.write(to: url, options: .atomic)) != nil else { return nil }
        return name
    }

    func removePhoto(_ name: String) {
        if let url = photoURL(name) { try? FileManager.default.removeItem(at: url) }
    }
}

enum Reminder {
    static func schedule(_ data: ToyData) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: data.rooms.map { "swap-\($0.id.uuidString)" })
        guard data.settings.remind else { return }
        for room in data.rooms {
            guard let due = Rotation.dueDate(data, room: room.id), due > Date(),
                  let next = Rotation.next(data, room: room.id) else { continue }
            let content = UNMutableNotificationContent()
            content.title = L.t("notify.title")
            let name = next.name.isEmpty ? L.f("bin.default", next.number) : next.name
            content.body = data.rooms.count > 1 ? L.f("notify.body.room", room.name, name) : L.f("notify.body", name)
            content.sound = .default
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: due)
            center.add(UNNotificationRequest(identifier: "swap-\(room.id.uuidString)", content: content,
                                             trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)))
        }
    }
}

extension Bin {
    var displayName: String { name.isEmpty ? L.f("bin.default", number) : name }
}
