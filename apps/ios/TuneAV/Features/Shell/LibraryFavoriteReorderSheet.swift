import AVHaptics
import SwiftUI

/// The listener's order of saved radios: a list that is always in edit mode, so every row shows
/// its drag handle and a drag is the only gesture. Each move is saved as it happens (device-local,
/// see `LibraryStore.moveFavorites`); Done only closes the sheet.
struct LibraryFavoriteReorderSheet: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let stations: [Station]
    let moveStations: (IndexSet, Int) -> Void
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(stations, id: \.id) { station in
                        row(station)
                    }
                    .onMove { source, destination in
                        AVHaptics.perform(.step)
                        moveStations(source, destination)
                    }
                } footer: {
                    Text(L10n.string("shell.library.reorder.hint"))
                }
            }
            .environment(\.editMode, .constant(.active))
            .animation(reduceMotion ? nil : .default, value: stations.map(\.id))
            .navigationTitle(L10n.string("shell.library.reorder.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.string("common.done"), action: onDismiss)
                        .accessibilityIdentifier("library.reorder.done")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationContentInteraction(.scrolls)
    }

    private func row(_ station: Station) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(station.name)
                .tuneScaledFont(size: 15, weight: .black)
                .foregroundStyle(TuneAVTheme.textPrimary)
                .lineLimit(2)

            Text(station.primaryDetailLine)
                .tuneScaledFont(size: 12, weight: .semibold)
                .foregroundStyle(TuneAVTheme.textSecondary)
                .lineLimit(1)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("library.reorder.row.\(station.id)")
    }
}
