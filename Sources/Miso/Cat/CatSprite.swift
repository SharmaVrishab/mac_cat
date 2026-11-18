import CoreGraphics
import Foundation

enum CatAction: Equatable {
    case walk
    case sit
    case sleep
    case happy
    case groom
    case work
    case coffee
}

struct CatPose: Equatable {
    var stage: CatStage
    var action: CatAction
    var frame: Int
    var facingLeft: Bool
    var blink: Bool
    var vibe: Bool = false
}

enum CatMetrics {
    static let side = 160
}

struct CatPicture {
    var image: CGImage
    let width: Int
    let height: Int
    private let alphas: [UInt8]

    init(image: CGImage, width: Int, height: Int, alphas: [UInt8]) {
        self.image = image
        self.width = width
        self.height = height
        self.alphas = alphas
    }

    func containsBody(at local: CGPoint, in bounds: CGSize) -> Bool {
        guard bounds.width > 1, bounds.height > 1 else { return false }
        let x = Int(local.x / bounds.width * CGFloat(width))
        let yFromTop = Int((bounds.height - local.y) / bounds.height * CGFloat(height))
        guard x >= 0, yFromTop >= 0, x < width, yFromTop < height else { return false }
        return alphas[yFromTop * width + x] > 48
    }
}

enum CatSprite {
    static func picture(for pose: CatPose, scale: CGFloat) -> CatPicture {
        let points = CatMetrics.side
        let pixels = max(1, Int((CGFloat(points) * max(scale, 1)).rounded()))
        var buffer = [UInt8](repeating: 0, count: pixels * pixels * 4)
        let image: CGImage = buffer.withUnsafeMutableBytes { raw in
            guard let context = CGContext(
                data: raw.baseAddress,
                width: pixels,
                height: pixels,
                bitsPerComponent: 8,
                bytesPerRow: pixels * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                fatalError("Could not create the bitmap")
            }
            context.setAllowsAntialiasing(true)
            context.setShouldAntialias(true)
            context.interpolationQuality = .high
            context.translateBy(x: 0, y: CGFloat(pixels))
            context.scaleBy(x: CGFloat(pixels) / CGFloat(points), y: -CGFloat(pixels) / CGFloat(points))
            draw(pose, in: context)
            return context.makeImage()!
        }
        let alphas = stride(from: 3, to: buffer.count, by: 4).map { buffer[$0] }
        return CatPicture(image: image, width: pixels, height: pixels, alphas: alphas)
    }

    private static func draw(_ pose: CatPose, in context: CGContext) {
        let stageScale: CGFloat = switch pose.stage {
        case .kitten: 0.78
        case .young: 0.9
        case .adult: 1
        }
        let rhythmic = pose.action == .walk || pose.action == .happy || pose.vibe
        let bob: CGFloat = rhythmic && pose.frame % 2 == 1 ? (pose.vibe ? -6 : -3) : 0
        context.saveGState()
        if pose.facingLeft {
            context.translateBy(x: CGFloat(CatMetrics.side), y: 0)
            context.scaleBy(x: -1, y: 1)
        }
        context.translateBy(x: 80, y: 86 + bob)
        context.scaleBy(x: stageScale, y: stageScale)
        context.translateBy(x: -80, y: -86)

        let tilt: CGFloat = switch pose.action {
        case .walk, .happy:
            pose.frame % 4 < 2 ? -0.08 : 0.08
        case .groom:
            0.16
        case .sleep:
            0.1
        default:
            0
        }

        drawStand(context)

        context.saveGState()
        context.translateBy(x: 80, y: 116)
        context.rotate(by: tilt)
        context.translateBy(x: -80, y: -116)
        drawHead(pose, in: context)
        context.restoreGState()

        if pose.action == .work {
            laptop(context)
        }
        if pose.action == .happy {
            confetti(context, frame: pose.frame)
        }
        if pose.action == .coffee {
            mug(context, frame: pose.frame)
        }
        if pose.action == .sleep {
            zzz(context, frame: pose.frame)
        }
        if pose.vibe {
            note(context)
        }
        context.restoreGState()
    }

    private static func drawStand(_ context: CGContext) {
        fillOval(context, CGRect(x: 48, y: 140, width: 64, height: 10), [rgb(40, 42, 46, alpha: 0.16)])
        context.setFillColor(rgb(72, 74, 78))
        fillRounded(context, CGRect(x: 42, y: 126, width: 76, height: 18), radius: 6)
        fillOval(context, CGRect(x: 48, y: 130, width: 6, height: 6), [rgb(48, 50, 54)])
        fillOval(context, CGRect(x: 106, y: 130, width: 6, height: 6), [rgb(48, 50, 54)])
        context.setFillColor(rgb(96, 98, 102))
        fillRounded(context, CGRect(x: 60, y: 110, width: 10, height: 22), radius: 3)
        fillRounded(context, CGRect(x: 90, y: 110, width: 10, height: 22), radius: 3)
        fillOval(context, CGRect(x: 68, y: 112, width: 24, height: 14), [rgb(58, 60, 64), rgb(36, 38, 42)])
    }

