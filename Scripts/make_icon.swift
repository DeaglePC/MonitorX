import AppKit

// Renders the MonitorX app icon (dark glassy squircle + gradient ring gauge) into an .iconset directory.
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext

    let inset = s * 0.055
    let rect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let squircle = NSBezierPath(roundedRect: rect, xRadius: s * 0.225, yRadius: s * 0.225)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    NSColor.black.setFill(); squircle.fill()
    ctx.restoreGState()

    ctx.saveGState()
    squircle.addClip()
    let bg = NSGradient(colors: [NSColor(red: 0.10, green: 0.11, blue: 0.24, alpha: 1), NSColor(red: 0.03, green: 0.04, blue: 0.10, alpha: 1)])!
    bg.draw(in: rect, angle: -60)
    // soft colored glow
    let glow = NSGradient(colors: [NSColor(red: 0.30, green: 0.55, blue: 1, alpha: 0.45), .clear])!
    glow.draw(fromCenter: CGPoint(x: s * 0.3, y: s * 0.8), radius: 0, toCenter: CGPoint(x: s * 0.3, y: s * 0.8), radius: s * 0.75, options: [])
    let glow2 = NSGradient(colors: [NSColor(red: 0.75, green: 0.35, blue: 1, alpha: 0.35), .clear])!
    glow2.draw(fromCenter: CGPoint(x: s * 0.85, y: s * 0.15), radius: 0, toCenter: CGPoint(x: s * 0.85, y: s * 0.15), radius: s * 0.6, options: [])
    ctx.restoreGState()

    // ring gauge
    let center = CGPoint(x: s / 2, y: s / 2)
    let radius = s * 0.29
    let lw = s * 0.085
    let track = NSBezierPath()
    track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
    track.lineWidth = lw
    NSColor.white.withAlphaComponent(0.13).setStroke(); track.stroke()

    let steps = 60
    let start: CGFloat = 90, sweep: CGFloat = 250
    let colors = [NSColor(red: 0.35, green: 0.85, blue: 1, alpha: 1), NSColor(red: 0.45, green: 0.5, blue: 1, alpha: 1), NSColor(red: 0.85, green: 0.4, blue: 1, alpha: 1)]
    for i in 0..<steps {
        let t0 = CGFloat(i) / CGFloat(steps), t1 = CGFloat(i + 1) / CGFloat(steps) + 0.004
        let a0 = start - sweep * t0, a1 = start - sweep * min(t1, 1)
        let seg = NSBezierPath()
        seg.appendArc(withCenter: center, radius: radius, startAngle: a0, endAngle: a1, clockwise: true)
        seg.lineWidth = lw
        seg.lineCapStyle = (i == 0 || i == steps - 1) ? .round : .butt
        let f = t0 * 2
        let c = f < 1 ? colors[0].blended(withFraction: f, of: colors[1])! : colors[1].blended(withFraction: f - 1, of: colors[2])!
        c.setStroke(); seg.stroke()
    }
    // needle dot
    let a = (start - sweep) * .pi / 180
    let dot = NSBezierPath(ovalIn: CGRect(x: center.x + cos(a) * radius - lw * 0.32, y: center.y + sin(a) * radius - lw * 0.32, width: lw * 0.64, height: lw * 0.64))
    NSColor.white.setFill(); dot.fill()

    // center bars
    let bw = s * 0.045, gap = s * 0.028
    let heights: [CGFloat] = [0.07, 0.12, 0.09, 0.15]
    let total = bw * 4 + gap * 3
    for (i, h) in heights.enumerated() {
        let r = CGRect(x: center.x - total / 2 + CGFloat(i) * (bw + gap), y: center.y - s * 0.075, width: bw, height: s * h)
        NSColor.white.withAlphaComponent(0.92).setFill()
        NSBezierPath(roundedRect: r, xRadius: bw / 2, yRadius: bw / 2).fill()
    }

    // top highlight (glass edge)
    ctx.saveGState()
    squircle.addClip()
    let hl = NSGradient(colors: [NSColor.white.withAlphaComponent(0.22), .clear])!
    hl.draw(in: CGRect(x: rect.minX, y: rect.midY, width: rect.width, height: rect.height / 2), angle: -90)
    ctx.restoreGState()
    let edge = NSBezierPath(roundedRect: rect.insetBy(dx: s * 0.002, dy: s * 0.002), xRadius: s * 0.225, yRadius: s * 0.225)
    edge.lineWidth = s * 0.004
    NSColor.white.withAlphaComponent(0.25).setStroke(); edge.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: URL(fileURLWithPath: "\(out)/icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: URL(fileURLWithPath: "\(out)/icon_\(base)x\(base)@2x.png"))
}
