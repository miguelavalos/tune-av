import Foundation

extension URL {
    var isSupportedAVAccountBaseURL: Bool {
        guard let scheme = scheme?.lowercased(),
              let host = host?.lowercased(),
              !host.isEmpty else {
            return false
        }

        if scheme == "https" {
            return true
        }

        return scheme == "http" && (host == "localhost" || host == "127.0.0.1" || host == "::1")
    }
}
