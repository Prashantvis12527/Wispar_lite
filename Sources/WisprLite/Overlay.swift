import AppKit

/// Floating vertical pill at the right edge of the screen. Idle: small and dim, tucked half off-screen.
/// Listening: pops out, grows and the bars glow with the mic level. Processing: bars ripple.
/// Also shows a result card (text + Copy) when a dictation has nowhere to be pasted.
final class Overlay: NSObject {
    enum Mode { case idle, listening, processing }

    enum Position: String, CaseIterable {
        case bottom, top, left, right
        var title: String { rawValue.capitalized }
        var vertical: Bool { self == .left || self == .right }
    }

    private static let pad: CGFloat = 14
    // Long side runs along the screen edge's perpendicular for left/right (vertical pill) and along it for top/bottom.
    private static let idleLong: CGFloat = 38, idleShort: CGFloat = 12
    private static let activeLong: CGFloat = 92, activeShort: CGFloat = 22

    private let panel: NSPanel
    private let pill = PillView()
    private var timer: Timer?
    private var mode: Mode = .idle
    private var level: CGFloat = 0
    /// Mouse is over the pill: it pops out so it is easy to click.
    private var hovering = false

    /// While the mouse is outside the panel but still in the hover zone, polls until it leaves (no flicker at the edge).
    private var hoverWatch: Timer?
    /// Small "Click to dictate" label shown above the pill after a short hover.
    private var hint: NSPanel?
    private var hintLabel: NSTextField?
    private var hintDelay: DispatchWorkItem?

    /// Clicking the pill: start a dictation, or stop and paste the running one.
    var onClick: (() -> Void)?

    private var card: NSPanel?
    private var cardText = ""
    private var copyButton: NSButton?
    private var cardTimer: Timer?
    private var cardRemaining: TimeInterval = 0
    private var ring: CAShapeLayer?
    private static let cardLifetime: TimeInterval = 10

    var position: Position = .bottom {
        didSet {
            pill.horizontal = !position.vertical
            apply(animated: false)
        }
    }

    /// Keep the idle pill on screen between dictations.
    var idleVisible = true { didSet { apply(animated: false) } }

