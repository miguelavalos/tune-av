import SwiftUI

extension View {
    func appShellGlobalPresentations(
        isShowingFooterArtworkZoom: Binding<Bool>,
        currentStation: Station?,
        currentTrackArtworkURL: URL?,
        currentTrackTitle: String?,
        currentTrackArtist: String?,
        upgradePrompt: Binding<UpgradePrompt?>,
        isGuest: Bool,
        accountIsAvailable: Bool,
        accessController: AccessController,
        showProPaywall: Binding<Bool>,
        pendingCellularPlayback: Binding<AppShellView.PendingPlayback?>,
        isConfirmingStopPlayback: Binding<Bool>,
        startSignInFlow: @escaping () -> Void,
        playPendingCellularPlayback: @escaping (AppShellView.PendingPlayback) -> Void,
        stopPlayback: @escaping () -> Void
    ) -> some View {
        modifier(
            AppShellGlobalPresentations(
                isShowingFooterArtworkZoom: isShowingFooterArtworkZoom,
                currentStation: currentStation,
                currentTrackArtworkURL: currentTrackArtworkURL,
                currentTrackTitle: currentTrackTitle,
                currentTrackArtist: currentTrackArtist,
                upgradePrompt: upgradePrompt,
                isGuest: isGuest,
                accountIsAvailable: accountIsAvailable,
                accessController: accessController,
                showProPaywall: showProPaywall,
                pendingCellularPlayback: pendingCellularPlayback,
                isConfirmingStopPlayback: isConfirmingStopPlayback,
                startSignInFlow: startSignInFlow,
                playPendingCellularPlayback: playPendingCellularPlayback,
                stopPlayback: stopPlayback
            )
        )
    }
}

private struct AppShellGlobalPresentations: ViewModifier {
    @Binding var isShowingFooterArtworkZoom: Bool
    let currentStation: Station?
    let currentTrackArtworkURL: URL?
    let currentTrackTitle: String?
    let currentTrackArtist: String?
    @Binding var upgradePrompt: UpgradePrompt?
    let isGuest: Bool
    let accountIsAvailable: Bool
    let accessController: AccessController
    @Binding var showProPaywall: Bool
    @Binding var pendingCellularPlayback: AppShellView.PendingPlayback?
    @Binding var isConfirmingStopPlayback: Bool
    let startSignInFlow: () -> Void
    let playPendingCellularPlayback: (AppShellView.PendingPlayback) -> Void
    let stopPlayback: () -> Void

    func body(content: Content) -> some View {
        content
            .overlay {
                if isShowingFooterArtworkZoom, let currentStation {
                    AppShellArtworkZoomOverlay(
                        station: currentStation,
                        artworkURL: currentTrackArtworkURL ?? currentStation.displayArtworkURL,
                        title: currentTrackTitle ?? currentStation.name,
                        subtitle: currentTrackArtist ?? currentStation.name
                    ) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                            isShowingFooterArtworkZoom = false
                        }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .zIndex(30)
                }
            }
            .sheet(item: $upgradePrompt) { prompt in
                UpgradeRecommendationSheet(
                    prompt: prompt,
                    isGuest: isGuest,
                    accountIsAvailable: accountIsAvailable,
                    onPrimaryAction: {
                        upgradePrompt = nil
                        if isGuest {
                            startSignInFlow()
                        } else {
                            showProPaywall = true
                        }
                    },
                    onDismiss: {
                        upgradePrompt = nil
                    }
                )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showProPaywall) {
                TuneAVProPaywallView(startSignInFlow: startSignInFlow)
                    .environmentObject(accessController)
            }
            .alert(L10n.string("settings.cellularPlayback.alert.title"), isPresented: pendingCellularPlaybackIsPresented) {
                Button(L10n.string("common.cancel"), role: .cancel) {
                    pendingCellularPlayback = nil
                }
                Button(L10n.string("settings.cellularPlayback.alert.play")) {
                    if let pendingCellularPlayback {
                        playPendingCellularPlayback(pendingCellularPlayback)
                    }
                    pendingCellularPlayback = nil
                }
            } message: {
                Text(L10n.string("settings.cellularPlayback.alert.message"))
            }
            .alert(L10n.string("player.stopPlayback.alert.title"), isPresented: $isConfirmingStopPlayback) {
                Button(L10n.string("common.cancel"), role: .cancel) {}
                Button(L10n.string("player.stopPlayback.alert.stop"), role: .destructive) {
                    stopPlayback()
                }
            } message: {
                Text(L10n.string("player.stopPlayback.alert.message"))
            }
    }

    private var pendingCellularPlaybackIsPresented: Binding<Bool> {
        Binding(
            get: { pendingCellularPlayback != nil },
            set: { if !$0 { pendingCellularPlayback = nil } }
        )
    }
}
