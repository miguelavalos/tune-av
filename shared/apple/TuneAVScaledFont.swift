import SwiftUI

/// Maps a fixed point size to the system text style whose default size is closest,
/// so a view styled at that size follows the text size chosen in Settings (Dynamic Type)
/// along that style's curve. At the default size the font stays exactly `size` points.
enum TuneAVTypeScale {
    static func textStyle(for size: CGFloat) -> Font.TextStyle {
        switch size {
        case ..<11.5:
            .caption2 // 11
        case ..<12.5:
            .caption // 12
        case ..<14.5:
            .footnote // 13
        case ..<15.5:
            .subheadline // 15
        case ..<16.5:
            .callout // 16
        case ..<18.5:
            .body // 17
        case ..<21:
            .title3 // 20
        case ..<25:
            .title2 // 22
        case ..<31:
            .title // 28
        default:
            .largeTitle // 34
        }
    }
}

/// `Font.system(size:weight:design:)` does not scale with Dynamic Type and SwiftUI has no
/// `relativeTo:` variant for system fonts, so the size is scaled with `ScaledMetric`, which
/// reads the view's `dynamicTypeSize` (and therefore respects a `.dynamicTypeSize(...)` cap
/// placed on a parent). On macOS, which has no Dynamic Type, the size is left as it is.
struct TuneAVScaledSystemFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight
    private let design: Font.Design

    init(size: CGFloat, weight: Font.Weight, design: Font.Design, relativeTo textStyle: Font.TextStyle) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: textStyle)
        self.weight = weight
        self.design = design
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight, design: design))
    }
}

extension View {
    /// A system font that is `size` points at the default text size and grows or shrinks with
    /// the text size chosen in iOS Settings, including the accessibility sizes.
    ///
    /// `textStyle` picks the scaling curve; by default it is the system style whose default
    /// size is closest to `size` (see `TuneAVTypeScale`). Use it where `.font(.system(size:))`
    /// was used before: the rendering at the default size is unchanged.
    func tuneScaledFont(
        size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default,
        relativeTo textStyle: Font.TextStyle? = nil
    ) -> some View {
        modifier(
            TuneAVScaledSystemFont(
                size: size,
                weight: weight,
                design: design,
                relativeTo: textStyle ?? TuneAVTypeScale.textStyle(for: size)
            )
        )
    }
}
