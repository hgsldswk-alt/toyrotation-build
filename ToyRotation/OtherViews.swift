import StoreKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var newRoom = ""

    var body: some View {
        NavigationStack {
            Form {
                Section(L.t("settings.rotation")) {
                    Picker(L.t("settings.cycle"), selection: $model.data.settings.cycleDays) {
                        ForEach(ToySettings.cycleChoices, id: \.self) { Text(L.f("settings.days", $0)).tag($0) }
                    }
                    .accessibilityIdentifier("settings.cycle")
                    Picker(L.t("settings.out"), selection: $model.data.settings.outCount) {
                        ForEach(ToySettings.outChoices, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                Section(L.t("settings.reminder")) {
                    Toggle(L.t("settings.remind"), isOn: $model.data.settings.remind)
                    if model.data.settings.remind {
                        DatePicker(L.t("settings.time"), selection: Binding(get: {
                            Calendar.current.date(bySettingHour: model.data.settings.reminderHour,
                                                  minute: model.data.settings.reminderMinute, second: 0, of: Date()) ?? Date()
                        }, set: { date in
                            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                            model.data.settings.reminderHour = parts.hour ?? 9
                            model.data.settings.reminderMinute = parts.minute ?? 0
                        }), displayedComponents: .hourAndMinute)
                    }
                }
                Section {
                    ForEach(model.data.rooms) { room in
                        HStack {
                            Text(room.name)
                            Spacer()
                            if room.id == model.data.currentRoom { Image(systemName: "checkmark").foregroundStyle(D.coral) }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { model.selectRoom(room.id) }
                    }
                    HStack {
                        TextField(L.t("settings.room.placeholder"), text: $newRoom)
                        Button(L.t("settings.room.add")) { model.addRoom(newRoom); newRoom = "" }
                            .disabled(newRoom.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: { Text(L.t("settings.rooms")) } footer: { Text(L.t("settings.rooms.footer")) }
                Section(L.t("settings.share")) {
                    Button(L.t("settings.copy-code")) { model.copyCode() }
                    Button(L.t("settings.paste-code")) {
                        if model.testing, let text = ProcessInfo.processInfo.environment["UITEST_CODE"] {
                            model.pasteCode(text)
                        } else {
                            model.pasteCode(UIPasteboard.general.string)
                        }
                    }
                    .accessibilityIdentifier("settings.paste-code")
                }
                Section {
                    if model.purchases.entitlement?.purchasedPro == true {
                        Label(L.t("settings.unlocked"), systemImage: "checkmark.seal.fill").foregroundStyle(D.green)
                    } else {
                        Button(model.hasPro
                               ? L.f("settings.trial", model.purchases.entitlement?.trialDaysLeft(at: model.now) ?? 30)
                               : L.t("settings.unlock")) { model.sheet = .paywall }
                            .accessibilityIdentifier("settings.unlock")
                    }
                    Button(L.t("settings.restore")) { Task { await model.purchases.restore() } }
                }
            }
            .navigationTitle(L.t("settings.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L.t("common.done")) { dismiss() } } }
        }
    }
}

struct ShareCard: View {
    let photo: UIImage?
    let binName: String
    let swaps: Int
    let favorite: String?
    let stats: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            BinPhoto(image: photo, caption: L.f("share.this-week", binName), height: 260)
            Text(favorite.map { L.f("share.summary.fav", swaps, $0) } ?? L.f("share.summary", swaps))
                .font(.title3.weight(.heavy))
            if stats {
                Text(L.t("share.stats-line")).font(.subheadline).foregroundStyle(D.muted)
            }
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L.t("share.tags")).font(.subheadline.weight(.bold)).foregroundStyle(D.coral)
                    Text(L.t("app.name")).font(.caption).foregroundStyle(D.muted)
                }
                Spacer()
                if let qr = QR.image() {
                    Image(uiImage: qr).interpolation(.none).resizable().frame(width: 68, height: 68)
                }
            }
        }
        .padding(18)
        .frame(width: 360)
        .background(D.paper)
        .foregroundStyle(D.ink)
    }
}

struct SharePreview: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var stats = false

    private var card: ShareCard {
        let bin = model.outBins.first
        return ShareCard(photo: model.photo(bin?.photo), binName: bin?.displayName ?? "", swaps: model.data.swaps,
                         favorite: Rotation.favorite(model.data)?.displayName, stats: stats)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    card.clipShape(RoundedRectangle(cornerRadius: 20)).overlay(RoundedRectangle(cornerRadius: 20).stroke(D.line))
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("share.card")
                    Picker("", selection: Binding(get: { stats }, set: { v in
                        if v && !model.hasPro { model.sheet = nil; model.later { model.sheet = .paywall } } else { stats = v }
                    })) {
                        Text(L.t("share.style.photo")).tag(false)
                        Text(L.t("share.style.stats")).tag(true)
                    }
                    .pickerStyle(.segmented)
                    Button(L.t("share.send")) {
                        let renderer = ImageRenderer(content: card)
                        renderer.scale = 3
                        if let image = renderer.uiImage {
                            dismiss()
                            model.later { model.share(image) }
                        }
                    }
                    .buttonStyle(PrimaryButton())
                    .accessibilityIdentifier("share.send")
                    Button(L.t("settings.copy-code")) { model.copyCode() }.buttonStyle(PrimaryButton(filled: false))
                }
                .padding(18)
            }
            .background(D.paper.ignoresSafeArea())
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L.t("common.close")) { dismiss() } } }
        }
    }
}

