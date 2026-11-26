import SwiftUI

/// Camera view: point the phone at the sky to see where the ISS is and where it will pass.
struct SkyView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var motion = MotionService()
    @StateObject private var camera = CameraService()

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.02, green: 0.03, blue: 0.12), .black],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            if !camera.isDenied && !camera.isUnavailable {
                CameraPreview(session: camera.session).ignoresSafeArea()
            }
            if let rotation = motion.rotation {
                SkyOverlay(rotation: rotation, verticalFOV: camera.verticalFOV,
                           pass: model.skyPass, now: model.now)
                    .ignoresSafeArea()
            }
            VStack(spacing: 10) {
                NowCard(now: model.now, placeName: model.location.placeName)
                notices
                Spacer()
                PassBanner(pass: model.skyPass, now: model.now, isSelected: model.selectedPass != nil) {
                    model.selectedPass = nil
                }
            }
            .padding()
        }
        .onAppear { camera.start(); motion.start() }
        .onDisappear { camera.stop(); motion.stop() }
    }

    @ViewBuilder private var notices: some View {
        if model.location.isDenied {
            Notice(icon: "location.slash", text: "Location access is off. Turn it on in Settings to predict passes for where you are.")
        }
        if motion.isUnavailable {
            Notice(icon: "gyroscope", text: "This device has no compass/motion sensors, so the sky overlay can't be shown. Use the Passes tab.")
        } else if motion.needsCalibration {
            Notice(icon: "arrow.triangle.2.circlepath", text: "Compass needs calibrating: move your phone in a figure-8.")
        }
        if camera.isDenied {
            Notice(icon: "camera", text: "Camera access is off. The overlay still works, but you won't see the sky behind it.")
        }
        if let error = model.errorMessage {
            Notice(icon: "wifi.exclamationmark", text: error)
        }
    }
}

private struct Notice: View {
    let icon: String
    let text: String
    var body: some View {
        Label(text, systemImage: icon)
            .font(.footnote)
            .foregroundStyle(.white)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.orange.opacity(0.8), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Where the ISS is right now.
private struct NowCard: View {
    let now: ISSNow?
    let placeName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("ISS NOW").font(.caption.bold()).foregroundStyle(.cyan)
                Spacer()
                if let placeName { Text(placeName).font(.caption).foregroundStyle(.secondary) }
            }
            if let now {
                let sky = now.sky
                Text(sky.elevation > 0
                     ? "Above you: \(Int(sky.elevation.rounded()))° up in the \(sky.compass)"
                     : "Below your horizon (\(sky.compass), \(Int(sky.elevation.rounded()))°)")
                    .font(.headline)
                Text(String(format: "Over %.1f°%@, %.1f°%@ · %.0f km up · %.2f km/s",
                            abs(now.latitude), now.latitude >= 0 ? "N" : "S",
                            abs(now.longitude), now.longitude >= 0 ? "E" : "W",
                            now.altitudeKm, now.speedKmS))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else {
                Text("Finding your location and the ISS…").font(.headline)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .environment(\.colorScheme, .dark)
    }
}

/// When and where to look for the pass drawn in the sky.
private struct PassBanner: View {
    let pass: ISSPass?
    let now: ISSNow?
    let isSelected: Bool
    let clearSelection: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let pass {
                let inProgress = pass.rise.date <= Date()
                HStack {
                    Text(title(pass, inProgress: inProgress)).font(.caption.bold()).foregroundStyle(.yellow)
                    Spacer()
                    if isSelected {
                        Button("Show next", action: clearSelection).font(.caption)
                    }
                }
                Text("\(pass.displayStart.date.dayTitle), \(pass.displayStart.date.clock)")
                    .font(.title2.bold())
                Text("Appears \(pass.displayStart.compass), climbs to \(Int(pass.displayPeak.rounded()))°, disappears \(pass.displayEnd.compass)")
                    .font(.subheadline)
                if !pass.isVisible, let reason = pass.invisibilityReason {
                    Text("Not visible: \(reason.lowercased())").font(.caption).foregroundStyle(.secondary)
                } else if !inProgress {
                    Text("Starts \(pass.displayStart.date, style: .relative) from now · lasts \(pass.displayEnd.date.timeIntervalSince(pass.displayStart.date).minutesText)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("Calculating passes…").font(.headline)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .environment(\.colorScheme, .dark)
    }

    private func title(_ pass: ISSPass, inProgress: Bool) -> String {
        if inProgress { return pass.isVisible ? "HAPPENING NOW – LOOK UP!" : "PASSING OVERHEAD NOW" }
        if isSelected { return "SELECTED PASS" }
        return pass.isVisible ? "NEXT VISIBLE PASS" : "NEXT PASS"
    }
}
