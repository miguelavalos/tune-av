import AppKit
import CoreGraphics
import Foundation

private enum AviReactionAssetKind {
    case listening
    case saved
    case curious
    case thinking
    case dislike
    case surprised
    case calm
    case sleep
}

private struct AviReactionAssetPack {
    let prefix: String
    let sourceAsset: String
    let kind: AviReactionAssetKind
}

private struct AviStaticAssetCopy {
    let assetName: String
    let sourceAsset: String
    let kind: AviReactionAssetKind
    let frame: Int
}

private let staticCopies: [AviStaticAssetCopy] = [
    .init(assetName: "AviV2TuneLiked", sourceAsset: "AviV2TuneHappy", kind: .saved, frame: 10),
    .init(assetName: "AviV2TuneSaved", sourceAsset: "AviV2TuneHappy", kind: .saved, frame: 10),
    .init(assetName: "AviV2TuneCurious", sourceAsset: "AviV2TuneFocused", kind: .curious, frame: 5),
    .init(assetName: "AviV2TuneCalm", sourceAsset: "AviV2Sleep", kind: .calm, frame: 5)
]

private let packs: [AviReactionAssetPack] = [
    .init(prefix: "AviTuneListeningIdle", sourceAsset: "AviV2TuneListening", kind: .listening),
    .init(prefix: "AviTuneSaved", sourceAsset: "AviV2TuneSaved", kind: .saved),
    .init(prefix: "AviTuneCurious", sourceAsset: "AviV2TuneCurious", kind: .curious),
    .init(prefix: "AviTuneThinking", sourceAsset: "AviV2Thinking", kind: .thinking),
    .init(prefix: "AviTuneDislike", sourceAsset: "AviV2TuneDislike", kind: .dislike),
    .init(prefix: "AviTuneSurprised", sourceAsset: "AviV2TuneSurprised", kind: .surprised),
    .init(prefix: "AviTuneCalmIdle", sourceAsset: "AviV2TuneCalm", kind: .calm),
    .init(prefix: "AviTuneSleepIdle", sourceAsset: "AviV2Sleep", kind: .sleep)
]

private let frameCount = 20
private let fileManager = FileManager.default
private let toolURL = URL(fileURLWithPath: #filePath)
private let toolsURL = toolURL.deletingLastPathComponent()
private let assetsURL = toolURL
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("App/Assets.xcassets", isDirectory: true)

private func pngURL(in imageSetURL: URL) throws -> URL {
    let files = try fileManager.contentsOfDirectory(at: imageSetURL, includingPropertiesForKeys: nil)
    guard let png = files.first(where: { $0.pathExtension.lowercased() == "png" }) else {
        throw NSError(domain: "AviAssetGenerator", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Missing PNG in \(imageSetURL.path)"
        ])
    }
    return png
}

private func cgImage(for assetName: String) throws -> CGImage {
    let imageSetURL = assetsURL.appendingPathComponent("\(assetName).imageset", isDirectory: true)
    let imageURL = try pngURL(in: imageSetURL)
    guard
        let image = NSImage(contentsOf: imageURL),
        let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    else {
        throw NSError(domain: "AviAssetGenerator", code: 2, userInfo: [
            NSLocalizedDescriptionKey: "Unable to read image \(imageURL.path)"
        ])
    }
    return cgImage
}

private func writeContentsJSON(for assetName: String, in imageSetURL: URL) throws {
    let json = """
    {
      "images": [
        {
          "filename": "\(assetName).png",
          "idiom": "universal",
          "scale": "1x"
        }
      ],
      "info": {
        "author": "xcode",
        "version": 1
      }
    }
    """
    try json.write(
        to: imageSetURL.appendingPathComponent("Contents.json"),
        atomically: true,
        encoding: .utf8
    )
}

private func write(_ image: NSImage, to url: URL) throws {
    guard
        let tiffData = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiffData),
        let pngData = bitmap.representation(using: .png, properties: [:])
    else {
        throw NSError(domain: "AviAssetGenerator", code: 3, userInfo: [
            NSLocalizedDescriptionKey: "Unable to encode PNG \(url.path)"
        ])
    }
    try pngData.write(to: url, options: .atomic)
}

private func normalizeImageSet(_ assetName: String, image: NSImage) throws {
    let imageSetURL = assetsURL.appendingPathComponent("\(assetName).imageset", isDirectory: true)
    try fileManager.createDirectory(at: imageSetURL, withIntermediateDirectories: true)
    let files = try fileManager.contentsOfDirectory(at: imageSetURL, includingPropertiesForKeys: nil)
    for file in files where file.pathExtension.lowercased() == "png" && file.lastPathComponent != "\(assetName).png" {
        try fileManager.removeItem(at: file)
    }
    try write(image, to: imageSetURL.appendingPathComponent("\(assetName).png"))
    try writeContentsJSON(for: assetName, in: imageSetURL)
}

