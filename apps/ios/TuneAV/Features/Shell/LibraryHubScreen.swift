import SwiftUI

struct LibraryHubScreen<Radios: View, Songs: View>: View {
    @Binding var segment: LibrarySegment
    @ViewBuilder let radios: () -> Radios
    @ViewBuilder let songs: () -> Songs

    var body: some View {
        TuneAdaptiveLayoutReader { layout in
            VStack(spacing: 0) {
                LibrarySegmentPicker(selection: $segment)
                    .padding(.horizontal, layout.isTabletLike ? 28 : shellScreenHorizontalPadding)
                    .padding(.top, 8)
                    .frame(maxWidth: layout.shellContentMaxWidth ?? .infinity)
                    .frame(maxWidth: .infinity)

                Group {
                    switch segment {
                    case .radios:
                        radios()
                    case .songs:
                        songs()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(TuneAVTheme.shellBackground.ignoresSafeArea())
    }
}

struct LibrarySegmentPicker: View {
    @Binding var selection: LibrarySegment
    @Namespace private var selectionNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 4) {
            ForEach(LibrarySegment.allCases, id: \.self) { segment in
                segmentButton(segment)
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.86), value: selection)
        .padding(4)
        .background(TuneAVTheme.cardSurface, in: Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous)
                .stroke(TuneAVTheme.borderSubtle, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.string("shell.libraryHub.segments"))
        .accessibilityIdentifier("library.segments")
    }

    private func segmentButton(_ segment: LibrarySegment) -> some View {
        let isSelected = selection == segment

        return Button {
            selection = segment
        } label: {
            Text(segment.title)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(isSelected ? TuneAVTheme.highlight : TuneAVTheme.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: 36)
                .background {
                    if isSelected {
                        Capsule(style: .continuous)
                            .fill(TuneAVTheme.highlight.opacity(0.12))
                            .overlay {
                                Capsule(style: .continuous)
                                    .stroke(TuneAVTheme.highlight.opacity(0.22), lineWidth: 1)
                            }
                            .matchedGeometryEffect(id: "librarySegmentSelection", in: selectionNamespace)
                    }
                }
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(segment.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(segment.accessibilityIdentifier)
    }
}
