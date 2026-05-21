import AVAppShellFoundation
import SwiftUI

struct TuneAVFeedbackBadge: View {
    let feedback: TuneAVStationFeedback
    var size: CGFloat = 22
    var fontSize: CGFloat?
    var borderOpacity: Double = 0.78

    var body: some View {
        AVFeedbackStatusBadge(
            systemImage: feedback.systemImage,
            accessibilityLabel: feedback.localizedState,
            isHighlighted: feedback == .liked,
            size: size,
            fontSize: fontSize,
            borderOpacity: borderOpacity
        )
    }
}
