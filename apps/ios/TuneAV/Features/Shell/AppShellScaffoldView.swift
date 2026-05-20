import SwiftUI

struct AppShellScaffold<Content: View, FooterPlayer: View>: View {
    let selectedTab: AppShellTab
    let hasFooterPlayer: Bool
    let hasAviActiveContext: Bool
    let footerBackdropHeight: CGFloat
    let footerPlayerTabSpacing: CGFloat
    let searchAction: () -> Void
    let aviAction: () -> Void
    let selectTab: (AppShellTab) -> Void
    @ViewBuilder let content: () -> Content
    @ViewBuilder let footerPlayer: () -> FooterPlayer

    @Namespace private var footerSelectionAnimation

    var body: some View {
        ZStack {
            TuneAVTheme.shellBackground.ignoresSafeArea()

            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay(alignment: .bottom) {
            footer
        }
    }

    private var footer: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                colors: [
                    TuneAVTheme.footerBackdrop.opacity(0),
                    TuneAVTheme.footerBackdrop.opacity(0.94),
                    TuneAVTheme.footerBackdrop
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: footerBackdropHeight)
            .allowsHitTesting(false)

            VStack(spacing: footerPlayerTabSpacing) {
                footerPlayer()

                HStack(spacing: 18) {
                    HStack {
                        AppShellFooterTabButton(
                            title: L10n.string("tab.home"),
                            systemImage: "house.fill",
                            isSelected: selectedTab == .home,
                            selectionNamespace: footerSelectionAnimation,
                            accessibilityIdentifier: "tab.home"
                        ) {
                            selectTab(.home)
                        }

                        AppShellFooterTabButton(
                            title: L10n.string("tab.library"),
                            systemImage: "dot.radiowaves.left.and.right",
                            isSelected: selectedTab == .library,
                            selectionNamespace: footerSelectionAnimation,
                            accessibilityIdentifier: "tab.library"
                        ) {
                            selectTab(.library)
                        }

                        AppShellFooterTabButton(
                            title: L10n.string("tab.music"),
                            systemImage: "music.note.list",
                            isSelected: selectedTab == .music,
                            selectionNamespace: footerSelectionAnimation,
                            accessibilityIdentifier: "tab.music"
                        ) {
                            selectTab(.music)
                        }

                        AppShellFooterTabButton(
                            title: L10n.string("tab.search"),
                            systemImage: "magnifyingglass",
                            isSelected: selectedTab == .search,
                            selectionNamespace: footerSelectionAnimation,
                            accessibilityIdentifier: "tab.search"
                        ) {
                            searchAction()
                        }
                    }
                    .padding(.leading, 10)
                    .padding(.trailing, 10)
                    .padding(.vertical, 7)
                    .background {
                        Capsule(style: .continuous)
                            .fill(TuneAVTheme.footerGlass)
                            .background(.ultraThinMaterial.opacity(0.95), in: Capsule(style: .continuous))
                            .overlay {
                                Capsule(style: .continuous)
                                    .stroke(TuneAVTheme.glassStroke, lineWidth: 1)
                            }
                        }
                    .shadow(color: TuneAVTheme.glassShadow, radius: 18, y: 10)

                    AppShellFooterAviButton(
                        isSelected: selectedTab == .avi,
                        hasActiveContext: hasAviActiveContext
                    ) {
                        aviAction()
                    }
                    .shadow(color: TuneAVTheme.glassShadow, radius: 18, y: 10)
                }
                .frame(maxWidth: 430)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, -8)
        }
        .ignoresSafeArea(edges: .bottom)
    }
}

private struct AppShellFooterTabButton: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let selectionNamespace: Namespace.ID
    let accessibilityIdentifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if isSelected {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(TuneAVTheme.footerGlassSelected)
                        .matchedGeometryEffect(id: "footerSelection", in: selectionNamespace)
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(TuneAVTheme.glassStroke, lineWidth: 0.8)
                        }
                }

                Image(systemName: displayedSystemImage)
                    .font(.system(size: 20, weight: isSelected ? .semibold : .regular))
                    .frame(width: 20, height: 20)
                    .symbolRenderingMode(.monochrome)
            }
            .foregroundStyle(isSelected ? TuneAVTheme.highlight : TuneAVTheme.textSecondary)
            .frame(width: 64, height: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var displayedSystemImage: String {
        guard !isSelected else { return systemImage }
        return systemImage.replacingOccurrences(of: ".fill", with: "")
    }
}

private struct AppShellFooterAviButton: View {
    let isSelected: Bool
    let hasActiveContext: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(TuneAVTheme.footerGlass)
                    .background(.ultraThinMaterial.opacity(0.95), in: Circle())
                    .overlay {
                        Circle()
                            .stroke(TuneAVTheme.glassStroke, lineWidth: 1)
                    }

                if isSelected {
                    Circle()
                        .fill(TuneAVTheme.footerGlassSelected)
                        .padding(4)

                    Circle()
                        .fill(TuneAVTheme.highlight.opacity(0.14))
                        .padding(9)
                }

                Image("AviFooterIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: isSelected ? 42 : 40, height: isSelected ? 32 : 30)
                    .opacity(isSelected ? 1 : 0.84)
                    .saturation(isSelected ? 1.06 : 0.82)
                    .padding(8)
                    .shadow(color: TuneAVTheme.highlight.opacity(isSelected ? 0.24 : 0), radius: 6, y: 2)

                if hasActiveContext && !isSelected {
                    Image(systemName: "waveform")
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(TuneAVTheme.highlight)
                        .frame(width: 20, height: 20)
                        .background(TuneAVTheme.cardSurface, in: Circle())
                        .overlay {
                            Circle()
                                .stroke(TuneAVTheme.highlight.opacity(0.32), lineWidth: 1)
                        }
                        .shadow(color: TuneAVTheme.highlight.opacity(0.18), radius: 4, y: 2)
                        .offset(x: 20, y: -18)
                }
            }
            .frame(width: 62, height: 62)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.string("shell.avi.title"))
        .accessibilityIdentifier("tab.avi")
    }
}
