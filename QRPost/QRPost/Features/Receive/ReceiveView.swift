import SwiftUI
import AVFoundation
import QRPostCore

struct ReceiveView: View {
    @State private var model = ReceiveModel()
    @State private var camera = CameraController()

    var body: some View {
        ZStack {
            QP.ColorToken.background.ignoresSafeArea()

            if model.phase == .completed, let file = model.result {
                ReceivedFileView(file: file) {
                    model.reset()
                }
            } else if model.isPermissionDenied {
                deniedView
            } else {
                scannerView
            }
        }
        .task {
            await requestCameraAndStart()
        }
        .onDisappear {
            camera.stop()
        }
    }

    // MARK: - 스캔 화면

    private var scannerView: some View {
        VStack(spacing: 0) {
            ZStack {
                if camera.isConfigured {
                    CameraPreview(session: camera.captureSession)
                        .clipShape(RoundedRectangle(cornerRadius: QP.Radius.sheet))
                } else {
                    RoundedRectangle(cornerRadius: QP.Radius.sheet)
                        .fill(QP.ColorToken.surface)
                        .overlay {
                            VStack(spacing: QP.Spacing.sm) {
                                Image(systemName: "camera")
                                    .font(.system(size: 32))
                                    .foregroundStyle(QP.ColorToken.textSecondary)
                                Text("카메라를 사용할 수 없어요\n실기기에서 확인해주세요")
                                    .font(.footnote)
                                    .multilineTextAlignment(.center)
                                    .foregroundStyle(QP.ColorToken.textSecondary)
                            }
                        }
                }
                cornerGuides
            }
            .padding(QP.Spacing.lg)

            statusPanel
        }
    }

    private var cornerGuides: some View {
        GeometryReader { proxy in
            let length: CGFloat = 24
            let inset: CGFloat = 0
            ForEach(0..<4, id: \.self) { corner in
                CornerBracket(length: length)
                    .stroke(QP.ColorToken.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: length, height: length)
                    .rotationEffect(.degrees(Double(corner) * 90))
                    .position(
                        x: corner == 0 || corner == 3 ? inset + length / 2 : proxy.size.width - inset - length / 2,
                        y: corner < 2 ? inset + length / 2 : proxy.size.height - inset - length / 2
                    )
            }
        }
        .padding(QP.Spacing.lg)
        .allowsHitTesting(false)
    }

    private var statusPanel: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: QP.Spacing.sm) {
                if model.phase == .receiving {
                    HStack {
                        Text(model.fileName ?? "수신 중")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(QP.ColorToken.textPrimary)
                            .lineLimit(1)
                        Spacer()
                        Text(progressPercentText)
                            .font(.subheadline.weight(.medium))
                            .qpMetric()
                            .foregroundStyle(QP.ColorToken.accent)
                    }
                    ProgressView(value: Double(model.decodedBlocks), total: Double(max(1, model.totalBlocks)))
                        .tint(QP.ColorToken.accent)
                    HStack {
                        Text("\(model.decodedBlocks)/\(model.totalBlocks) 블록 · \(model.bytesPerSecond / 1024)KB/s")
                            .font(.footnote)
                            .qpMetric()
                            .foregroundStyle(QP.ColorToken.textSecondary)
                        Spacer()
                        Button("취소", role: .destructive) {
                            model.reset()
                        }
                        .font(.footnote.weight(.medium))
                    }
                    if model.isStalled(at: context.date) {
                        Text("인식이 끊겼어요. 두 기기를 20cm 정도로 가까이 해주세요.")
                            .font(.footnote)
                            .foregroundStyle(QP.ColorToken.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    Text("상대 화면의 QR에 카메라를 비추면\n자동으로 수신이 시작돼요")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(QP.ColorToken.textSecondary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(QP.Spacing.md)
        .background(QP.ColorToken.surface)
        .clipShape(RoundedRectangle(cornerRadius: QP.Radius.sheet))
        .padding([.horizontal, .bottom], QP.Spacing.md)
        .accessibilityElement(children: .combine)
        .accessibilityValue(model.phase == .receiving ? "\(progressPercentText) 수신됨" : "수신 대기 중")
    }

    private var progressPercentText: String {
        guard model.totalBlocks > 0 else { return "0%" }
        return "\(model.decodedBlocks * 100 / model.totalBlocks)%"
    }

    // MARK: - 권한 거부

    private var deniedView: some View {
        VStack(spacing: QP.Spacing.md) {
            Image(systemName: "camera.badge.ellipsis")
                .font(.system(size: 36))
                .foregroundStyle(QP.ColorToken.textSecondary)
            Text("카메라 권한이 꺼져 있어요")
                .font(.body.weight(.medium))
                .foregroundStyle(QP.ColorToken.textPrimary)
            Text("QR을 읽어 파일을 받으려면 카메라가 필요해요.")
                .font(.footnote)
                .foregroundStyle(QP.ColorToken.textSecondary)
            Button("설정 열기") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(QPSecondaryButtonStyle())
            .frame(maxWidth: 200)
        }
        .padding(QP.Spacing.lg)
    }

    // MARK: - 권한과 시작

    private func requestCameraAndStart() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startCamera()
        case .notDetermined:
            if await AVCaptureDevice.requestAccess(for: .video) {
                startCamera()
            } else {
                model.cameraDenied()
            }
        default:
            model.cameraDenied()
        }
    }

    private func startCamera() {
        model.cameraAuthorized()
        if !camera.isConfigured {
            let configured = camera.configure { payloads in
                model.ingest(payloads)
                if model.phase == .completed {
                    Haptics.success()
                    camera.stop()
                }
            }
            guard configured else { return }
        }
        camera.start()
    }
}

/// 뷰파인더 모서리 꺾쇠 (좌상단 기준, 회전으로 4곳 배치)
private struct CornerBracket: Shape {
    let length: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + length))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + 8))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + 8, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.minX + length, y: rect.minY))
        return path
    }
}

#Preview {
    ReceiveView()
        .preferredColorScheme(.dark)
}
