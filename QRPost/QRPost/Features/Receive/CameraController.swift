import AVFoundation
import SwiftUI
import QRPostCore

/// 카메라 캡처와 QR 인식. AVCaptureMetadataOutput의 디스크립터에서
/// 심볼 버전과 오류 정정 완료된 원시 코드워드를 얻어 코어 파서에 넘긴다.
final class CameraController: NSObject, AVCaptureMetadataOutputObjectsDelegate {
    let captureSession = AVCaptureSession()
    private let metadataQueue = DispatchQueue(label: "kr.arcseed.qrpost.metadata")
    /// configure에서 한 번 설정된 뒤 델리게이트 큐에서 읽기만 한다
    private nonisolated(unsafe) var onPayloads: (@MainActor ([Data]) -> Void)?

    var isConfigured: Bool {
        !captureSession.inputs.isEmpty
    }

    func configure(onPayloads: @escaping @MainActor ([Data]) -> Void) -> Bool {
        self.onPayloads = onPayloads
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else {
            return false
        }

        captureSession.beginConfiguration()
        guard captureSession.canAddInput(input) else {
            captureSession.commitConfiguration()
            return false
        }
        captureSession.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard captureSession.canAddOutput(output) else {
            captureSession.commitConfiguration()
            return false
        }
        captureSession.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: metadataQueue)
        output.metadataObjectTypes = [.qr]
        captureSession.commitConfiguration()

        // 근접 촬영 고정 초점이 유리하지만 기본 연속 초점으로 시작한다 (#11 실측에서 튜닝)
        return true
    }

    func start() {
        guard isConfigured, !captureSession.isRunning else { return }
        metadataQueue.async { [captureSession] in
            captureSession.startRunning()
        }
    }

    func stop() {
        guard captureSession.isRunning else { return }
        metadataQueue.async { [captureSession] in
            captureSession.stopRunning()
        }
    }

    nonisolated func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        var payloads: [Data] = []
        for object in metadataObjects {
            guard let code = object as? AVMetadataMachineReadableCodeObject,
                  let descriptor = code.descriptor as? CIQRCodeDescriptor else { continue }
            if let payload = QRByteModeParser.payload(
                fromRawBitstream: descriptor.errorCorrectedPayload,
                version: Int(descriptor.symbolVersion)
            ) {
                payloads.append(payload)
            }
        }
        guard !payloads.isEmpty, let onPayloads else { return }
        let delivered = payloads
        Task { @MainActor in
            onPayloads(delivered)
        }
    }
}

/// AVCaptureVideoPreviewLayer를 SwiftUI에 노출한다
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override static var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}
