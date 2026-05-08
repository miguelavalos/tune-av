import Foundation

extension URL {
    var isSupportedAVAccountBaseURL: Bool {
        guard let scheme = scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              host?.isEmpty == false else {
            return false
        }
        return true
    }
}
