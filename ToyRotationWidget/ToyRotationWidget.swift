import AppIntents
import ImageIO
import SwiftUI
import UIKit
import WidgetKit

private struct Entry: TimelineEntry {
    let date: Date
    let name: String?
    let daysLeft: Int
    let next: String?
    let photo: UIImage?
}

private struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry {
        Entry(date: Date(), name: L.f("bin.default", 2), daysLeft: 3, next: L.f("bin.default", 5), photo: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(make(Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let calendar = Calendar.current
        let midnight = calendar.startOfDay(for: Date())
        let dates = [Date()] + (1...3).compactMap { calendar.date(byAdding: .day, value: $0, to: midnight) }
        completion(Timeline(entries: dates.map(make), policy: .atEnd))
    }

    private func make(_ date: Date) -> Entry {
        let store = ToyStore.shared()
        guard let data = store.load(), let bin = Rotation.out(data, room: data.currentRoom).first else {
            return Entry(date: date, name: nil, daysLeft: 0, next: nil, photo: nil)
        }
        let photo = bin.photo.flatMap(store.photoURL).flatMap { thumbnail($0) }
        return Entry(date: date, name: bin.displayName, daysLeft: Rotation.daysLeft(bin, settings: data.settings, now: date),
                     next: Rotation.next(data, room: data.currentRoom)?.displayName, photo: photo)
    }

    private func thumbnail(_ url: URL) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: 400,
                  kCGImageSourceCreateThumbnailWithTransform: true,
              ] as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }
}

private func due(_ days: Int) -> String {
    days <= 0 ? L.t("widget.due-today") : L.f("widget.due-in", days)
}

private struct WidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: Entry
    private let coral = Color(red: 0.878, green: 0.404, blue: 0.247)

    var body: some View {
        if family == .accessoryRectangular {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name.map { L.f("widget.playing", $0) } ?? L.t("widget.empty")).font(.headline).lineLimit(1)
                if entry.name != nil { Text(due(entry.daysLeft)).font(.caption) }
            }
            .containerBackground(for: .widget) { Color.clear }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                if let name = entry.name {
                    Text(L.t("widget.out")).font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.9))
                    Text(name).font(.headline.weight(.heavy)).lineLimit(1)
                    Text(due(entry.daysLeft)).font(.caption.weight(.semibold))
                    Spacer(minLength: 0)
                    if entry.next != nil {
                        Button(intent: SwapIntent()) {
                            Text(L.t("widget.swap")).font(.caption.weight(.bold)).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(coral)
                    }
                } else {
                    Text(L.t("widget.empty")).font(.subheadline.weight(.semibold))
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .containerBackground(for: .widget) {
                ZStack {
                    if let photo = entry.photo {
                        Image(uiImage: photo).resizable().scaledToFill()
                        LinearGradient(colors: [.black.opacity(0.55), .black.opacity(0.15), .black.opacity(0.55)],
                                       startPoint: .top, endPoint: .bottom)
                    } else {
                        LinearGradient(colors: [Color(red: 0.94, green: 0.76, blue: 0.35), coral], startPoint: .topLeading, endPoint: .bottomTrailing)
                    }
                }
            }
        }
    }
}

@main
struct ToyRotationWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: ToyStore.widgetKind, provider: Provider()) { entry in
            WidgetView(entry: entry)
        }
        .configurationDisplayName(L.t("widget.name"))
        .description(L.t("widget.description"))
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}