    override init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.ignoresMouseEvents = false   // hover and click; the panel never becomes key, so focus stays in the target app
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = pill
        pill.onHover = { [weak self] inside in self?.mouseMoved(inside: inside) }
        pill.onClick = { [weak self] in
            guard let self, self.mode != .processing else { return }
            self.hideHint()
            self.onClick?()
        }
        panel.setFrame(frame(for: .idle), display: false)
        apply(animated: false)
    }

    func setMode(_ new: Mode) {
        guard new != mode else { return }
        mode = new
        pill.mode = new
        if new != .listening { level = 0 }
        if new == .idle { timer?.invalidate(); timer = nil } else if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.pill.tick(level: self.level)
            }
        }
        apply(animated: true)
        if hovering { scheduleHint() } else { hideHint() }
    }

    /// Mic level 0...1, fed from the recorder.
    func setLevel(_ v: CGFloat) { level = v }

    // MARK: pill placement

    /// The pill's own rect (without glow padding) for a mode, attached to the chosen screen edge.
    private func pillRect(for mode: Mode) -> NSRect { pillRect(big: mode != .idle || hovering) }

    private func pillRect(big: Bool) -> NSRect {
        let screen = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        let small = !big
        let long = small ? Overlay.idleLong : Overlay.activeLong
        let short = small ? Overlay.idleShort : Overlay.activeShort
        let size = position.vertical ? NSSize(width: short, height: long) : NSSize(width: long, height: short)
        let inward: CGFloat = small ? -6 : 8      // idle sits partly off the edge, active or hovered pops out
        switch position {
        case .right:  return NSRect(x: screen.maxX - size.width - inward, y: screen.midY - size.height / 2, width: size.width, height: size.height)
        case .left:   return NSRect(x: screen.minX + inward, y: screen.midY - size.height / 2, width: size.width, height: size.height)
        case .bottom: return NSRect(x: screen.midX - size.width / 2, y: screen.minY + inward, width: size.width, height: size.height)
        case .top:    return NSRect(x: screen.midX - size.width / 2, y: screen.maxY - size.height - inward, width: size.width, height: size.height)
        }
    }

    private func frame(for mode: Mode) -> NSRect {
        pillRect(for: mode).insetBy(dx: -Overlay.pad, dy: -Overlay.pad)
    }

    // MARK: hover

    /// Area that counts as "over the pill": the small and the big pill together, stretched to the screen edge.
    /// Using one fixed area (instead of the panel, which changes size) keeps the pill from popping in and out.
    private var hoverZone: NSRect {
        let s = (NSScreen.main ?? NSScreen.screens[0]).frame
        let z = pillRect(big: false).union(pillRect(big: true)).insetBy(dx: -Overlay.pad, dy: -Overlay.pad)
        switch position {
        case .bottom: return NSRect(x: z.minX, y: s.minY, width: z.width, height: z.maxY - s.minY)
        case .top:    return NSRect(x: z.minX, y: z.minY, width: z.width, height: s.maxY - z.minY)
        case .left:   return NSRect(x: s.minX, y: z.minY, width: z.maxX - s.minX, height: z.height)
        case .right:  return NSRect(x: z.minX, y: z.minY, width: s.maxX - z.minX, height: z.height)
        }
    }

    private func mouseMoved(inside: Bool) {
        if inside {
            hoverWatch?.invalidate(); hoverWatch = nil
            setHovering(true)
            return
        }
        // Left the panel: collapse only once the cursor is really out of the hover zone.
        guard hoverWatch == nil else { return }
        hoverWatch = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            if self.panel.frame.contains(NSEvent.mouseLocation) || self.hoverZone.contains(NSEvent.mouseLocation) { return }
            t.invalidate(); self.hoverWatch = nil
            self.setHovering(false)
        }
        hoverWatch?.fire()
    }

    private func setHovering(_ on: Bool) {
        guard hovering != on else { return }
        hovering = on
        pill.hover = on
        apply(animated: true, gentle: true)
        if on { scheduleHint() } else { hideHint() }
    }

    /// Shows the hint after a short pause, so a cursor just passing by doesn't flash it.
    private func scheduleHint() {
        hintDelay?.cancel()
        guard mode != .processing, card == nil else { hideHint(); return }
        let text = mode == .listening ? "Click to stop and paste" : "Click to dictate"
        if let label = hintLabel, hint?.isVisible == true, hint?.alphaValue ?? 0 > 0 {
            label.stringValue = text
            layoutHint()
            return
        }
        let work = DispatchWorkItem { [weak self] in self?.showHint(text) }
        hintDelay = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private func showHint(_ text: String) {
        guard hovering else { return }
        if hint == nil {
            let label = NSTextField(labelWithString: text)
            label.font = .systemFont(ofSize: 12, weight: .medium)
            label.textColor = NSColor(white: 1, alpha: 0.92)
            let bg = NSVisualEffectView()
            bg.material = .hudWindow
            bg.appearance = NSAppearance(named: .vibrantDark)
            bg.state = .active
            bg.wantsLayer = true
            bg.layer?.cornerRadius = 8
            bg.layer?.masksToBounds = true
            bg.layer?.borderWidth = 0.5
            bg.layer?.borderColor = NSColor(white: 1, alpha: 0.12).cgColor
            bg.addSubview(label)
            let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = true
            p.level = .statusBar
            p.ignoresMouseEvents = true
            p.hidesOnDeactivate = false
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            p.contentView = bg
            hint = p
            hintLabel = label
        }
        hintLabel?.stringValue = text
        layoutHint()
        guard let p = hint else { return }
        p.alphaValue = 0
        p.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.15; p.animator().alphaValue = 1 }
    }

    /// Sizes the hint to its text and places it beside the pill, on the screen side.
    private func layoutHint() {
        guard let p = hint, let label = hintLabel else { return }
        let size = label.fittingSize
        let w = ceil(size.width) + 20, h = ceil(size.height) + 10
        label.frame = NSRect(x: 10, y: (h - size.height) / 2, width: ceil(size.width), height: ceil(size.height))
        let pr = pillRect(big: true)
        let gap: CGFloat = 8
        let origin: NSPoint
        switch position {
        case .bottom: origin = NSPoint(x: pr.midX - w / 2, y: pr.maxY + gap)
        case .top:    origin = NSPoint(x: pr.midX - w / 2, y: pr.minY - h - gap)
        case .left:   origin = NSPoint(x: pr.maxX + gap, y: pr.midY - h / 2)
        case .right:  origin = NSPoint(x: pr.minX - w - gap, y: pr.midY - h / 2)
        }
        p.setFrame(NSRect(origin: origin, size: NSSize(width: w, height: h)), display: true)
    }

    private func hideHint() {
        hintDelay?.cancel(); hintDelay = nil
        guard let p = hint, p.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.12; p.animator().alphaValue = 0 },
                                             completionHandler: {
            if p.alphaValue == 0 { p.orderOut(nil) }   // skip if a new hover brought it back mid-fade
        })
    }

    private func apply(animated: Bool, gentle: Bool = false) {
        let visible = mode != .idle || idleVisible
        let target = frame(for: mode)
        if visible { panel.orderFrontRegardless() }
        let finish = { [weak self] in
            guard let self, self.mode == .idle, !self.idleVisible else { return }
            self.panel.orderOut(nil)
        }
        if animated {
            NSAnimationContext.runAnimationGroup({ ctx in
                if gentle {   // hover: smooth ease-out, no bounce
                    ctx.duration = 0.18
                    ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 0.1, 0.25, 1)
                } else {
                    ctx.duration = 0.22
                    ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1.1)   // slight overshoot = pop
                }
                panel.animator().setFrame(target, display: true)
            }, completionHandler: finish)
        } else {
            panel.setFrame(target, display: true)
            finish()
        }
    }

    // MARK: result card

    /// Shows the dictated text with a Copy button, next to the pill.
    func showCard(_ text: String) {
        dismissCard()
        hideHint()
        cardText = text

        let width: CGFloat = 360, inset: CGFloat = 14
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: width - 2 * inset, height: 10))
        textView.string = text
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textColor = .white
        textView.font = .systemFont(ofSize: 13)
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
        let used = textView.layoutManager?.usedRect(for: textView.textContainer!).height ?? 20
        let textH = min(max(ceil(used), 20), 200)

        let headerH: CGFloat = 16, buttonH: CGFloat = 28, gap: CGFloat = 10
        let height = inset + headerH + gap + textH + gap + buttonH + inset

        let bg = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        bg.material = .hudWindow
        bg.appearance = NSAppearance(named: .vibrantDark)
        bg.state = .active
        bg.wantsLayer = true
        bg.layer?.cornerRadius = 14
        bg.layer?.masksToBounds = true

        var y = height - inset - headerH
        let header = NSTextField(labelWithString: "WisprLite · nothing to paste into")
        header.font = .systemFont(ofSize: 11, weight: .medium)
        header.textColor = .secondaryLabelColor
        header.frame = NSRect(x: inset, y: y, width: width - 2 * inset - 24, height: headerH)
        bg.addSubview(header)

        let close = NSButton(title: "✕", target: self, action: #selector(dismissCard))
        close.isBordered = false
        close.contentTintColor = .secondaryLabelColor
        close.frame = NSRect(x: width - inset - 22, y: y - 2, width: 22, height: 20)
        bg.addSubview(close)

        // Countdown ring around the close button: starts full at 12 o'clock and drains as the card's time runs out.
        let ring = CAShapeLayer()
        let center = CGPoint(x: close.frame.midX, y: close.frame.midY)
        let path = CGMutablePath()
        path.addArc(center: center, radius: 10, startAngle: .pi / 2, endAngle: -3 * .pi / 2, clockwise: true)
        ring.path = path
        ring.fillColor = nil
        ring.strokeColor = NSColor.white.withAlphaComponent(0.75).cgColor
        ring.lineWidth = 1.5
        ring.lineCap = .round
        bg.layer?.addSublayer(ring)
        self.ring = ring

        y -= gap + textH
        let scroll = NSScrollView(frame: NSRect(x: inset, y: y, width: width - 2 * inset, height: textH))
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = used > 200
        scroll.documentView = textView
        bg.addSubview(scroll)

        let copy = NSButton(title: "Copy", target: self, action: #selector(copyCard))
        copy.bezelStyle = .rounded
        copy.controlSize = .large
        copy.keyEquivalent = "\r"
        copy.frame = NSRect(x: width - inset - 90, y: inset, width: 90, height: buttonH)
        bg.addSubview(copy)
        copyButton = copy

        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .statusBar
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView = bg

        let screen = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        let pr = pillRect(for: .listening)
        var origin: NSPoint
        switch position {
        case .right:  origin = NSPoint(x: pr.minX - width - 8, y: pr.midY - height / 2)
        case .left:   origin = NSPoint(x: pr.maxX + 8, y: pr.midY - height / 2)
        case .bottom: origin = NSPoint(x: pr.midX - width / 2, y: pr.maxY + 8)
        case .top:    origin = NSPoint(x: pr.midX - width / 2, y: pr.minY - height - 8)
        }
        origin.x = min(max(origin.x, screen.minX + 8), screen.maxX - width - 8)
        origin.y = min(max(origin.y, screen.minY + 8), screen.maxY - height - 8)
        p.setFrameOrigin(origin)
        p.alphaValue = 0
        p.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.18; p.animator().alphaValue = 1 }
        card = p
        startCardTimer()
    }

    /// Counts down `cardLifetime` seconds, draining the ring, then fades the card out.
    /// The countdown pauses while the mouse is over the card (reading or selecting text).
    private func startCardTimer() {
        cardTimer?.invalidate()
        cardRemaining = Overlay.cardLifetime
        let step = 0.1
        cardTimer = Timer.scheduledTimer(withTimeInterval: step, repeats: true) { [weak self] _ in
            guard let self, let p = self.card else { return }
            if p.frame.contains(NSEvent.mouseLocation) { return }
            self.cardRemaining -= step
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.ring?.strokeEnd = CGFloat(max(self.cardRemaining, 0) / Overlay.cardLifetime)
            CATransaction.commit()
            guard self.cardRemaining <= 0 else { return }
            self.cardTimer?.invalidate()
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.25; p.animator().alphaValue = 0 },
                                                 completionHandler: { if self.card === p { self.dismissCard() } })
        }
    }

    @objc private func copyCard() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(cardText, forType: .string)
        copyButton?.title = "Copied ✓"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in self?.dismissCard() }
    }

    @objc func dismissCard() {
        cardTimer?.invalidate()
        cardTimer = nil
        ring = nil
        card?.orderOut(nil)
        card = nil
        copyButton = nil
    }
}

