import AppIntents
import Foundation
import WidgetKit

struct SwapIntent: AppIntent {
    static var title: LocalizedStringResource = "Swap toy bin"
    static var description = IntentDescription("Put the current bin away and bring out the next one.")

    func perform() async throws -> some IntentResult {
        let store = ToyStore.shared()
        if var data = store.load() {
            Rotation.swap(&data, room: data.currentRoom, now: Date())
            store.save(data)
            Reminder.schedule(data)
        }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
