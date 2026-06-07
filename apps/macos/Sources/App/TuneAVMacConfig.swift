import AVDiagnosticsFoundation
import Foundation

@MainActor
enum TuneAVMacConfig {
    static var diagnosticsConfiguration: AVDiagnosticsConfiguration {
        AVDiagnosticsConfiguration(
            dsn: TuneAVBundleConfig.stringValue(for: "TUNEAV_MACOS_SENTRY_DSN"),
            environment: diagnosticsEnvironment,
            releaseName: diagnosticsReleaseName,
            tracesSampleRate: 0,
            isEnabled: isDiagnosticsEnabled
        )
    }

    static var tuneConvexURL: String {
        TuneAVBundleConfig.stringValue(for: "TUNEAV_CONVEX_URL")
    }

    private static var diagnosticsEnvironment: AVDiagnosticsEnvironment {
        switch TuneAVBundleConfig.stringValue(for: "TUNEAV_CONFIG_ENVIRONMENT").lowercased() {
        case "prod", "production":
            return .production
        case "staging", "preview":
            return .preview
        case "dev", "debug":
            return .debug
        default:
            return .debug
        }
    }

    private static var diagnosticsReleaseName: String? {
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.avalsys.tuneav.mac"
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(bundleIdentifier)@\(version)+\(build)"
    }

    private static var isDiagnosticsEnabled: Bool {
        #if DEBUG
        false
        #else
        !TuneAVBundleConfig.stringValue(for: "TUNEAV_MACOS_SENTRY_DSN").isEmpty
        #endif
    }
}