/// The pill itself: a dark capsule with five bars that glow while listening.
final class PillView: NSView {
    var mode: Overlay.Mode = .idle { didSet { needsLayout = true } }
    /// Horizontal pill (top/bottom): bars stack vertically and grow sideways. Vertical pill: the reverse.
    var horizontal = true { didSet { needsLayout = true } }
    /// Mouse is over the pill while idle: brighter bars and border.
    var hover = false {
        didSet {
            guard hover != oldValue else { return }
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.18)
            render()
            CATransaction.commit()
        }
    }
    var onHover: ((Bool) -> Void)?
    var onClick: (() -> Void)?

    static let count = 9
    static let weights: [CGFloat] = [0.35, 0.55, 0.8, 0.95, 1.0, 0.95, 0.8, 0.55, 0.35]
    private let capsule = CALayer()
    private let bars: [CALayer] = (0..<PillView.count).map { _ in CALayer() }
    private var heights = [CGFloat](repeating: 0, count: PillView.count)
    private var phase: CGFloat = 0
    private let glow = NSColor(calibratedRed: 0.35, green: 0.62, blue: 1.0, alpha: 1)

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        capsule.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 0.92).cgColor
        capsule.borderWidth = 1
        capsule.shadowOffset = .zero
        layer?.addSublayer(capsule)
        for b in bars {
            b.backgroundColor = NSColor.white.cgColor
            b.shadowColor = glow.cgColor
            b.shadowOffset = .zero
            capsule.addSublayer(b)
        }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onClick?() }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        capsule.frame = bounds.insetBy(dx: Overlay.padValue, dy: Overlay.padValue)
        capsule.cornerRadius = min(capsule.bounds.width, capsule.bounds.height) / 2
        render()
        CATransaction.commit()
    }

    /// Advance the animation one frame. `level` is the smoothed-by-us mic level 0...1.
    func tick(level: CGFloat) {
        phase += 0.28
        let weights = PillView.weights
        let maxH = (horizontal ? capsule.bounds.height : capsule.bounds.width) - 6
        for i in 0..<PillView.count {
            var target: CGFloat
            switch mode {
            case .listening: target = 5 + level * maxH * weights[i] * (0.75 + 0.25 * sin(phase + CGFloat(i) * 0.9))
            case .processing: target = 6 + (maxH * 0.5) * (0.5 + 0.5 * sin(phase - CGFloat(i) * 0.7))
            case .idle: target = 4
            }
            heights[i] += (target - heights[i]) * 0.45
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        render(level: level)
        CATransaction.commit()
    }

    private func render(level: CGFloat = 0) {
        let active = mode != .idle
        let thick: CGFloat = 2
        let gap: CGFloat = active || hover ? 2.5 : 2
        let n = CGFloat(PillView.count)
        let total = n * thick + (n - 1) * gap
        // Horizontal pill: bars stand side by side along x and grow up/down. Vertical pill: the same, rotated.
        let along = horizontal ? capsule.bounds.width : capsule.bounds.height
        let cross = horizontal ? capsule.bounds.height : capsule.bounds.width
        let start = (along - total) / 2
        let glowLevel: CGFloat = mode == .listening ? level : (mode == .processing ? 0.4 : 0)
        for (i, b) in bars.enumerated() {
            // Hovered while idle: a calm, still waveform that says "ready".
            let len = active ? min(max(heights[i], 2), cross - 4) : (hover ? min(3 + 7 * PillView.weights[i], cross - 8) : 2)
            let c = start + CGFloat(i) * (thick + gap)
            let o = (cross - len) / 2
            b.frame = horizontal ? NSRect(x: c, y: o, width: thick, height: len) : NSRect(x: o, y: c, width: len, height: thick)
            b.cornerRadius = thick / 2
            b.opacity = active ? 1 : (hover ? 0.8 : 0.35)
            b.shadowOpacity = Float(active ? 0.6 + 0.4 * glowLevel : 0)
            b.shadowRadius = 2 + glowLevel * 5
        }
        capsule.borderColor = (active ? glow.withAlphaComponent(0.35 + 0.5 * glowLevel) : NSColor(white: 1, alpha: hover ? 0.3 : 0.12)).cgColor
        capsule.shadowColor = glow.cgColor
        capsule.shadowOpacity = Float(active ? 0.35 + 0.65 * glowLevel : 0)
        capsule.shadowRadius = 4 + glowLevel * 8
    }
}

extension Overlay {
    static var padValue: CGFloat { pad }
}