struct MilestoneView: View {
    @EnvironmentObject private var model: AppModel
    let value: Int

    var body: some View {
        VStack(spacing: 12) {
            Text(L.t("milestone.label")).font(.caption.weight(.bold)).foregroundStyle(D.muted)
            Text(value == 90 ? L.t("milestone.months") : L.f("milestone.swaps", value))
                .font(.system(size: 36, weight: .heavy)).foregroundStyle(D.coral).multilineTextAlignment(.center)
            Text(L.t(value == 90 ? "milestone.months.body" : "milestone.swaps.body"))
                .foregroundStyle(D.muted).multilineTextAlignment(.center)
            Button(L.t("milestone.share")) { model.sheet = nil; model.later { model.sheet = .share } }
                .buttonStyle(PrimaryButton())
                .accessibilityIdentifier("milestone.share")
        }
        .padding(24)
        .presentationDetents([.medium])
    }
}

struct PaywallView: View {
    @ObservedObject var purchases: Purchases
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Image(systemName: "shippingbox.and.arrow.backward.fill").font(.system(size: 46)).foregroundStyle(D.coral)
                    Text(L.t("paywall.title")).font(.title.weight(.bold)).accessibilityIdentifier("paywall.title")
                    Text(L.t("paywall.body")).foregroundStyle(D.muted)
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(["paywall.f1", "paywall.f2", "paywall.f3", "paywall.f4"], id: \.self) { key in
                            Label(L.t(key), systemImage: "checkmark.circle.fill").font(.subheadline)
                        }
                    }
                    .cardBox()
                    Text(L.t("paywall.free")).font(.footnote).foregroundStyle(D.muted)
                    if let product = purchases.products.first(where: { $0.id == purchases.proID }) {
                        Button(L.f("paywall.buy", product.displayPrice)) { Task { await purchases.purchase(product) } }
                            .buttonStyle(PrimaryButton())
                            .disabled(purchases.busy)
                    } else if ProcessInfo.processInfo.arguments.contains("-ui-testing") {
                        Button(L.f("paywall.buy", L.t("paywall.price.sample"))) {}.buttonStyle(PrimaryButton())
                    } else {
                        Button(L.t("paywall.loading")) {}.buttonStyle(PrimaryButton()).disabled(true)
                    }
                    Button(L.t("settings.restore")) { Task { await purchases.restore() } }
                        .buttonStyle(PrimaryButton(filled: false))
                    Text(L.t("paywall.once")).font(.caption).foregroundStyle(D.muted)
                }
                .padding(22)
            }
            .background(D.paper.ignoresSafeArea())
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L.t("common.close")) { dismiss() } } }
            .task { await purchases.loadProducts() }
            .onChange(of: purchases.entitlement?.purchasedPro) { _, value in if value == true { dismiss() } }
            .alert(L.t("notice.title"), isPresented: Binding(get: { purchases.message != nil }, set: { if !$0 { purchases.message = nil } })) {
                Button(L.t("common.ok"), role: .cancel) { purchases.message = nil }
            } message: { Text(purchases.message ?? "") }
        }
    }
}
