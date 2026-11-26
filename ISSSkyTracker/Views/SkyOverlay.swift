import SwiftUI

/// Maps sky directions (azimuth/elevation) to points on the screen using the phone's orientation.
struct SkyProjection {
    /// Row-major rotation from the (north, west, up) frame into device coordinates.
    let m: [Double]
    let size: CGSize
    let focal: Double

    init(rotation: [Double], size: CGSize, verticalFOV: Double) {
        m = rotation
        self.size = size
        focal = Double(size.height) / 2 / tan(verticalFOV / 2 * Astro.deg)
    }

    func deviceVector(azimuth: Double, elevation: Double) -> Vec3 {
        let a = azimuth * Astro.deg, e = elevation * Astro.deg
        let north = cos(e) * cos(a), west = -cos(e) * sin(a), up = sin(e)
        return Vec3(x: m[0] * north + m[1] * west + m[2] * up,
                    y: m[3] * north + m[4] * west + m[5] * up,
                    z: m[6] * north + m[7] * west + m[8] * up)
    }

    /// Screen point for a sky direction, or nil if it is behind the camera.
    func project(azimuth: Double, elevation: Double) -> CGPoint? {
        let d = deviceVector(azimuth: azimuth, elevation: elevation)
        guard -d.z > 0.08 else { return nil }      // the camera looks along -z
        return CGPoint(x: Double(size.width) / 2 + focal * d.x / -d.z,
                       y: Double(size.height) / 2 - focal * d.y / -d.z)
    }

    func isOnScreen(_ p: CGPoint, inset: CGFloat = 0) -> Bool {
        CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset).contains(p)
    }

    /// Screen-space angle (radians, 0 = right, positive = down) toward a sky direction.
    func screenDirection(azimuth: Double, elevation: Double) -> Double {
        let d = deviceVector(azimuth: azimuth, elevation: elevation)
        return atan2(-d.y, d.x)
    }

    /// Where the camera is pointing.
    var pointing: (azimuth: Double, elevation: Double) {
        let north = -m[6], west = -m[7], up = -m[8]
        var az = atan2(-west, north) / Astro.deg
        if az < 0 { az += 360 }
        return (az, asin(max(-1, min(1, up))) / Astro.deg)
    }
}

/// Draws the horizon, compass points, the ISS trajectory and the ISS itself over the camera image.
struct SkyOverlay: View {
    let rotation: [Double]
    let verticalFOV: Double
    let pass: ISSPass?
    let now: ISSNow?

    var body: some View {
        GeometryReader { geo in
            let proj = SkyProjection(rotation: rotation, size: geo.size, verticalFOV: verticalFOV)
            Canvas { ctx, size in
                drawHorizon(&ctx, proj)
                if let pass { drawPass(&ctx, proj, pass) }
                drawISS(&ctx, proj)
                drawGuideArrow(&ctx, proj, size)
            }
            .overlay(alignment: .center) { crosshair(proj) }
        }
        .allowsHitTesting(false)
    }

    // MARK: Horizon and compass

    private func drawHorizon(_ ctx: inout GraphicsContext, _ proj: SkyProjection) {
        var horizon = Path()
        var penDown = false
        for az in stride(from: 0.0, through: 360.0, by: 2) {
            if let p = proj.project(azimuth: az, elevation: 0) {
                penDown ? horizon.addLine(to: p) : horizon.move(to: p)
                penDown = true
            } else {
                penDown = false
            }
        }
        ctx.stroke(horizon, with: .color(.white.opacity(0.45)), style: StrokeStyle(lineWidth: 1.5, dash: [6, 6]))

        let points: [(String, Double)] = [("N", 0), ("NE", 45), ("E", 90), ("SE", 135),
                                          ("S", 180), ("SW", 225), ("W", 270), ("NW", 315)]
        for (label, az) in points {
            guard let p = proj.project(azimuth: az, elevation: 0) else { continue }
            let main = label.count == 1
            ctx.draw(Text(label)
                        .font(main ? .headline.bold() : .caption.bold())
                        .foregroundColor(label == "N" ? .red : .white),
                     at: CGPoint(x: p.x, y: p.y - 14))
        }
    }

    // MARK: Trajectory

    private func drawPass(_ ctx: inout GraphicsContext, _ proj: SkyProjection, _ pass: ISSPass) {
        var visible = Path(), hidden = Path()
        var last: (CGPoint, Bool)?
        for s in pass.path {
            guard let p = proj.project(azimuth: s.azimuth, elevation: s.elevation) else { last = nil; continue }
            let isVis = s.isNakedEyeVisible
            if let (lp, lv) = last {
                var seg = Path(); seg.move(to: lp); seg.addLine(to: p)
                if isVis && lv { visible.addPath(seg) } else { hidden.addPath(seg) }
            }
            last = (p, isVis)
        }
        ctx.stroke(hidden, with: .color(.white.opacity(0.6)), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [3, 7]))
        ctx.stroke(visible, with: .color(.yellow.opacity(0.35)), style: StrokeStyle(lineWidth: 10, lineCap: .round))
        ctx.stroke(visible, with: .color(.yellow), style: StrokeStyle(lineWidth: 3.5, lineCap: .round))

