import AVAviFoundation
import SwiftUI

struct AviPreviewCapabilityRow: View {
    let systemImage: String
    let title: String
    let detail: String

    var body: some View {
        AVAviPreviewCapabilityRow(
            systemImage: systemImage,
            title: title,
            detail: detail
        )
    }
}

struct AviPreviewPrimaryButton: View {
    let title: String
    let systemImage: String
    let accessibilityIdentifier: String
    let action: () -> Void

    var body: some View {
        AVAviPreviewPrimaryButton(
            title: title,
            systemImage: systemImage,
            accessibilityIdentifier: accessibilityIdentifier,
            action: action
        )
    }
}

struct AviPreviewSecondaryButton: View {
    let title: String
    let systemImage: String
    let accessibilityIdentifier: String
    let action: () -> Void

    var body: some View {
        AVAviPreviewSecondaryButton(
            title: title,
            systemImage: systemImage,
            accessibilityIdentifier: accessibilityIdentifier,
            action: action
        )
    }
}
