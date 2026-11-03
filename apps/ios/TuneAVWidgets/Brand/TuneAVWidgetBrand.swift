import SwiftUI

enum TuneAVWidgetBrand {
    static let ink = Color(red: 0x15 / 255, green: 0x19 / 255, blue: 0x4A / 255)
    static let inkRaised = Color(red: 0x22 / 255, green: 0x27 / 255, blue: 0x63 / 255)
    static let paper = Color(red: 0xFB / 255, green: 0xF7 / 255, blue: 0xEB / 255)
    static let green = Color(red: 0x6D / 255, green: 0xBE / 255, blue: 0x45 / 255)
}

struct TuneAVMarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        let width = rect.width
        let top = rect.minY
        let bottom = rect.maxY
        func x(_ value: CGFloat) -> CGFloat { rect.minX + width * value }

        var path = Path()
        path.move(to: CGPoint(x: x(0.02), y: bottom))
        path.addLine(to: CGPoint(x: x(0.245), y: top))
        path.addLine(to: CGPoint(x: x(0.47), y: bottom))
        path.move(to: CGPoint(x: x(0.53), y: top))
        path.addLine(to: CGPoint(x: x(0.755), y: bottom))
        path.addLine(to: CGPoint(x: x(0.98), y: top))
        return path
    }
}

struct TuneAVMark: View {
    var color: Color = TuneAVWidgetBrand.green
    var lineWidthRatio: CGFloat = 0.2

    var body: some View {
        GeometryReader { proxy in
            let lineWidth = max(1.5, proxy.size.height * lineWidthRatio)
            TuneAVMarkShape()
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                .padding(lineWidth / 2)
        }
        .aspectRatio(1.9, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

struct TuneAVLiveBars: View {
    let isLive: Bool
    var color: Color = TuneAVWidgetBrand.green

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array([0.55, 1.0, 0.7].enumerated()), id: \.offset) { _, ratio in
                Capsule(style: .continuous)
                    .fill(color)
                    .frame(width: 3)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .scaleEffect(x: 1, y: isLive ? ratio : 0.3, anchor: .bottom)
            }
        }
        .opacity(isLive ? 1 : 0.7)
        .accessibilityHidden(true)
    }
}
