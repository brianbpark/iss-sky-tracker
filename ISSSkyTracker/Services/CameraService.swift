import AVFoundation

/// Runs the back camera for the live sky view and reports its field of view.
final class CameraService: ObservableObject {
    let session = AVCaptureSession()
    /// Vertical field of view of the portrait preview, in degrees.
    @Published private(set) var verticalFOV: Double = 60
    @Published private(set) var isDenied = false
    @Published private(set) var isUnavailable = false

    private let queue = DispatchQueue(label: "camera.session")
    private var configured = false

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            run()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted { self.run() } else { self.isDenied = true }
                }
            }
        default:
            isDenied = true
        }
    }

    func stop() {
        queue.async { if self.session.isRunning { self.session.stopRunning() } }
    }

    private func run() {
        queue.async {
            if !self.configured {
                guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                      let input = try? AVCaptureDeviceInput(device: device) else {
                    DispatchQueue.main.async { self.isUnavailable = true }
                    return
                }
                self.session.beginConfiguration()
                self.session.sessionPreset = .high
                if self.session.canAddInput(input) { self.session.addInput(input) }
                self.session.commitConfiguration()
                // videoFieldOfView is measured across the sensor's long side, which is
                // the vertical axis of the screen when the phone is held upright.
                let fov = Double(device.activeFormat.videoFieldOfView)
                DispatchQueue.main.async { if fov > 0 { self.verticalFOV = fov } }
                self.configured = true
            }
            if !self.session.isRunning { self.session.startRunning() }
        }
    }
}
