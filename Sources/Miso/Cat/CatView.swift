import AppKit

final class CatView: NSView {
    private var pose = CatPose(stage: .kitten, action: .sit, frame: 0, facingLeft: false, blink: false)
    private var picture: CatPicture?
    var onClick: (() -> Void)?
    var onDragBegan: (() -> Void)?
    var onDragEnded: (() -> Void)?
    var onRightClick: ((NSEvent) -> Void)?

    private var dragDidMove = false
    private var dragAnchorMouse = NSPoint.zero
    private var dragAnchorOrigin = NSPoint.zero

    override var isOpaque: Bool { false }
    override var wantsUpdateLayer: Bool { false }
    override var acceptsFirstResponder: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refreshPicture()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        refreshPicture()
    }

    func show(pose: CatPose) {
        self.pose = pose
        refreshPicture()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard bounds.contains(local), picture?.containsBody(at: local, in: bounds.size) == true else { return nil }
        return self
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.setShouldAntialias(true)
        context.interpolationQuality = .high
        context.clear(bounds)
        if let image = picture?.image {
            context.draw(image, in: bounds)
        }
        context.restoreGState()
    }

    override func mouseDown(with event: NSEvent) {
        dragDidMove = false
        dragAnchorMouse = NSEvent.mouseLocation
        dragAnchorOrigin = window?.frame.origin ?? .zero
        onDragBegan?()
    }

    override func mouseDragged(with event: NSEvent) {
        let mouse = NSEvent.mouseLocation
        let dx = mouse.x - dragAnchorMouse.x
        let dy = mouse.y - dragAnchorMouse.y
        if abs(dx) > 2 || abs(dy) > 2 {
            dragDidMove = true
        }
        window?.setFrameOrigin(NSPoint(
            x: (dragAnchorOrigin.x + dx).rounded(),
            y: (dragAnchorOrigin.y + dy).rounded()
        ))
    }

    override func mouseUp(with event: NSEvent) {
        if dragDidMove {
            onDragEnded?()
        } else {
            onClick?()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?(event)
    }

    private func refreshPicture() {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        picture = CatSprite.picture(for: pose, scale: scale)
        needsDisplay = true
    }
}
