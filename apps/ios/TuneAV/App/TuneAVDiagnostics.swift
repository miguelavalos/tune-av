import AVDiagnosticsFoundation
import Foundation

enum TuneAVDiagnostics {
    static func addBreadcrumb(feature: String, operation: String, data: [String: String] = [:]) {
        var breadcrumbData = data
        breadcrumbData["operation"] = operation
        AVDiagnostics.addBreadcrumb(AVDiagnosticsBreadcrumb(
            category: feature,
            message: "\(feature).\(operation)",
            data: breadcrumbData
        ))
    }

    static func capture(
        _ error: any Error,
        feature: String,
        operation: String,
        step: String,
        data: [String: String] = [:]
    ) {
        guard shouldCapture(error) else { return }

        var contextData = data
        contextData["operation"] = operation
        contextData["step"] = step
        AVDiagnostics.capture(
            error: error,
            context: AVDiagnosticsContext(
                feature: feature,
                code: errorCode(for: error),
                data: contextData
            )
        )
    }

    static func setUserContext(id: String?) {
        guard let id, !id.isEmpty else {
            AVDiagnostics.clearUserContext()
            return
        }
        AVDiagnostics.setUserContext(AVDiagnosticsUserContext(id: id))
    }

    static func clearUserContext() {
        AVDiagnostics.clearUserContext()
    }

    static func shouldCapture(_ error: any Error) -> Bool {
        if error is CancellationError {
            return false
        }

        if let urlError = error as? URLError {
            return shouldCaptureURLCode(urlError.code)
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return shouldCaptureURLCode(URLError.Code(rawValue: nsError.code))
        }

        if let accountError = error as? AVAccountAPIClientError {
            switch accountError {
            case .missingToken, .missingBaseURL:
                return false
            case .requestFailed:
                return true
            }
        }

        if let promoCodeError = error as? TuneAVPromoCodeClientError,
           case .server("promo_code_unavailable", _, 404) = promoCodeError {
            return false
        }

        return true
    }

    private static func errorCode(for error: any Error) -> String {
        if let urlError = error as? URLError {
            return urlErrorCode(urlError.code)
        }
        if let accountError = error as? AVAccountAPIClientError {
            switch accountError {
            case .missingToken:
                return "missing_token"
            case .missingBaseURL:
                return "missing_base_url"
            case .requestFailed(let statusCode, _):
                return "request_failed_\(statusCode)"
            }
        }
        if let subscriptionError = error as? TuneAVSubscriptionPurchaseError {
            return String(describing: subscriptionError)
        }
        if let profileError = error as? AccountProfileResolverError {
            return String(describing: profileError)
        }
        let nsError = error as NSError
        return "\(nsError.domain):\(nsError.code)"
    }

    private static func urlErrorCode(_ code: URLError.Code) -> String {
        switch code {
        case .timedOut:
            return "timed_out"
        case .cannotFindHost:
            return "cannot_find_host"
        case .cannotConnectToHost:
            return "cannot_connect_to_host"
        case .networkConnectionLost:
            return "network_connection_lost"
        case .dnsLookupFailed:
            return "dns_lookup_failed"
        case .notConnectedToInternet:
            return "not_connected_to_internet"
        case .badServerResponse:
            return "bad_server_response"
        default:
            return "url_error_\(code.rawValue)"
        }
    }

    private static func shouldCaptureURLCode(_ code: URLError.Code) -> Bool {
        switch code {
        case .cancelled,
             .networkConnectionLost,
             .notConnectedToInternet:
            return false
        default:
            return true
        }
    }
}
