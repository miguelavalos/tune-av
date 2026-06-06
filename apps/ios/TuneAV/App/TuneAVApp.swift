import AVDiagnosticsFoundation
import AVBrandFoundation
import SwiftData
import SwiftUI

@main
struct TuneAVApp: App {
    private let launchContext: LaunchContext
    private let persistenceController: PersistenceController
    @StateObject private var audioPlayer = AudioPlayerService()
    @StateObject private var languageController = AppLanguageController()
    @StateObject private var themeController = AppThemeController()
    @StateObject private var libraryStore: LibraryStore
    @StateObject private var accessController: AccessController

    init() {
        let launchContext = LaunchContext.current
        self.launchContext = launchContext
        AppConfig.configureAVAccountIfPossible()
        AVDiagnostics.configure(AppConfig.diagnosticsConfiguration)
        let persistenceController = launchContext.isUITesting ? PersistenceController(inMemory: true) : PersistenceController.shared
        self.persistenceController = persistenceController
        _libraryStore = StateObject(wrappedValue: LibraryStore(container: persistenceController.container))
        _accessController = StateObject(
            wrappedValue: AccessController(
                subscriptionPurchasing: TuneAVUITestEnvironment.current.shouldUseSubscriptionPurchasingStub
                    ? UITestTuneAVSubscriptionPurchasing()
                    : RevenueCatTuneAVSubscriptionPurchasing()
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            Group {
                RootView()
                    .environmentObject(accessController)
                    .environmentObject(languageController)
                    .environmentObject(themeController)
                    .environment(\.locale, languageController.locale)
                    .environmentObject(audioPlayer)
                    .environmentObject(libraryStore)
                    .avCommonAppExperience(TuneAppExperience.experience)
                    .preferredColorScheme(themeController.currentTheme.preferredColorScheme)
            }
        }
        .modelContainer(persistenceController.container)
    }
}