    private static func drawHead(_ pose: CatPose, in context: CGContext) {
        context.setFillColor(rgb(154, 152, 146))
        fillRounded(context, CGRect(x: 20, y: 42, width: 32, height: 76), radius: 8)
        context.setStrokeColor(rgb(110, 108, 102))
        context.setLineWidth(1.6)
        context.setLineCap(.round)
        var ventY: CGFloat = 54
        while ventY < 90 {
            context.move(to: CGPoint(x: 26, y: ventY))
            context.addLine(to: CGPoint(x: 42, y: ventY))
            context.strokePath()
            ventY += 8
        }
        context.setFillColor(rgb(86, 88, 92))
        fillRounded(context, CGRect(x: 26, y: 98, width: 12, height: 7), radius: 1.5)

        context.setFillColor(rgb(214, 212, 206))
        fillRounded(context, CGRect(x: 44, y: 36, width: 82, height: 86), radius: 11)
        context.saveGState()
        context.addPath(CGPath(roundedRect: CGRect(x: 44, y: 36, width: 82, height: 86), cornerWidth: 11, cornerHeight: 11, transform: nil))
        context.clip()
        fillOval(context, CGRect(x: 48, y: 38, width: 40, height: 24), [rgb(255, 255, 255, alpha: 0.5), rgb(255, 255, 255, alpha: 0)])
        context.restoreGState()

        context.setFillColor(rgb(238, 236, 230))
        fillRounded(context, CGRect(x: 42, y: 18, width: 84, height: 24), radius: 6)
        context.setFillColor(rgb(64, 66, 70))
        fillRounded(context, CGRect(x: 54, y: 26, width: 18, height: 5), radius: 1.5)
        fillRounded(context, CGRect(x: 78, y: 26, width: 18, height: 5), radius: 1.5)
        fillOval(context, CGRect(x: 104, y: 22, width: 10, height: 10), [rgb(186, 184, 178), rgb(132, 130, 124)])
        fillOval(context, CGRect(x: 112, y: 24, width: 4, height: 4), [rgb(220, 224, 230)])

        context.setFillColor(rgb(16, 18, 22))
        fillRounded(context, CGRect(x: 54, y: 48, width: 64, height: 60), radius: 9)
        let asleep = pose.action == .sleep
        context.setFillColor(asleep ? rgb(6, 10, 16) : rgb(12, 20, 32))
        fillRounded(context, CGRect(x: 60, y: 54, width: 52, height: 42), radius: 6)
        fillOval(context, CGRect(x: 78, y: 98, width: 10, height: 7), [rgb(48, 50, 54), rgb(24, 26, 30)])
        screenFace(pose, in: context)
    }

    private static func screenFace(_ pose: CatPose, in context: CGContext) {
        let lookX: CGFloat = (pose.action == .walk || pose.action == .happy) ? 3 : 0
        let lookY: CGFloat = switch pose.action {
        case .groom: 5
        case .sleep: 2
        default: 0
        }
        let left = CGPoint(x: 74 + lookX, y: 68 + lookY)
        let right = CGPoint(x: 98 + lookX, y: 68 + lookY)
        if pose.blink || pose.action == .sleep {
            eyeDash(context, at: left)
            eyeDash(context, at: right)
        } else {
            let radius: CGFloat = switch pose.action {
            case .happy: 3.6
            case .work: 2.1
            default: 2.8
            }
            eyeDot(context, at: left, radius: radius)
            eyeDot(context, at: right, radius: radius)
        }

        context.setStrokeColor(rgb(232, 238, 246))
        context.setLineWidth(pose.action == .happy ? 2.4 : 2.2)
        context.setLineCap(.round)
        switch pose.action {
        case .happy:
            context.move(to: CGPoint(x: 76, y: 80))
            context.addQuadCurve(to: CGPoint(x: 98, y: 80), control: CGPoint(x: 87, y: 92))
        case .sleep:
            context.move(to: CGPoint(x: 82, y: 84))
            context.addLine(to: CGPoint(x: 94, y: 84))
        case .groom:
            context.move(to: CGPoint(x: 80, y: 86))
            context.addLine(to: CGPoint(x: 96, y: 86))
        default:
            context.move(to: CGPoint(x: 78, y: 82))
            context.addLine(to: CGPoint(x: 98, y: 82))
        }
        context.strokePath()
    }

