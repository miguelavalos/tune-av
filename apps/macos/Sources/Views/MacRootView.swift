import SwiftUI

enum MacRootSection: String, CaseIterable, Identifiable {
    case home
    case search
    case library
    case music
    case profile
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home:
            L10n.string("tab.home")
        case .search:
            L10n.string("tab.search")
        case .library:
            L10n.string("tab.library")
        case .music:
            L10n.string("tab.music")
        case .profile:
            L10n.string("tab.profile")
        case .settings:
            L10n.string("shell.header.settings")
        }
    }

    var symbol: String {
        switch self {
        case .home:
            "house.fill"
        case .search:
            "magnifyingglass"
        case .library:
            "dot.radiowaves.left.and.right"
        case .music:
            "music.note.list"
        case .profile:
            "person.crop.circle"
        case .settings:
            "gearshape"
        }
    }
}

struct MacRootView: View {
    @EnvironmentObject private var model: TuneAVMacModel

    var body: some View {
        NavigationSplitView {
            List(MacRootSection.allCases, selection: $model.selectedSection) { section in
                Label(section.title, systemImage: section.symbol)
                    .tag(section)
            }
            .listStyle(.sidebar)
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
