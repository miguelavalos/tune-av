import SwiftUI

enum MacRootSection: String, CaseIterable, Identifiable {
    case home
    case library
    case music
    case search
    case profile
    case settings

    var id: String { rawValue }

    static var primarySidebarSections: [MacRootSection] {
        [.home, .library, .music, .search]
    }

    static var footerSidebarSections: [MacRootSection] {
        [.settings, .profile]
    }

    var title: String {
        switch self {
        case .home:
            L10n.string("tab.home")
        case .library:
            L10n.string("tab.library")
        case .music:
            L10n.string("tab.music")
        case .search:
            L10n.string("tab.search")
        case .profile:
            L10n.string("profile.accountScreen.title")
        case .settings:
            L10n.string("profile.settingsScreen.title")
        }
    }

    var symbol: String {
        switch self {
        case .home:
            "house.fill"
        case .library:
            "dot.radiowaves.left.and.right"
        case .music:
            "music.note.list"
        case .search:
            "magnifyingglass"
        case .profile:
            "person.crop.circle.fill"
        case .settings:
            "gearshape.fill"
        }
    }
}

struct MacRootView: View {
    @EnvironmentObject private var model: TuneAVMacModel

    var body: some View {
        NavigationSplitView {
            MacSidebarView(selection: $model.selectedSection)
            .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
        } detail: {
            HStack(spacing: 0) {
                TuneAVTheme.shellBackground
                    .ignoresSafeArea()
                    .overlay {
                        currentScreen
                    }

                Divider()

                MacFullPlayerView(showsCloseButton: false)
                    .frame(width: 420)
                    .background(.regularMaterial)
            }
            .navigationTitle(model.selectedSection.title)
            .toolbar {
                ToolbarItemGroup {
                    Button {
                        model.selectedSection = .search
                    } label: {
                        Label(L10n.string("tab.search"), systemImage: "magnifyingglass")
                    }

                    Button {
                        model.togglePlayback()
                    } label: {
                        Label(model.isPlaying ? L10n.string("player.control.pause") : L10n.string("player.control.play"), systemImage: model.isPlaying ? "pause.fill" : "play.fill")
                    }
                }
            }
        }
        .task {
            await model.loadFeaturedStations()
        }
        .onChange(of: model.selectedSection) { _, _ in
            model.closeStationDetail()
        }
        .alert(L10n.string("app.name"), isPresented: errorIsPresented) {
            Button(L10n.string("common.ok")) {
                model.errorMessage = nil
            }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .alert(upgradePromptTitle, isPresented: upgradePromptIsPresented) {
            Button(L10n.string("limits.upgrade.notNow")) {
                model.upgradePrompt = nil
            }
            Button(L10n.string("limits.upgrade.profile")) {
                model.upgradePrompt = nil
                model.selectedSection = .profile
            }
        } message: {
            Text(model.upgradePrompt?.message ?? "")
        }
    }

    @ViewBuilder
    private var currentScreen: some View {
        if let route = model.stationDetailRoute {
            MacStationDetailView(
                station: route.station,
                queue: route.queue,
                initialSection: route.showsHistory ? .history : .about
            )
            .id(route.id)
        } else if let route = model.musicDetailRoute {
            MacMusicDetailView(route: route)
        } else if let route = model.homeStationListRoute {
            MacHomeStationListPage(route: route)
        } else {
            switch model.selectedSection {
            case .home:
                MacHomeView(openSearchTag: { tag in
                    model.selectedSection = .search
                    Task { await model.search(tag: tag) }
                })
            case .search:
                MacSearchView()
            case .library:
                MacLibraryView()
            case .music:
                MacMusicView()
            case .profile:
                MacProfileView()
            case .settings:
                MacSettingsView()
            }
        }
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )
    }

    private var upgradePromptIsPresented: Binding<Bool> {
        Binding(
            get: { model.upgradePrompt != nil },
            set: { if !$0 { model.upgradePrompt = nil } }
        )
    }

    private var upgradePromptTitle: String {
        model.upgradePrompt?.title ?? L10n.string("limits.upgrade.eyebrow")
    }
}

private struct MacSidebarView: View {
    @Binding var selection: MacRootSection

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image("HeaderWordmark")
                    .renderingMode(.original)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 138, height: 44, alignment: .leading)
                    .accessibilityLabel(L10n.string("app.name"))

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.bottom, 12)

            ForEach(MacRootSection.primarySidebarSections) { section in
                MacSidebarButton(
                    section: section,
                    isSelected: selection == section
                ) {
                    selection = section
                }
            }

            Spacer(minLength: 16)

            ForEach(MacRootSection.footerSidebarSections) { section in
                MacSidebarButton(
                    section: section,
                    isSelected: selection == section
                ) {
                    selection = section
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial)
        .accessibilityIdentifier("tune.shell.mac.sidebar")
    }
}

private struct MacSidebarButton: View {
    let section: MacRootSection
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Label {
                Text(section.title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } icon: {
                Image(systemName: section.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 20)
            }
            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(buttonBackground, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel(section.title)
        .accessibilityIdentifier("tune.sidebar.\(section.rawValue)")
    }

    private var buttonBackground: some ShapeStyle {
        if isSelected {
            return AnyShapeStyle(Color.primary.opacity(0.10))
        }
        if isHovered {
            return AnyShapeStyle(Color.primary.opacity(0.06))
        }
        return AnyShapeStyle(Color.clear)
    }
}
