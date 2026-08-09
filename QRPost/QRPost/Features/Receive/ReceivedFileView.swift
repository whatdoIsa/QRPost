import SwiftUI
import Photos

/// 수신 완료 — 이 앱의 피크 순간. 앰버 소인이 찍히고 요약 카드로 닫는다
/// (디자인 가이드 5-5)
struct ReceivedFileView: View {
    let file: ReceiveModel.ReceivedFile
    let onDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stampVisible = false
    @State private var saveMessage: String?
    @State private var isExporting = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            postmark
                .padding(.bottom, QP.Spacing.md)

            Text("도착했어요")
                .font(.title3.weight(.medium))
                .foregroundStyle(QP.ColorToken.textPrimary)
            Text(saveMessage ?? "아래에서 저장하거나 공유할 수 있어요")
                .font(.footnote)
                .foregroundStyle(QP.ColorToken.textSecondary)
                .padding(.top, 4)

            summaryCard
                .padding(QP.Spacing.md)

            Spacer()

            actions
        }
        .onAppear {
            if reduceMotion {
                stampVisible = true
            } else {
                withAnimation(.spring(duration: 0.35, bounce: 0.4).delay(0.15)) {
                    stampVisible = true
                }
            }
        }
        .fileExporter(
            isPresented: $isExporting,
            document: ReceivedDocument(data: file.data),
            contentType: .data,
            defaultFilename: file.name
        ) { result in
            if case .success = result {
                saveMessage = "파일 앱에 저장됨"
            }
        }
    }

    private var postmark: some View {
        VStack(spacing: 2) {
            Text("도착")
                .font(.footnote.weight(.medium))
            Text(Date.now.formatted(.dateTime.month(.defaultDigits).day().hour().minute()))
                .font(.caption2)
                .qpMetric()
        }
        .foregroundStyle(QP.ColorToken.accent)
        .frame(width: 76, height: 76)
        .overlay(Circle().strokeBorder(QP.ColorToken.accent, lineWidth: 2.5))
        .rotationEffect(.degrees(-11))
        .scaleEffect(stampVisible ? 1 : (reduceMotion ? 1 : 1.6))
        .opacity(stampVisible ? 1 : 0)
        .accessibilityLabel("도착 소인")

    }

    private var summaryCard: some View {
        HStack(spacing: QP.Spacing.sm + 4) {
            Image(systemName: file.isImage ? "photo" : "doc")
                .font(.system(size: 20))
                .foregroundStyle(QP.ColorToken.textSecondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(QP.ColorToken.textPrimary)
                    .lineLimit(1)
                Text("\(SendModel.formatBytes(file.data.count)) · \(file.seconds)초 · \(file.blockCount)블록")
                    .font(.footnote)
                    .qpMetric()
                    .foregroundStyle(QP.ColorToken.textSecondary)
            }
            Spacer()
        }
        .padding(QP.Spacing.md)
        .background(QP.ColorToken.surface)
        .clipShape(RoundedRectangle(cornerRadius: QP.Radius.card))
    }

    private var actions: some View {
        VStack(spacing: QP.Spacing.sm) {
            HStack(spacing: QP.Spacing.sm) {
                ShareLink(item: file.data, preview: SharePreview(file.name)) {
                    Label("공유", systemImage: "square.and.arrow.up")
                        .font(.body.weight(.medium))
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .foregroundStyle(QP.ColorToken.textPrimary)
                .overlay(Capsule().strokeBorder(QP.ColorToken.border, lineWidth: 1))

                Button(file.isImage ? "사진 앱에 저장" : "파일로 저장") {
                    save()
                }
                .buttonStyle(QPPrimaryButtonStyle())
            }
            Button("확인") {
                onDone()
            }
            .font(.body.weight(.medium))
            .foregroundStyle(QP.ColorToken.textSecondary)
            .frame(minHeight: QP.minTapTarget)
        }
        .padding([.horizontal, .bottom], QP.Spacing.md)
    }

    private func save() {
        if file.isImage {
            saveToPhotoLibrary()
        } else {
            isExporting = true
        }
    }

    private func saveToPhotoLibrary() {
        let data = file.data
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                Task { @MainActor in
                    saveMessage = "사진 접근 권한이 꺼져 있어요. 설정에서 켜주세요."
                }
                return
            }
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: data, options: nil)
            } completionHandler: { success, _ in
                Task { @MainActor in
                    saveMessage = success ? "사진 앱에 저장됨" : "저장하지 못했어요. 다시 시도해주세요."
                }
            }
        }
    }
}

private struct ReceivedDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.data]
    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

import UniformTypeIdentifiers
