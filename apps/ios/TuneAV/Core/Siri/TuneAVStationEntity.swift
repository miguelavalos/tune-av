import AppIntents
import Foundation

struct TuneAVStationEntity: AppEntity, Identifiable, Hashable, Sendable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "widget.intent.station")
    static let defaultQuery = TuneAVStationEntityQuery()

    let id: String
    let name: String

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    init(station: Station) {
        self.init(id: station.id, name: TuneAVSiriStationCatalog.displayName(for: station))
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            image: DisplayRepresentation.Image(systemName: "radio")
        )
    }
}

struct TuneAVStationEntityQuery: EntityStringQuery {
    init() {}

    func entities(for identifiers: [TuneAVStationEntity.ID]) async throws -> [TuneAVStationEntity] {
        await MainActor.run {
            identifiers.compactMap { id in
                TuneAVWidgetController.shared.siriStation(id: id).map(TuneAVStationEntity.init(station:))
            }
        }
    }

    func entities(matching string: String) async throws -> [TuneAVStationEntity] {
        await MainActor.run {
            TuneAVSiriStationCatalog
                .matching(string, in: TuneAVWidgetController.shared.siriStations())
                .map(TuneAVStationEntity.init(station:))
        }
    }

    func suggestedEntities() async throws -> [TuneAVStationEntity] {
        await MainActor.run {
            TuneAVWidgetController.shared.siriStations().map(TuneAVStationEntity.init(station:))
        }
    }
}
