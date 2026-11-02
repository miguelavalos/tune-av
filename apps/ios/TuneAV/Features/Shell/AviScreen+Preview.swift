import AVAviFoundation
import AVAppShellFoundation
import AVExternalLinkFoundation
import AVHaptics
import OSLog
import SwiftUI
import UIKit

extension AviScreen {
    var aviPreviewContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            aviPreviewHero
            aviPreviewCurrentContext
            aviPromptSuggestions
            aviPreviewActions
            aviPreviewCapabilities
        }
        .padding(.bottom, 96)
        .accessibilityIdentifier("avi.preview")
    }

    var aviPreviewLandingContent: AVAviLandingContent {
        AVAviLandingContent(
            eyebrow: L10n.string("shell.avi.preview.eyebrow"),
            title: L10n.string("shell.avi.preview.title"),
            detail: L10n.string("shell.avi.preview.detail"),
            chips: [
                AVAviLandingChip(title: L10n.string("shell.avi.preview.chip.listen"), systemImage: "waveform"),
                AVAviLandingChip(title: L10n.string("shell.avi.preview.chip.save"), systemImage: "bookmark"),
                AVAviLandingChip(title: L10n.string("shell.avi.preview.chip.search"), systemImage: "magnifyingglass")
            ],
            accessibilityIdentifier: "avi.preview.hero"
        )
    }

    var aviPreviewHero: some View {
        AVAviLandingHeroCard(content: aviPreviewLandingContent) {
            aviHeroImage(width: 62)
        }
    }

    var aviPreviewCurrentContext: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L10n.string("shell.avi.preview.current"))
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(TuneAVTheme.highlight)
                    .textCase(.uppercase)

                Spacer(minLength: 0)

                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(TuneAVTheme.highlight)
            }

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: currentStation == nil ? "sparkles" : "waveform")
                    .font(.system(size: 17, weight: .black))
                    .foregroundStyle(TuneAVTheme.highlight)
                    .frame(width: 38, height: 38)
                    .background(TuneAVTheme.highlight.opacity(0.1), in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(aviPreviewContextTitle)
                        .font(.system(size: 17, weight: .black, design: .rounded))
                        .foregroundStyle(TuneAVTheme.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)

                    Text(aviPreviewContextDetail)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(TuneAVTheme.textSecondary)
                        .lineSpacing(1)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .background(TuneAVTheme.cardSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(TuneAVTheme.highlight.opacity(0.18), lineWidth: 1)
        }
    }

    var aviPromptSuggestions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.string(currentStation == nil ? "shell.avi.preview.steps" : "shell.avi.preview.prompts"))
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(TuneAVTheme.textPrimary)
                .textCase(.uppercase)

            VStack(spacing: 8) {
                if currentStation == nil {
                    AVAviPreviewStep(index: 1, title: L10n.string("shell.avi.preview.step.choose"))
                    AVAviPreviewStep(index: 2, title: L10n.string("shell.avi.preview.step.listen"))
                    AVAviPreviewStep(index: 3, title: L10n.string("shell.avi.preview.step.remember"))
                } else if let currentStation {
                    HStack(spacing: 8) {
                        AVAviPromptButton(
                            title: L10n.string("shell.avi.preview.prompt.saveStation"),
                            systemImage: "bookmark",
                            action: {
                                toggleFavorite(currentStation)
                            }
                        )
                        AVAviPromptButton(
                            title: L10n.string("shell.avi.preview.prompt.history"),
                            systemImage: "clock.arrow.circlepath",
                            action: { showStationDetails(currentStation, [currentStation], .history) }
                        )
                    }
                }
            }
        }
        .padding(14)
        .background(TuneAVTheme.cardSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(TuneAVTheme.borderSubtle.opacity(0.5), lineWidth: 1)
        }
    }

    var aviPreviewCapabilities: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(L10n.string("shell.avi.preview.capabilities"))
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(TuneAVTheme.textPrimary)
                .textCase(.uppercase)

            AVAviPreviewCapabilityRow(systemImage: "text.quote", title: L10n.string("shell.avi.preview.music.title"), detail: L10n.string("shell.avi.preview.music.detail"))
            Divider().overlay(TuneAVTheme.borderSubtle.opacity(0.45))
            AVAviPreviewCapabilityRow(systemImage: "dot.radiowaves.left.and.right", title: L10n.string("shell.avi.preview.radio.title"), detail: L10n.string("shell.avi.preview.radio.detail"))
            Divider().overlay(TuneAVTheme.borderSubtle.opacity(0.45))
            AVAviPreviewCapabilityRow(systemImage: "sparkles", title: L10n.string("shell.avi.preview.recommendations.title"), detail: L10n.string("shell.avi.preview.recommendations.detail"))
        }
        .padding(14)
        .background(TuneAVTheme.cardSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(TuneAVTheme.borderSubtle.opacity(0.5), lineWidth: 1)
        }
    }

    var aviPreviewActions: some View {
        VStack(spacing: 12) {
            AVAviPreviewPrimaryButton(
                title: primaryAviPreviewTitle,
                systemImage: primaryAviPreviewSystemImage,
                accessibilityIdentifier: "avi.preview.primary",
                action: primaryAviPreviewAction
            )

            HStack(spacing: 10) {
                AVAviPreviewSecondaryButton(
                    title: L10n.string("shell.avi.preview.compare"),
                    systemImage: "rectangle.3.group",
                    accessibilityIdentifier: "avi.preview.compare"
                ) {
                    isShowingPlanComparison = true
                }

                if currentStation != nil || currentTrackTitle != nil {
                    AVAviPreviewSecondaryButton(
                        title: L10n.string("shell.avi.preview.search"),
                        systemImage: "magnifyingglass",
                        accessibilityIdentifier: "avi.preview.search",
                        action: openSearch
                    )
                }
            }
        }
    }

    var primaryAviPreviewTitle: String {
        if currentStation != nil || currentTrackTitle != nil {
            return L10n.string("shell.avi.preview.primary.nowPlaying")
        }
        return L10n.string("shell.avi.preview.primary.search")
    }

    var primaryAviPreviewSystemImage: String {
        if currentStation != nil || currentTrackTitle != nil {
            return "waveform"
        }
        return "magnifyingglass"
    }

    var aviPreviewContextTitle: String {
        if let currentTrackTitle, let currentTrackArtist {
            return "\(currentTrackTitle) - \(currentTrackArtist)"
        }
        if let currentStation {
            return currentStation.name
        }
        return L10n.string("shell.avi.preview.emptyTitle")
    }

    var aviPreviewContextDetail: String {
        if currentTrackTitle != nil {
            return L10n.string("shell.avi.preview.songDetail")
        }
        if currentStation != nil {
            return L10n.string("shell.avi.preview.radioDetail")
        }
        return L10n.string("shell.avi.preview.emptyDetail")
    }

    func primaryAviPreviewAction() {
        if currentStation != nil || currentTrackTitle != nil {
            openPlayer()
        } else {
            openSearch()
        }
    }
}