private func drawImage(_ cgImage: CGImage, in context: CGContext, size: CGSize, scale: CGFloat, rotation: CGFloat, x: CGFloat, y: CGFloat) {
    context.saveGState()
    context.translateBy(x: size.width / 2 + x, y: size.height / 2 + y)
    context.rotate(by: rotation * .pi / 180)
    context.scaleBy(x: scale, y: scale)
    context.translateBy(x: -size.width / 2, y: -size.height / 2)
    context.draw(cgImage, in: CGRect(origin: .zero, size: size))
    context.restoreGState()
}

private func drawCircle(in context: CGContext, center: CGPoint, radius: CGFloat, color: NSColor, alpha: CGFloat) {
    context.setFillColor(color.withAlphaComponent(alpha).cgColor)
    context.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
}

private func drawHeart(in context: CGContext, center: CGPoint, size: CGFloat, alpha: CGFloat) {
    context.saveGState()
    context.translateBy(x: center.x, y: center.y)
    context.scaleBy(x: size / 100, y: size / 100)
    let path = CGMutablePath()
    path.move(to: CGPoint(x: 0, y: -34))
    path.addCurve(to: CGPoint(x: -48, y: -4), control1: CGPoint(x: -30, y: -4), control2: CGPoint(x: -48, y: -18))
    path.addCurve(to: CGPoint(x: 0, y: 44), control1: CGPoint(x: -48, y: 26), control2: CGPoint(x: -14, y: 38))
    path.addCurve(to: CGPoint(x: 48, y: -4), control1: CGPoint(x: 14, y: 38), control2: CGPoint(x: 48, y: 26))
    path.addCurve(to: CGPoint(x: 0, y: -34), control1: CGPoint(x: 48, y: -18), control2: CGPoint(x: 30, y: -4))
    context.setFillColor(NSColor.systemPink.withAlphaComponent(alpha).cgColor)
    context.addPath(path)
    context.fillPath()
    context.restoreGState()
}

private func drawSpark(in context: CGContext, center: CGPoint, radius: CGFloat, color: NSColor, alpha: CGFloat) {
    context.saveGState()
    context.setStrokeColor(color.withAlphaComponent(alpha).cgColor)
    context.setLineWidth(max(2, radius * 0.18))
    context.setLineCap(.round)
    context.move(to: CGPoint(x: center.x, y: center.y - radius))
    context.addLine(to: CGPoint(x: center.x, y: center.y + radius))
    context.move(to: CGPoint(x: center.x - radius, y: center.y))
    context.addLine(to: CGPoint(x: center.x + radius, y: center.y))
    context.move(to: CGPoint(x: center.x - radius * 0.65, y: center.y - radius * 0.65))
    context.addLine(to: CGPoint(x: center.x + radius * 0.65, y: center.y + radius * 0.65))
    context.move(to: CGPoint(x: center.x + radius * 0.65, y: center.y - radius * 0.65))
    context.addLine(to: CGPoint(x: center.x - radius * 0.65, y: center.y + radius * 0.65))
    context.strokePath()
    context.restoreGState()
}