        // Time ticks once a minute.
        for s in pass.path where Int(s.date.timeIntervalSince1970) % 60 < 5 {
            guard let p = proj.project(azimuth: s.azimuth, elevation: s.elevation), proj.isOnScreen(p) else { continue }
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6)), with: .color(.white))
            ctx.draw(Text(s.date.clock).font(.caption2.monospacedDigit()).foregroundColor(.white),
                     at: CGPoint(x: p.x + 6, y: p.y + 4), anchor: .topLeading)
        }

        // Start and end markers.
        let start = pass.displayStart, end = pass.displayEnd
        if let p = proj.project(azimuth: start.azimuth, elevation: start.elevation) {
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - 6, y: p.y - 6, width: 12, height: 12)), with: .color(.green))
            ctx.draw(Text("Appears \(start.date.clock)").font(.caption.bold()).foregroundColor(.green),
                     at: CGPoint(x: p.x, y: p.y - 12), anchor: .bottom)
        }
        if let p = proj.project(azimuth: end.azimuth, elevation: end.elevation) {
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - 6, y: p.y - 6, width: 12, height: 12)), with: .color(.red))
            ctx.draw(Text("Gone \(end.date.clock)").font(.caption.bold()).foregroundColor(.red),
                     at: CGPoint(x: p.x, y: p.y - 12), anchor: .bottom)
        }
    }

    // MARK: ISS marker

    private func drawISS(_ ctx: inout GraphicsContext, _ proj: SkyProjection) {
        guard let sky = now?.sky, sky.elevation > -1,
              let p = proj.project(azimuth: sky.azimuth, elevation: sky.elevation) else { return }
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - 18, y: p.y - 18, width: 36, height: 36)), with: .color(.cyan.opacity(0.25)))
        ctx.stroke(Path(ellipseIn: CGRect(x: p.x - 18, y: p.y - 18, width: 36, height: 36)), with: .color(.cyan), lineWidth: 2)
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8)), with: .color(.white))
        ctx.draw(Text("ISS  \(Int(sky.elevation.rounded()))°").font(.headline).foregroundColor(.cyan),
                 at: CGPoint(x: p.x, y: p.y + 24), anchor: .top)
    }

    /// Arrow at the screen edge pointing toward the ISS (if up) or where it will appear.
    private func drawGuideArrow(_ ctx: inout GraphicsContext, _ proj: SkyProjection, _ size: CGSize) {
        let target: (az: Double, el: Double, label: String)
        if let sky = now?.sky, sky.elevation > 0 {
            target = (sky.azimuth, sky.elevation, "ISS")
        } else if let pass {
            target = (pass.displayStart.azimuth, pass.displayStart.elevation, "Appears here")
        } else {
            return
        }
        if let p = proj.project(azimuth: target.az, elevation: target.el), proj.isOnScreen(p, inset: 30) { return }

        let angle = proj.screenDirection(azimuth: target.az, elevation: target.el)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let rx = size.width / 2 - 44, ry = size.height / 2 - 140
        let tip = CGPoint(x: center.x + rx * cos(angle), y: center.y + ry * sin(angle))

        var arrow = Path()
        arrow.move(to: CGPoint(x: 18, y: 0))
        arrow.addLine(to: CGPoint(x: -12, y: -13))
        arrow.addLine(to: CGPoint(x: -6, y: 0))
        arrow.addLine(to: CGPoint(x: -12, y: 13))
        arrow.closeSubpath()
        let transform = CGAffineTransform(translationX: tip.x, y: tip.y).rotated(by: angle)
        ctx.fill(arrow.applying(transform), with: .color(.yellow))
        let labelPoint = CGPoint(x: tip.x - 34 * cos(angle), y: tip.y - 34 * sin(angle))
        ctx.draw(Text(target.label).font(.caption.bold()).foregroundColor(.yellow), at: labelPoint)
    }

    private func crosshair(_ proj: SkyProjection) -> some View {
        let p = proj.pointing
        return VStack(spacing: 6) {
            Image(systemName: "plus")
                .font(.system(size: 28, weight: .ultraLight))
                .foregroundStyle(.white.opacity(0.7))
            Text("\(Int(p.azimuth.rounded()))° \(Astro.compass(p.azimuth)) · \(Int(p.elevation.rounded()))° up")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.8))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(.black.opacity(0.35), in: Capsule())
        }
        .offset(y: 22)
    }
}
