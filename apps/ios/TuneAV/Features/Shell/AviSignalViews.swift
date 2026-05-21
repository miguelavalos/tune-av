import AVAviFoundation
import SwiftUI

struct AviSignalActionChip: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        AVAviActionChip(title: title, systemImage: systemImage, action: action)
    }
}

struct AviSignalStep: View {
    let index: Int
    let title: String

    var body: some View {
        AVAviSignalStep(index: index, title: title)
    }
}

struct AviSignalChip: View {
    let title: String
    let systemImage: String

    var body: some View {
        AVAviSignalChip(title: title, systemImage: systemImage)
    }
}

struct AviSignalRow: View {
    let title: String
    let detail: String
    let systemImage: String
    let accessibilityIdentifier: String

    var body: some View {
        AVAviInfoRow(
            title: title,
            detail: detail,
            systemImage: systemImage,
            accessibilityIdentifier: accessibilityIdentifier
        )
    }
}