    private static func eyeDot(_ context: CGContext, at center: CGPoint, radius: CGFloat) {
        fillOval(
            context,
            CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2),
            [rgb(244, 248, 255), rgb(210, 224, 236)]
        )
    }

    private static func eyeDash(_ context: CGContext, at center: CGPoint) {
        context.setStrokeColor(rgb(232, 238, 246))
        context.setLineWidth(2)
        context.setLineCap(.round)
        context.move(to: CGPoint(x: center.x - 4, y: center.y))
        context.addLine(to: CGPoint(x: center.x + 4, y: center.y))
        context.strokePath()
    }

    private static func confetti(_ context: CGContext, frame: Int) {
        let spots: [(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (24, 36, 244, 150, 90),
            (136, 30, 255, 196, 120),
            (20, 58, 186, 140, 230),
            (140, 54, 120, 190, 160),
            (32, 26, 255, 220, 140),
            (128, 20, 240, 120, 150),
        ]
        for (index, spot) in spots.enumerated() {
            let drift = CGFloat((frame + index) % 4) * 2
            fillOval(
                context,
                CGRect(x: spot.0, y: spot.1 + drift, width: 5, height: 5),
                [rgb(spot.2, spot.3, spot.4)]
            )
        }
    }

    private static func mug(_ context: CGContext, frame: Int) {
        fillOval(context, CGRect(x: 122, y: 104, width: 22, height: 18), [rgb(255, 250, 245), rgb(214, 186, 162)], highlight: CGPoint(x: 128, y: 108))
        fillOval(context, CGRect(x: 126, y: 108, width: 14, height: 9), [rgb(122, 74, 44), rgb(78, 46, 28)])
        context.setStrokeColor(rgb(196, 164, 142))
        context.setLineWidth(2.2)
        context.setLineCap(.round)
        context.move(to: CGPoint(x: 140, y: 108))
        context.addQuadCurve(to: CGPoint(x: 140, y: 118), control: CGPoint(x: 152, y: 113))
        context.strokePath()
        let rise = CGFloat(frame % 4) * 2
        context.setStrokeColor(rgb(255, 255, 255, alpha: 0.85))
        context.setLineWidth(1.4)
        context.move(to: CGPoint(x: 132, y: 102))
        context.addQuadCurve(to: CGPoint(x: 130, y: 88 - rise), control: CGPoint(x: 142, y: 94 - rise))
        context.strokePath()
    }

    private static func laptop(_ context: CGContext) {
        context.setFillColor(rgb(58, 66, 82))
        context.fill(CGRect(x: 54, y: 136, width: 52, height: 14))
        context.setFillColor(rgb(168, 214, 176))
        context.fill(CGRect(x: 58, y: 140, width: 44, height: 6))
        context.setFillColor(rgb(92, 100, 116))
        fillRounded(context, CGRect(x: 46, y: 148, width: 68, height: 7), radius: 2)
    }

    private static func zzz(_ context: CGContext, frame: Int) {
        let drift = CGFloat(frame % 4) * 2
        zed(context, at: CGPoint(x: 124, y: 20 - drift), size: 11, alpha: 0.95)
        zed(context, at: CGPoint(x: 136, y: 10 - drift), size: 8, alpha: 0.72)
        zed(context, at: CGPoint(x: 116, y: 8 - drift), size: 6, alpha: 0.5)
    }

    private static func zed(_ context: CGContext, at point: CGPoint, size: CGFloat, alpha: CGFloat) {
        context.setStrokeColor(rgb(120, 96, 176, alpha: alpha))
        context.setLineWidth(max(1.2, size * 0.16))
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.move(to: CGPoint(x: point.x, y: point.y))
        context.addLine(to: CGPoint(x: point.x + size, y: point.y))
        context.addLine(to: CGPoint(x: point.x, y: point.y + size * 0.8))
        context.addLine(to: CGPoint(x: point.x + size, y: point.y + size * 0.8))
        context.strokePath()
    }

    private static func note(_ context: CGContext) {
        fillOval(context, CGRect(x: 16, y: 44, width: 8, height: 6), [rgb(120, 86, 196), rgb(86, 54, 156)])
        context.setStrokeColor(rgb(120, 86, 196))
        context.setLineWidth(1.6)
        context.setLineCap(.round)
        context.move(to: CGPoint(x: 23, y: 47))
        context.addLine(to: CGPoint(x: 23, y: 30))
        context.strokePath()
        context.move(to: CGPoint(x: 23, y: 30))
        context.addQuadCurve(to: CGPoint(x: 31, y: 34), control: CGPoint(x: 29, y: 26))
        context.strokePath()
    }

    private static func fillRounded(_ context: CGContext, _ rect: CGRect, radius: CGFloat) {
        let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        context.addPath(path)
        context.fillPath()
    }

    private static func fillOval(_ context: CGContext, _ rect: CGRect, _ colors: [CGColor], highlight: CGPoint? = nil) {
        guard rect.width > 1, rect.height > 1, let first = colors.first else { return }
        context.saveGState()
        context.addEllipse(in: rect)
        context.clip()
        if colors.count == 1 {
            context.setFillColor(first)
            context.fill(rect)
        } else if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: nil) {
            let start = highlight ?? CGPoint(x: rect.midX - rect.width * 0.18, y: rect.minY + rect.height * 0.28)
            let end = CGPoint(x: rect.midX + rect.width * 0.08, y: rect.midY + rect.height * 0.12)
            context.drawRadialGradient(
                gradient,
                startCenter: start,
                startRadius: 0,
                endCenter: end,
                endRadius: max(rect.width, rect.height) * 0.72,
                options: [.drawsAfterEndLocation]
            )
        }
        context.restoreGState()
    }

    private static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, alpha: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: alpha)
    }
}
