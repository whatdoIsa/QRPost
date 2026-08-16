import SwiftUI
import Photos
import AVKit
import UniformTypeIdentifiers

/// 수신 완료 — 이 앱의 피크 순간. 받은 사진·영상을 바로 보여주고
/// 소인이 프리뷰 모서리에 찍힌다 (디자인 가이드 5-5)
struct ReceivedFileView: View {
    let file: ReceiveModel.ReceivedFile
    let onDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stampVisible = false
    @State private var saveMessage: String?
    @State private var isExporting = false
    @State private var videoURL: URL?

    var body: some View {
        VStack(spacing: 0) {
            Text("도착했어요")
                .font(.title3.weight(.medium))
                .foregroundStyle(QP.ColorToken.textPrimary)
                .padding(.top, QP.Spacing.lg)

            Spacer(minLength: QP.Spacing.sm)

            mediaPreview
                .padding(.horizontal, QP.Spacing.md)

            VStack(spacing: 2) {
                Text(saveMessage ?? file.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(QP.ColorToken.textPrimary)
                    .lineLimit(1)
                Text("\(SendModel.formatBytes(file.data.count)) · \(file.seconds)초 · \(file.blockCount)블록")
                    .font(.footnote)
                    .qpMetric()
                    .foregroundStyle(QP.ColorToken.textSecondary)
            }
            .padding(.top, QP.Spacing.md)

            Spacer(minLength: QP.Spacing.sm)

            actions
        }
        .onAppear {
            prepareVideoIfNeeded()
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

    // MARK: - 프리뷰

    @ViewBuilder
    private var mediaPreview: some View {
        Group {
            if file.isImage, let image = UIImage(data: file.data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else if file.isVideo, let videoURL {
                VideoPlayer(player: AVPlayer(url: videoURL))
                    .aspectRatio(3.0 / 4.0, contentMode: .fit)
            } else {
                VStack(spacing: QP.Spacing.sm) {
                    Image(systemName: "doc")
                        .font(.system(size: 40))
                        .foregroundStyle(QP.ColorToken.textSecondary)
                    Text(file.contentType)
                        .font(.footnote)
                        .foregroundStyle(QP.ColorToken.textSecondary)
                }
                .frame(maxWidth: .infinity, minHeight: 240)
                .background(QP.ColorToken.surface)
            }
        }
        .frame(maxHeight: 420)
        .clipShape(RoundedRectangle(cornerRadius: QP.Radius.sheet))
        .overlay(alignment: .topTrailing) {
            postmark
                .offset(x: QP.Spacing.sm, y: -QP.Spacing.sm)
        }
    }

    private var postmark: some View {
        VStack(spacing: 0) {
            Text("도착")
                .font(.caption.weight(.medium))
            Text(Date.now.formatted(.dateTime.month(.defaultDigits).day()))
                .font(.caption2)
                .qpMetric()
        }
        .foregroundStyle(QP.ColorToken.accent)
        .frame(width: 58, height: 58)
        .background(QP.ColorToken.background.opacity(0.85), in: Circle())
        .overlay(Circle().strokeBorder(QP.ColorToken.accent, lineWidth: 2))
        .rotationEffect(.degrees(-11))
        .scaleEffect(stampVisible ? 1 : (reduceMotion ? 1 : 1.6))
        .opacity(stampVisible ? 1 : 0)
        .accessibilityLabel("도착 소인")
    }

    // MARK: - 액션

    private var actions: some View {
        VStack(spacing: QP.Spacing.sm) {
            HStack(spacing: QP.Spacing.sm) {
                shareLink
                Button(file.isImage || file.isVideo ? "사진 앱에 저장" : "파일로 저장") {
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

    @ViewBuilder
    private var shareLink: some View {
        let label = Label("공유", systemImage: "square.and.arrow.up")
            .font(.body.weight(.medium))
            .frame(maxWidth: .infinity, minHeight: 50)
        Group {
            if let videoURL {
                ShareLink(item: videoURL) { label }
            } else {
                ShareLink(item: file.data, preview: SharePreview(file.name)) { label }
            }
        }
        .foregroundStyle(QP.ColorToken.textPrimary)
        .overlay(Capsule().strokeBorder(QP.ColorToken.border, lineWidth: 1))
    }

    // MARK: - 저장

    private func save() {
        if file.isImage || file.isVideo {
            saveToPhotoLibrary()
        } else {
            isExporting = true
        }
    }

    private func saveToPhotoLibrary() {
        let data = file.data
        let isVideo = file.isVideo
        let videoURL = videoURL
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                Task { @MainActor in
                    saveMessage = "사진 접근 권한이 꺼져 있어요. 설정에서 켜주세요."
                }
                return
            }
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                if isVideo, let videoURL {
                    request.addResource(with: .video, fileURL: videoURL, options: nil)
                } else {
                    request.addResource(with: .photo, data: data, options: nil)
                }
            } completionHandler: { success, _ in
                Task { @MainActor in
                    saveMessage = success ? "사진 앱에 저장됨" : "저장하지 못했어요. 다시 시도해주세요."
                }
            }
        }
    }

    /// 영상 재생·공유·저장은 파일 URL이 필요해 임시 파일로 쓴다
    private func prepareVideoIfNeeded() {
        guard file.isVideo, videoURL == nil else { return }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = directory.appendingPathComponent(file.name)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try file.data.write(to: url)
            videoURL = url
        } catch {
            videoURL = nil
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
