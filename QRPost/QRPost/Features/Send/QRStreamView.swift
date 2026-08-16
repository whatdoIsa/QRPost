import SwiftUI
import QRPostCore

/// 풀스크린 QR 스트림 재생. 다크 앱에서 이 화면만 순백으로 반전된다 —
/// 화면이 발광 장치가 되는 순간 (디자인 가이드 5-3)
struct QRStreamView: View {
    let session: SendSession

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var startDate = Date.now

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / Double(TransferTuning.framesPerSecond))) { context in
            VStack(spacing: 0) {
                Text("\(session.metadata.name) 전송 중")
                    .font(.footnote)
                    .foregroundStyle(Color(white: 0.4))
                    .padding(.top, QP.Spacing.lg)

                Spacer()
                // 여러 코드를 세로로 동시 표시 — 카메라는 한 프레임에서 모두 인식한다
                let tick = currentTick(context.date)
                VStack(spacing: QP.Spacing.sm) {
                    ForEach(0..<TransferTuning.simultaneousCodes, id: \.self) { slot in
                        symbolImage(at: tick * UInt32(TransferTuning.simultaneousCodes) + UInt32(slot))
                    }
                }
                .padding(.horizontal, QP.Spacing.md)
                Spacer()

                Text("상대 카메라에 화면을 비춰주세요 · \(elapsedText(context.date))")
                    .font(.footnote)
                    .qpMetric()
                    .foregroundStyle(Color(white: 0.55))
                    .padding(.bottom, QP.Spacing.sm)

                Button("중단", role: .destructive) {
                    dismiss()
                }
                .font(.body.weight(.medium))
                .frame(minWidth: QP.minTapTarget, minHeight: QP.minTapTarget)
                .padding(.bottom, QP.Spacing.lg)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.white)
        }
        .statusBarHidden()
        .preferredColorScheme(.light)
        .onAppear {
            startDate = .now
            ScreenGuard.engage()
        }
        .onDisappear {
            ScreenGuard.release()
        }
        .onChange(of: scenePhase) {
            // 전화·앱 전환 중에는 밝기를 돌려주고, 복귀하면 다시 고정한다.
            // 프레임 인덱스는 벽시계 기준이라 중단 없이 이어진다 (수신은 순서 무관)
            switch scenePhase {
            case .active:
                ScreenGuard.engage()
            default:
                ScreenGuard.release()
            }
        }
        .accessibilityLabel("QR 코드 재생 중")
        .accessibilityValue("\(session.metadata.name) 전송 중")
    }

    private func currentTick(_ date: Date) -> UInt32 {
        let elapsed = max(0, date.timeIntervalSince(startDate))
        return UInt32(elapsed * Double(TransferTuning.framesPerSecond))
    }

    private func elapsedText(_ date: Date) -> String {
        let seconds = Int(max(0, date.timeIntervalSince(startDate)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    @ViewBuilder
    private func symbolImage(at index: UInt32) -> some View {
        let bytes = session.frameBytes(at: index)
        if let symbol = QRCodeEncoder.encode(Data(bytes), level: .low),
           let image = Self.render(symbol) {
            Image(decorative: image, scale: 1)
                .resizable()
                .interpolation(.none)
                .aspectRatio(1, contentMode: .fit)
        }
    }

    /// 심볼을 1모듈 = 1픽셀 그레이 비트맵으로 만들고 뷰에서 최근접 확대한다.
    /// 콰이어트 존은 흰 배경 자체가 제공한다
    private static func render(_ symbol: QRSymbol) -> CGImage? {
        let size = symbol.size
        var pixels = [UInt8](repeating: 255, count: size * size)
        for y in 0..<size {
            for x in 0..<size where symbol.module(x: x, y: y) {
                pixels[y * size + x] = 0
            }
        }
        let context = CGContext(
            data: &pixels,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: size,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        )
        return context?.makeImage()
    }
}
