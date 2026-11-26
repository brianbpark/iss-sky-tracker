import CoreMotion

/// Publishes the phone's orientation relative to true north and the vertical.
final class MotionService: ObservableObject {
    /// Row-major 3x3 matrix taking a vector in the (north, west, up) frame into device coordinates
    /// (x = right edge of screen, y = top of screen, z = out of the screen toward the user).
    @Published private(set) var rotation: [Double]?
    @Published private(set) var needsCalibration = false
    @Published private(set) var isUnavailable = false

    private let manager = CMMotionManager()

    func start() {
        guard manager.isDeviceMotionAvailable,
              CMMotionManager.availableAttitudeReferenceFrames().contains(.xTrueNorthZVertical) else {
            isUnavailable = true
            return
        }
        guard !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 30
        manager.showsDeviceMovementDisplay = true   // lets iOS prompt for compass calibration
        manager.startDeviceMotionUpdates(using: .xTrueNorthZVertical, to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            let m = motion.attitude.rotationMatrix
            self.rotation = [m.m11, m.m12, m.m13,
                             m.m21, m.m22, m.m23,
                             m.m31, m.m32, m.m33]
            self.needsCalibration = motion.magneticField.accuracy == .uncalibrated
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
    }
}
