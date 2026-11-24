import StoreKit
import SwiftUI

@main
struct ToyRotationApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .tint(D.coral)
                .preferredColorScheme(.light)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.requestReview) private var requestReview
    @Environment(\.scenePhase) private var scenePhase

    private var reviewHome: Bool {
        model.path.isEmpty && model.sheet == nil && model.asking == nil && model.activity == nil && !model.addingBin
            && model.toast == nil && !model.presentingSwapMilestone && !model.purchases.busy && !model.testing
    }

    var body: some View {
        NavigationStack(path: $model.path) {
            HomeView()
                .navigationDestination(for: UUID.self) { id in BinView(id: id) }
        }
        .foregroundStyle(D.ink)
        .task { await model.start() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                model.becameActive()
                Task { await model.purchases.refresh() }
            }
        }
        .reviewAfterCoreAction(when: reviewHome) { requestReview() }
        .task(id: reviewHome && model.reviewSignal > 0 && scenePhase == .active) {
            guard reviewHome, model.reviewSignal > 0, scenePhase == .active else { return }
            do { try await Task.sleep(for: .milliseconds(800)) } catch { return }
            guard !Task.isCancelled, reviewHome else { return }
            model.requestSwapReview { requestReview() }
        }
        .onReceive(model.purchases.objectWillChange) { _ in model.objectWillChange.send() }
        .sheet(item: $model.sheet) { sheet in
            switch sheet {
            case .settings: SettingsView()
            case .paywall: PaywallView(purchases: model.purchases)
            case .milestone(let value): MilestoneView(value: value)
            case .share: SharePreview()
            }
        }
        .sheet(item: $model.asking, onDismiss: { model.react(nil) }) { ask in ReactionSheet(ask: ask) }
        .sheet(item: $model.activity) { share in
            ActivitySheet(items: share.items).presentationDetents([.medium, .large])
        }
        .fullScreenCover(isPresented: $model.addingBin) {
            if model.testing {
                Color.clear.onAppear {
                    model.addBin(photo: UIImage(data: Fixtures.draw((.systemTeal, .systemIndigo), seed: model.data.bins.count)))
                }
            } else {
                CameraPicker { image in model.addBin(photo: image) }.ignoresSafeArea()
            }
        }
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
                Text(toast)
                    .font(.footnote.weight(.semibold))
                    .padding(.vertical, 10).padding(.horizontal, 16)
                    .background(D.ink.opacity(0.9), in: Capsule())
                    .foregroundStyle(.white)
                    .padding(.bottom, 20)
                    .accessibilityIdentifier("toast")
            }
        }
    }
}
