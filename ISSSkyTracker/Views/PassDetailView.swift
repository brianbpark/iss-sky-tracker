import SwiftUI

/// One pass: a sky chart of its path plus when and where to look.
struct PassDetailView: View {
    @EnvironmentObject private var model: AppModel
    let pass: ISSPass
    @State private var reminderSet = false
    @State private var reminderMessage: String?

    var body: some View {
        List {
            Section {
                SkyChartView(pass: pass)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1, contentMode: .fit)
                    .padding(.vertical, 8)
            } footer: {
                Text("Looking straight up: the center is overhead, the edge is the horizon. Yellow is where the ISS is bright enough to see.")
            }

            Section(pass.isVisible ? "When to look" : "Pass (not visible)") {
                if let reason = pass.invisibilityReason {
                    Label(reason, systemImage: "eye.slash").foregroundStyle(.secondary)
                }
                row("Appears", pass.displayStart)
                LabeledContent("Highest") {
                    Text("\(Int(pass.displayPeak.rounded()))° up · \(pass.culmination.date.clockWithSeconds)")
                }
                row("Disappears", pass.displayEnd)
                LabeledContent("Duration",
                               value: pass.displayEnd.date.timeIntervalSince(pass.displayStart.date).minutesText)
                LabeledContent("Closest distance",
                               value: "\(Int(pass.path.map(\.rangeKm).min() ?? 0)) km")
            }

            Section {
                Button {
                    model.selectedPass = pass
                    model.tab = .sky
                } label: {
                    Label("Show this pass in the sky", systemImage: "camera.viewfinder")
                }
                if pass.isVisible, pass.displayStart.date.timeIntervalSinceNow > NotificationService.leadTime {
                    Button {
                        Task { await toggleReminder() }
                    } label: {
                        Label(reminderSet ? "Cancel reminder" : "Remind me 10 minutes before",
                              systemImage: reminderSet ? "bell.slash" : "bell")
                    }
                }
                if let reminderMessage {
                    Text(reminderMessage).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(pass.displayStart.date.shortDay)
        .task { reminderSet = await NotificationService.isScheduled(pass) }
    }

    private func row(_ title: String, _ s: SkySample) -> some View {
        LabeledContent(title) {
            Text("\(s.date.clockWithSeconds) · \(s.compass) (\(Int(s.azimuth.rounded()))°) · \(Int(s.elevation.rounded()))° up")
                .multilineTextAlignment(.trailing)
        }
    }

    private func toggleReminder() async {
        if reminderSet {
            NotificationService.cancel(pass)
            reminderSet = false
            reminderMessage = nil
        } else if await NotificationService.schedule(pass) {
            reminderSet = true
            reminderMessage = "You'll get a notification at \(pass.displayStart.date.addingTimeInterval(-NotificationService.leadTime).clock)."
        } else {
            reminderMessage = "Couldn't set a reminder. Check that notifications are allowed for this app in Settings."
        }
    }
}

/// Polar sky chart: azimuth around the circle (north up), elevation from the edge (0°) to the center (90°).
struct SkyChartView: View {
    let pass: ISSPass

    var body: some View {
        Canvas { ctx, size in
            let r = min(size.width, size.height) / 2 - 18
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            func point(_ az: Double, _ el: Double) -> CGPoint {
                let d = r * (90 - max(0, el)) / 90
                return CGPoint(x: c.x + d * sin(az * Astro.deg), y: c.y - d * cos(az * Astro.deg))
            }

            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                     with: .color(Color(red: 0.05, green: 0.07, blue: 0.2)))
            for el in [30.0, 60.0] {
                let d = r * (90 - el) / 90
                ctx.stroke(Path(ellipseIn: CGRect(x: c.x - d, y: c.y - d, width: 2 * d, height: 2 * d)),
                           with: .color(.white.opacity(0.2)), lineWidth: 1)
                ctx.draw(Text("\(Int(el))°").font(.caption2).foregroundColor(.white.opacity(0.5)),
                         at: CGPoint(x: c.x + 10, y: c.y - d + 8))
            }
            var cross = Path()
            cross.move(to: CGPoint(x: c.x - r, y: c.y)); cross.addLine(to: CGPoint(x: c.x + r, y: c.y))
            cross.move(to: CGPoint(x: c.x, y: c.y - r)); cross.addLine(to: CGPoint(x: c.x, y: c.y + r))
            ctx.stroke(cross, with: .color(.white.opacity(0.15)), lineWidth: 1)
            for (label, az) in [("N", 0.0), ("E", 90.0), ("S", 180.0), ("W", 270.0)] {
                let p = CGPoint(x: c.x + (r + 10) * sin(az * Astro.deg), y: c.y - (r + 10) * cos(az * Astro.deg))
                ctx.draw(Text(label).font(.caption.bold()).foregroundColor(label == "N" ? .red : .primary), at: p)
            }

            var hidden = Path(), visible = Path()
            for (a, b) in zip(pass.path, pass.path.dropFirst()) {
                var seg = Path()
                seg.move(to: point(a.azimuth, a.elevation))
                seg.addLine(to: point(b.azimuth, b.elevation))
                if a.isNakedEyeVisible && b.isNakedEyeVisible { visible.addPath(seg) } else { hidden.addPath(seg) }
            }
            ctx.stroke(hidden, with: .color(.white.opacity(0.5)), style: StrokeStyle(lineWidth: 2, dash: [3, 5]))
            ctx.stroke(visible, with: .color(.yellow), style: StrokeStyle(lineWidth: 4, lineCap: .round))

            let start = point(pass.displayStart.azimuth, pass.displayStart.elevation)
            let end = point(pass.displayEnd.azimuth, pass.displayEnd.elevation)
            ctx.fill(Path(ellipseIn: CGRect(x: start.x - 5, y: start.y - 5, width: 10, height: 10)), with: .color(.green))
            ctx.fill(Path(ellipseIn: CGRect(x: end.x - 5, y: end.y - 5, width: 10, height: 10)), with: .color(.red))
            ctx.draw(Text(pass.displayStart.date.clock).font(.caption2.bold()).foregroundColor(.green),
                     at: CGPoint(x: start.x, y: start.y - 12))
            ctx.draw(Text(pass.displayEnd.date.clock).font(.caption2.bold()).foregroundColor(.red),
                     at: CGPoint(x: end.x, y: end.y - 12))
        }
    }
}
