import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                if model.data.bins.filter({ $0.roomID == model.room }).isEmpty {
                    emptyState
                } else {
                    ForEach(model.outBins) { bin in
                        OutCard(bin: bin)
                    }
                    if let next = model.nextBin {
                        Button {
                            model.swap()
                        } label: {
                            Text(swapTitle(next))
                        }
                        .buttonStyle(PrimaryButton())
                        .accessibilityIdentifier("home.swap")
                    }
                    Text(L.t("home.stored")).font(.subheadline.weight(.bold))
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(model.storedBins) { bin in
                            Button { model.path = [bin.id] } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    BinPhoto(image: model.photo(bin.photo), caption: storedCaption(bin))
                                    Text(bin.displayName).font(.caption).foregroundStyle(D.muted).lineLimit(1)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("home.bin.\(bin.number)")
                        }
                        Button { model.startAddBin() } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 16).fill(D.pale)
                                    Image(systemName: "camera.fill").font(.title2).foregroundStyle(D.coral)
                                }
                                .frame(height: 92)
                                Text(L.t("home.add")).font(.caption).foregroundStyle(D.muted)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("home.add")
                    }
                }
            }
            .padding(.horizontal, 18).padding(.bottom, 24)
        }
        .background(D.paper.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        HStack {
            Menu {
                ForEach(model.data.rooms) { room in
                    Button(room.name) { model.selectRoom(room.id) }
                }
                Button(L.t("room.add")) { model.sheet = .settings }
            } label: {
                Label(model.roomName, systemImage: "chevron.down")
                    .font(.subheadline.weight(.bold))
                    .padding(.vertical, 6).padding(.horizontal, 10)
                    .background(D.pale, in: Capsule())
            }
            .accessibilityIdentifier("home.room")
            Spacer()
            Text(L.f("home.cycle", model.data.settings.cycleDays, model.data.settings.outCount))
                .font(.footnote).foregroundStyle(D.muted)
            if !model.outBins.isEmpty {
                Button { model.sheet = .share } label: { Image(systemName: "square.and.arrow.up").foregroundStyle(D.muted).frame(width: 40, height: 44).contentShape(Rectangle()) }
                    .accessibilityIdentifier("home.share")
            }
            Button { model.sheet = .settings } label: { Image(systemName: "gearshape.fill").foregroundStyle(D.muted).frame(width: 40, height: 44).contentShape(Rectangle()) }
                .accessibilityIdentifier("home.settings")
        }
        .padding(.top, 6)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "shippingbox.fill").font(.system(size: 54)).foregroundStyle(D.coral)
            Text(L.t("empty.title")).font(.title2.weight(.bold)).multilineTextAlignment(.center)
            Text(L.t("empty.body")).font(.subheadline).foregroundStyle(D.muted).multilineTextAlignment(.center)
            Button(L.t("empty.add")) { model.startAddBin() }
                .buttonStyle(PrimaryButton())
                .accessibilityIdentifier("empty.add")
        }
        .padding(.top, 60)
    }

    private func swapTitle(_ next: Bin) -> String {
        if let days = Rotation.daysStored(next, now: model.now) {
            return L.f("home.swap.days", next.displayName, days)
        }
        return L.f("home.swap.new", next.displayName)
    }

    private func storedCaption(_ bin: Bin) -> String {
        Rotation.daysStored(bin, now: model.now).map { L.f("home.days", $0) } ?? L.t("home.never")
    }
}

struct OutCard: View {
    @EnvironmentObject private var model: AppModel
    let bin: Bin

    var body: some View {
        let left = Rotation.daysLeft(bin, settings: model.data.settings, now: model.now)
        VStack(alignment: .leading, spacing: 10) {
            Button { model.path = [bin.id] } label: {
                BinPhoto(image: model.photo(bin.photo), height: model.outBins.count > 1 ? 160 : 240)
            }
            .buttonStyle(.plain)
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L.t("home.playing")).font(.footnote).foregroundStyle(D.muted)
                    Text(bin.displayName).font(.system(size: 30, weight: .heavy)).lineLimit(1).minimumScaleFactor(0.7)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(L.f("home.day", Rotation.dayOut(bin, now: model.now))).font(.footnote).foregroundStyle(D.muted)
                    Text(left > 0 ? L.f("home.left", left) : L.t("home.due"))
                        .font(.system(size: 28, weight: .heavy))
                        .foregroundStyle(D.coral)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("home.out")
    }
}

struct ReactionSheet: View {
    @EnvironmentObject private var model: AppModel
    let ask: ReactionAsk

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L.f("reaction.ask", ask.name)).font(.title3.weight(.bold))
            HStack(spacing: 10) {
                ForEach(Reaction.allCases) { reaction in
                    Button(L.t(reaction.key)) { model.react(reaction) }
                        .buttonStyle(PrimaryButton(filled: reaction == .loved))
                        .accessibilityIdentifier("reaction.\(reaction.rawValue)")
                }
            }
            Button(L.t("reaction.skip")) { model.react(nil) }
                .font(.subheadline).foregroundStyle(D.muted)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityIdentifier("reaction.skip")
        }
        .padding(20)
        .presentationDetents([.height(220)])
    }
}
