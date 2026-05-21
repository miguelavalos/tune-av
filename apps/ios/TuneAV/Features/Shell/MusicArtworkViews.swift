import SwiftUI

struct TuneAVMusicArtworkFallback: View {
    let systemImage: String
    let size: CGFloat
    var iconSize: CGFloat = 18

    var body: some View {
        shape
            .fill(TuneAVTheme.mutedSurface)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: systemImage)
                    .font(.system(size: iconSize, weight: .bold))
                    .foregroundStyle(TuneAVTheme.highlight)
            }
            .overlay {
                shape
                    .stroke(TuneAVTheme.borderSubtle, lineWidth: 1)
            }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: StationArtworkView.ArtworkStyle.cornerRadius(for: size),
            style: .continuous
        )
    }
}
