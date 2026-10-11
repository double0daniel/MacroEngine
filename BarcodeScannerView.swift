import SwiftUI
import AVFoundation

/// Full-screen live barcode scanner. Requires `NSCameraUsageDescription` in Info.plist.
struct BarcodeScannerView: View {
    let onScan: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var permission = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var torchOn = false

    private var hasTorch: Bool { AVCaptureDevice.default(for: .video)?.hasTorch == true }

    var body: some View {
        ZStack {
            Slate.background.ignoresSafeArea()

            switch permission {
            case .authorized:
                scanner
            case .notDetermined:
                ProgressView().tint(Slate.textSecondary)
            default:
                CameraPermissionView()
            }
        }
        .overlay(alignment: .top) { topBar }
        .task {
            guard permission == .notDetermined else { return }
            _ = await AVCaptureDevice.requestAccess(for: .video)
            permission = AVCaptureDevice.authorizationStatus(for: .video)
        }
        .preferredColorScheme(.dark)
    }

    private var scanner: some View {
        ZStack {
            CameraPreview(torchOn: torchOn) { code in
                onScan(code)
                dismiss()
            }
            .ignoresSafeArea()

            ViewfinderCorners()
                .stroke(Slate.textPrimary, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                .frame(width: 300, height: 190)
                .accessibilityHidden(true)

            VStack {
                Spacer()
                Text("Align the barcode inside the frame")
                    .font(.meBody)
                    .foregroundStyle(Slate.textPrimary)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(Slate.background.opacity(0.85), in: Capsule())
                    .padding(.bottom, 48)
            }
        }
    }

    private var topBar: some View {
        HStack {
            circleButton(symbol: "xmark", label: "Close") { dismiss() }
            Spacer()
            if permission == .authorized && hasTorch {
                circleButton(symbol: torchOn ? "flashlight.on.fill" : "flashlight.off.fill",
                             label: torchOn ? "Turn flashlight off" : "Turn flashlight on") {
                    torchOn.toggle()
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private func circleButton(symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Slate.textPrimary)
                .frame(width: 44, height: 44)
                .background(Slate.background.opacity(0.85), in: Circle())
        }
        .accessibilityLabel(label)
    }
}

// MARK: - Permission denied

private struct CameraPermissionView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        EmptyStateView(
            symbol: "video.slash.fill",
            title: "Camera access is off",
            message: "Turn on camera access in Settings to scan barcodes, or search for foods by name instead.",
            actionTitle: "Open Settings"
        ) {
            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
        }
        .padding(.horizontal, 24)
    }
}

// MARK: - Viewfinder

private struct ViewfinderCorners: Shape {
    var length: CGFloat = 30
    var radius: CGFloat = 18

    func path(in r: CGRect) -> Path {
        var p = Path()
        // top-left
        p.move(to: CGPoint(x: r.minX, y: r.minY + length))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + radius))
        p.addQuadCurve(to: CGPoint(x: r.minX + radius, y: r.minY), control: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + length, y: r.minY))
        // top-right
        p.move(to: CGPoint(x: r.maxX - length, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - radius, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY + radius), control: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + length))
        // bottom-right
        p.move(to: CGPoint(x: r.maxX, y: r.maxY - length))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - radius))
        p.addQuadCurve(to: CGPoint(x: r.maxX - radius, y: r.maxY), control: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - length, y: r.maxY))
        // bottom-left
        p.move(to: CGPoint(x: r.minX + length, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + radius, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY - radius), control: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY - length))
        return p
    }
}

// MARK: - AVFoundation bridge

private struct CameraPreview: UIViewControllerRepresentable {
    var torchOn: Bool
    var onCode: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerController {
        let controller = ScannerController()
        controller.onCode = onCode
        return controller
    }

    func updateUIViewController(_ controller: ScannerController, context: Context) {
        controller.onCode = onCode
        controller.setTorch(torchOn)
    }
}

private final class ScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: ((String) -> Void)?

    private let session = AVCaptureSession()
    private let previewLayer = AVCaptureVideoPreviewLayer()
    private var device: AVCaptureDevice?
    private var didReport = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        configureSession()
        previewLayer.session = session
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        didReport = false
        let session = session
        DispatchQueue.global(qos: .userInitiated).async {
            if !session.isRunning { session.startRunning() }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        setTorch(false)
        let session = session
        DispatchQueue.global(qos: .userInitiated).async {
            if session.isRunning { session.stopRunning() }
        }
    }

    private func configureSession() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }
        session.addInput(input)
        self.device = device

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)

        let wanted: [AVMetadataObject.ObjectType] = [.ean13, .ean8, .upce, .code128, .code39]
        output.metadataObjectTypes = wanted.filter { output.availableMetadataObjectTypes.contains($0) }
    }

    func setTorch(_ on: Bool) {
        guard let device, device.hasTorch else { return }
        let mode: AVCaptureDevice.TorchMode = on ? .on : .off
        guard device.torchMode != mode else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = mode
            device.unlockForConfiguration()
        } catch {
            // Torch is a nicety; ignore failures.
        }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard !didReport,
              let code = (metadataObjects.first as? AVMetadataMachineReadableCodeObject)?.stringValue
        else { return }
        didReport = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onCode?(code)
    }
}
