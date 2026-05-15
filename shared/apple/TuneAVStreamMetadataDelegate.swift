@preconcurrency import AVFoundation
import Foundation

struct TuneAVStreamMetadataEvent: Sendable {
    let value: String
    let commonKey: String
    let identifier: String
}

final class TuneAVStreamMetadataDelegate: NSObject, AVPlayerItemMetadataOutputPushDelegate {
    private let handler: @Sendable ([TuneAVStreamMetadataEvent]) async -> Void
    private let signatureCache = TuneAVStreamMetadataSignatureCache()

    init(handler: @escaping @Sendable ([TuneAVStreamMetadataEvent]) async -> Void) {
        self.handler = handler
    }

    func metadataOutput(
        _ output: AVPlayerItemMetadataOutput,
        didOutputTimedMetadataGroups groups: [AVTimedMetadataGroup],
        from track: AVPlayerItemTrack?
    ) {
        let metadataItems = TuneAVMetadataItemsBox(groups.flatMap(\.items))
        guard !metadataItems.items.isEmpty else { return }

        Task { [handler, metadataItems] in
            var events: [TuneAVStreamMetadataEvent] = []
            events.reserveCapacity(metadataItems.items.count)

            for item in metadataItems.items {
                let value = try? await item.load(.stringValue)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard let value, !value.isEmpty else { continue }

                events.append(
                    TuneAVStreamMetadataEvent(
                        value: value,
                        commonKey: item.commonKey?.rawValue.lowercased() ?? "",
                        identifier: item.identifier?.rawValue.lowercased() ?? ""
                    )
                )
            }

            guard !events.isEmpty else { return }
            let signature = TuneAVStreamMetadataDelegate.signature(for: events)
            guard signatureCache.rememberIfChanged(signature) else { return }
            await handler(events)
        }
    }

    private static func signature(for events: [TuneAVStreamMetadataEvent]) -> String {
        events
            .map { "\($0.commonKey)\u{1F}\($0.identifier)\u{1F}\($0.value)" }
            .joined(separator: "\u{1E}")
    }
}

private final class TuneAVStreamMetadataSignatureCache: @unchecked Sendable {
    private let lock = NSLock()
    private var lastSignature: String?

    func rememberIfChanged(_ signature: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard signature != lastSignature else { return false }
        lastSignature = signature
        return true
    }
}

private final class TuneAVMetadataItemsBox: @unchecked Sendable {
    let items: [AVMetadataItem]

    init(_ items: [AVMetadataItem]) {
        self.items = items
    }
}
