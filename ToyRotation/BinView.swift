import SwiftUI

struct BinView: View {
    @EnvironmentObject private var model: AppModel
    let id: UUID
    @State private var camera = false
    @State private var confirmDelete = false

    var body: some View {
        ScrollView {
            if let bin = model.bin(id) {
                VStack(alignment: .leading, spacing: 14) {
                    Button { if model.testing { model.retake(id, photo: nil) } else { camera = true } } label: {
                        BinPhoto(image: model.photo(bin.photo), caption: L.t("bin.retake"), height: 220)
                    }
                    .buttonStyle(.plain)
                    TextField(L.f("bin.default", bin.number), text: Binding(
                        get: { model.bin(id)?.name ?? "" },
                        set: { value in model.updateBin(id) { $0.name = String(value.prefix(20)) } }))
                        .font(.title2.weight(.bold))
                        .accessibilityIdentifier("bin.name")
                    if !bin.isOut {
                        Button(L.t("bin.take-out")) { model.swap(bringOut: id) }
                            .buttonStyle(PrimaryButton())
                            .accessibilityIdentifier("bin.take-out")
                    }
                    HStack(spacing: 10) {
                        stat(L.t("bin.outings"), "\(bin.outings.count)")
                        if model.hasPro {
                            stat(L.t("bin.loved-rate"), bin.lovedRate.map { "\(Int(($0 * 100).rounded()))%" } ?? "—", accent: true)
                        } else {
                            Button { model.sheet = .paywall } label: { stat(L.t("bin.loved-rate"), "🔒", accent: true) }
                                .buttonStyle(.plain)
                        }
                        stat(L.t("bin.last"), last(bin))
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L.t("bin.history")).font(.headline)
                        if bin.outings.isEmpty {
                            Text(L.t("bin.history.empty")).font(.subheadline).foregroundStyle(D.muted)
                        }
                        ForEach(Array(bin.outings.reversed().enumerated()), id: \.offset) { _, outing in
                            HStack {
                                Text(range(outing)).font(.subheadline)
                                Spacer()
                                if let reaction = outing.reaction {
                                    Text(L.t(reaction.key)).font(.subheadline.weight(.semibold))
                                        .foregroundStyle(reaction == .loved ? D.coral : D.muted)
                                } else if outing.end == nil {
                                    Text(L.t("bin.now-out")).font(.subheadline.weight(.semibold)).foregroundStyle(D.green)
                                }
                            }
                        }
                    }
                    .cardBox()
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L.t("bin.note")).font(.headline)
                        TextField(L.t("bin.note.placeholder"), text: Binding(
                            get: { model.bin(id)?.note ?? "" },
                            set: { value in model.updateBin(id) { $0.note = String(value.prefix(200)) } }), axis: .vertical)
                    }
                    .cardBox()
                    Button(L.t("bin.delete"), role: .destructive) { confirmDelete = true }
                        .font(.subheadline)
                }
                .padding(.horizontal, 18).padding(.bottom, 24)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .background(D.paper.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $camera) {
            CameraPicker { image in
                camera = false
                model.retake(id, photo: image)
            }
            .ignoresSafeArea()
        }
        .confirmationDialog(L.t("bin.delete.confirm"), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(L.t("bin.delete"), role: .destructive) { model.delete(id) }
        }
    }

    private func stat(_ title: String, _ value: String, accent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(D.muted)
            Text(value).font(.system(size: 26, weight: .heavy)).foregroundStyle(accent ? D.coral : D.ink)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .cardBox()
    }

    private func last(_ bin: Bin) -> String {
        if bin.isOut { return L.t("bin.now-out") }
        return Rotation.daysStored(bin, now: model.now).map { L.f("home.days", $0) } ?? "—"
    }

    private func range(_ outing: Outing) -> String {
        let f = Date.FormatStyle().month(.twoDigits).day(.twoDigits)
        return outing.start.formatted(f) + " → " + (outing.end?.formatted(f) ?? "…")
    }
}