private func renderFrame(source: CGImage, kind: AviReactionAssetKind, frame: Int) -> NSImage {
    let size = CGSize(width: source.width, height: source.height)
    let image = NSImage(size: size)
    let t = CGFloat(frame) / CGFloat(frameCount)
    let wave = sin(t * .pi * 2)
    let pulse = sin(t * .pi)
    let quick = sin(t * .pi * 4)

    image.lockFocus()
    guard let context = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }
    context.clear(CGRect(origin: .zero, size: size))

    switch kind {
    case .listening:
        drawImage(source, in: context, size: size, scale: 1 + 0.006 * abs(wave), rotation: 0.6 * wave, x: 0, y: 2 * wave)

    case .saved:
        drawImage(source, in: context, size: size, scale: 1 + 0.018 * pulse, rotation: 1.8 * wave, x: 0, y: -4 * pulse)
        drawHeart(in: context, center: CGPoint(x: 398 + 6 * wave, y: 385 + 3 * pulse), size: 34 + 6 * pulse, alpha: 0.58 * pulse)
        drawSpark(in: context, center: CGPoint(x: 118, y: 372), radius: 12 + 4 * pulse, color: .systemYellow, alpha: 0.42 * pulse)

    case .curious:
        drawImage(source, in: context, size: size, scale: 1 + 0.01 * pulse, rotation: 2.2 * wave, x: 5 * wave, y: 0)
        drawCircle(in: context, center: CGPoint(x: 392, y: 384 + 8 * wave), radius: 7 + 2 * pulse, color: .systemTeal, alpha: 0.48)
        drawCircle(in: context, center: CGPoint(x: 418, y: 414 - 6 * wave), radius: 5 + 2 * pulse, color: .systemTeal, alpha: 0.34)
        drawCircle(in: context, center: CGPoint(x: 366, y: 414 + 4 * wave), radius: 4 + 1.5 * pulse, color: .systemTeal, alpha: 0.28)

    case .thinking:
        drawImage(source, in: context, size: size, scale: 1, rotation: 1.4 * wave, x: 3 * wave, y: 0)
        for dot in 0..<3 {
            let phase = CGFloat(dot) * 0.22
            let dotPulse = max(0.22, sin((t + phase) * .pi * 2) * 0.5 + 0.5)
            drawCircle(
                in: context,
                center: CGPoint(x: 350 + CGFloat(dot) * 25, y: 404 + 5 * dotPulse),
                radius: 5 + 4 * dotPulse,
                color: .systemPurple,
                alpha: 0.28 + 0.3 * dotPulse
            )
        }

    case .dislike:
        drawImage(source, in: context, size: size, scale: 1, rotation: -1.6 * abs(quick), x: 7 * quick, y: 2 * abs(quick))
        context.setStrokeColor(NSColor.systemGray.withAlphaComponent(0.32 * pulse).cgColor)
        context.setLineWidth(5)
        context.setLineCap(.round)
        context.move(to: CGPoint(x: 370, y: 398))
        context.addLine(to: CGPoint(x: 424, y: 398))
        context.strokePath()

    case .surprised:
        drawImage(source, in: context, size: size, scale: 1 + 0.038 * pulse, rotation: -1.2 * wave, x: 0, y: -7 * pulse)
        drawSpark(in: context, center: CGPoint(x: 382, y: 410), radius: 11 + 8 * pulse, color: .systemYellow, alpha: 0.5 * pulse)

    case .calm:
        drawImage(source, in: context, size: size, scale: 1 + 0.004 * abs(wave), rotation: 0.25 * wave, x: 0, y: 1.8 * wave)
        drawCircle(in: context, center: CGPoint(x: 398 + 3 * wave, y: 404), radius: 4 + 1.5 * pulse, color: .systemBlue, alpha: 0.16 + 0.12 * pulse)

    case .sleep:
        drawImage(source, in: context, size: size, scale: 1 + 0.003 * abs(wave), rotation: 0, x: 0, y: 1.5 * wave)
        drawCircle(in: context, center: CGPoint(x: 390, y: 405 + 5 * wave), radius: 4 + 2 * pulse, color: .systemIndigo, alpha: 0.24 * pulse)
        drawCircle(in: context, center: CGPoint(x: 414, y: 428 + 8 * wave), radius: 3 + 1.5 * pulse, color: .systemIndigo, alpha: 0.18 * pulse)
    }

    image.unlockFocus()
    return image
}

private func generateContactSheet(samples: [(name: String, image: NSImage)]) throws {
    let tile = CGSize(width: 150, height: 174)
    let columns = 4
    let rows = Int(ceil(Double(samples.count) / Double(columns)))
    let sheetSize = CGSize(width: tile.width * CGFloat(columns), height: tile.height * CGFloat(rows))
    let sheet = NSImage(size: sheetSize)

    sheet.lockFocus()
    guard let context = NSGraphicsContext.current?.cgContext else {
        sheet.unlockFocus()
        return
    }
    context.setFillColor(NSColor(calibratedWhite: 0.06, alpha: 1).cgColor)
    context.fill(CGRect(origin: .zero, size: sheetSize))

    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
        .foregroundColor: NSColor.white.withAlphaComponent(0.86)
    ]

    for (index, sample) in samples.enumerated() {
        let column = index % columns
        let row = index / columns
        let origin = CGPoint(x: CGFloat(column) * tile.width, y: sheetSize.height - CGFloat(row + 1) * tile.height)
        let rect = CGRect(x: origin.x + 12, y: origin.y + 28, width: tile.width - 24, height: tile.width - 24)
        sample.image.draw(in: rect)
        sample.name.draw(
            in: CGRect(x: origin.x + 10, y: origin.y + 9, width: tile.width - 20, height: 16),
            withAttributes: attributes
        )
    }

    sheet.unlockFocus()
    try write(sheet, to: toolsURL.appendingPathComponent("avi_reaction_contact_sheet.png"))
}

for copy in staticCopies {
    let source = try cgImage(for: copy.sourceAsset)
    try normalizeImageSet(copy.assetName, image: renderFrame(source: source, kind: copy.kind, frame: copy.frame))
}

var contactSheetSamples: [(name: String, image: NSImage)] = []

for pack in packs {
    let source = try cgImage(for: pack.sourceAsset)
    for frame in 0..<frameCount {
        let frameName = "\(pack.prefix)\(String(format: "%03d", frame))"
        let image = renderFrame(source: source, kind: pack.kind, frame: frame)
        try normalizeImageSet(frameName, image: image)
        if [0, 5, 10, 15].contains(frame) {
            contactSheetSamples.append((name: frameName, image: image))
        }
    }
}

try generateContactSheet(samples: contactSheetSamples)

print("Generated \(packs.count * frameCount) Avi reaction frames in \(assetsURL.path)")
print("Generated QA sheet at \(toolsURL.appendingPathComponent("avi_reaction_contact_sheet.png").path)")
