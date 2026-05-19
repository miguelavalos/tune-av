enum HomeMoodGenreTagBuilder {
    static func build(visibleDiscoveryTags _: [String]) -> [HomeMoodGenreSuggestion] {
        TuneAVMusicGenreCatalog.visibleTags.map { tag in
            HomeMoodGenreSuggestion(
                tag: tag,
                title: L10n.genreLabel(for: tag).capitalized(with: L10n.locale)
            )
        }
    }
}
