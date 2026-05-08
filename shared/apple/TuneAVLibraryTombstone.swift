import Foundation

struct TuneAVLibraryTombstone: Codable, Equatable {
    let resource: String
    let identityKey: String
    var payloadJSON: String
    var deletedAt: Date

    init(resource: String, identityKey: String, payloadJSON: String, deletedAt: Date = .now) {
        self.resource = resource
        self.identityKey = identityKey
        self.payloadJSON = payloadJSON
        self.deletedAt = deletedAt
    }

    var resourceKey: String {
        Self.resourceKey(resource: resource, identityKey: identityKey)
    }

    static func resourceKey(resource: String, identityKey: String) -> String {
        "\(resource):\(identityKey)"
    }
}

enum TuneAVLibraryTombstoneCoding {
    static func payloadJSON<Payload: Encodable>(
        for payload: Payload,
        encoder: JSONEncoder = JSONEncoder()
    ) -> String? {
        guard let data = try? encoder.encode(payload) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func decodePayload<Record: Decodable>(
        _ type: Record.Type,
        from payloadJSON: String,
        decoder: JSONDecoder = JSONDecoder()
    ) -> Record? {
        guard let data = payloadJSON.data(using: .utf8) else { return nil }
        return try? decoder.decode(Record.self, from: data)
    }

    static func upserting<Payload: Encodable>(
        resource: String,
        identityKey: String,
        payload: Payload,
        deletedAt: Date,
        into tombstones: [TuneAVLibraryTombstone],
        encoder: JSONEncoder = JSONEncoder()
    ) -> [TuneAVLibraryTombstone] {
        guard let payloadJSON = payloadJSON(for: payload, encoder: encoder) else {
            return tombstones
        }

        let resourceKey = TuneAVLibraryTombstone.resourceKey(resource: resource, identityKey: identityKey)
        var next = tombstones
        if let index = next.firstIndex(where: { $0.resourceKey == resourceKey }) {
            next[index].payloadJSON = payloadJSON
            next[index].deletedAt = deletedAt
        } else {
            next.append(
                TuneAVLibraryTombstone(
                    resource: resource,
                    identityKey: identityKey,
                    payloadJSON: payloadJSON,
                    deletedAt: deletedAt
                )
            )
        }
        return next
    }

    static func records<Record: Decodable>(
        for resource: String,
        in tombstones: [TuneAVLibraryTombstone],
        as type: Record.Type,
        decoder: JSONDecoder = JSONDecoder()
    ) -> [Record] {
        tombstones
            .filter { $0.resource == resource }
            .compactMap { decodePayload(type, from: $0.payloadJSON, decoder: decoder) }
    }
}
