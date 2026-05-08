@preconcurrency import AVFoundation
import Foundation

struct TuneAVStreamMetadataEvent: Sendable {
    let value: String
    let commonKey: String
    let identifier: String
}

final class TuneAVStreamMetadataDelegate: NSObject, AVPlayerItemMetadataOutputPushDelegate {
    private let handler: @Sendable ([TuneAVStreamMetadataEvent]) async -> Void

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
            await handler(events)
        }
    }
}

private final class TuneAVMetadataItemsBox: @unchecked Sendable {
    let items: [AVMetadataItem]

    init(_ items: [AVMetadataItem]) {
        self.items = items
    }
}
