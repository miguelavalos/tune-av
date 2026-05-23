import SwiftUI

struct WrapTagsRow: View {
    let tags: [String]
    var highlighted = false

    var body: some View {
        FlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(.system(size: 13, weight: .semibold))
                    .shellChip(isHighlighted: highlighted, horizontalPadding: 12, verticalPadding: 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension View {
    func shellChip(
        isHighlighted: Bool,
        horizontalPadding: CGFloat = 14,
        verticalPadding: CGFloat = 10,
        highlightedStrokeOpacity: Double = 0.22
    ) -> some View {
        foregroundStyle(isHighlighted ? TuneAVTheme.highlight : TuneAVTheme.textPrimary)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(
                Capsule(style: .continuous)
                    .fill(isHighlighted ? TuneAVTheme.highlight.opacity(0.1) : TuneAVTheme.cardSurface)
            )
            .overlay {
                Capsule(style: .continuous)
                    .stroke(
                        isHighlighted ? TuneAVTheme.highlight.opacity(highlightedStrokeOpacity) : TuneAVTheme.borderSubtle,
                        lineWidth: 1
                    )
            }
    }
}

struct FlowLayout: Layout {
    var horizontalSpacing: CGFloat = 8
    var verticalSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = resolvedMaxWidth(from: proposal)
        var lineWidth: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var maxLineWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if lineWidth > 0, lineWidth + horizontalSpacing + size.width > maxWidth {
                totalHeight += lineHeight + verticalSpacing
                maxLineWidth = max(maxLineWidth, lineWidth)
                lineWidth = size.width
                lineHeight = size.height
            } else {
                lineWidth += lineWidth == 0 ? size.width : horizontalSpacing + size.width
                lineHeight = max(lineHeight, size.height)
            }
        }

        maxLineWidth = max(maxLineWidth, lineWidth)
        totalHeight += lineHeight

        return CGSize(width: maxLineWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var origin = CGPoint(x: bounds.minX, y: bounds.minY)
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if origin.x > bounds.minX, origin.x + size.width > bounds.maxX {
                origin.x = bounds.minX
                origin.y += lineHeight + verticalSpacing
                lineHeight = 0
            }

            subview.place(
                at: origin,
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )

            origin.x += size.width + horizontalSpacing
            lineHeight = max(lineHeight, size.height)
        }
    }

    private func resolvedMaxWidth(from proposal: ProposedViewSize) -> CGFloat {
        let conservativeCardWidth = UIScreen.main.bounds.width - 104
        guard let width = proposal.width, width.isFinite, width > 0 else {
            return conservativeCardWidth
        }
        return min(width, conservativeCardWidth)
    }
}
