import Foundation

extension TuneAVProLibraryObserver {
    convenience init() {
        self.init(deploymentURL: AppConfig.tuneConvexURL)
    }
}
