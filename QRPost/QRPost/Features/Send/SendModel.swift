import SwiftUI
import PhotosUI
import QRPostCore
import UniformTypeIdentifiers

@Observable
final class SendModel {
    struct Payload {
        let data: Data
        let name: String
        let contentType: String

        var isImage: Bool { contentType.hasPrefix("image/") }
    }

    enum Quality: CaseIterable, Identifiable {
        case fast
        case original

        var id: Self { self }
        var title: String {
            switch self {
            case .fast: return "빠르게"
            case .original: return "원본 화질"
            }
        }
    }

    nonisolated static let maxFileSize = 64 * 1024 * 1024

    private(set) var payload: Payload?
    /// 빠르게 옵션용 재압축 결과. 원본보다 작을 때만 존재
    private(set) var compressedData: Data?
    var quality: Quality = .fast
    var errorMessage: String?
    var activeSession: SendSession?

    var hasQualityChoice: Bool { compressedData != nil }

    func load(photoItem: PhotosPickerItem) async {
        guard let data = try? await photoItem.loadTransferable(type: Data.self) else {
            errorMessage = "사진을 불러오지 못했어요. 다시 선택해주세요."
            return
        }
        let type = photoItem.supportedContentTypes.first
        setPayload(
            data: data,
            name: "사진.\(type?.preferredFilenameExtension ?? "jpg")",
            contentType: type?.preferredMIMEType ?? "application/octet-stream"
        )
    }

    func load(fileResult: Result<URL, Error>) {
        guard case .success(let url) = fileResult else { return }
        guard url.startAccessingSecurityScopedResource() else {
            errorMessage = "파일에 접근하지 못했어요. 다시 선택해주세요."
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }
        guard let data = try? Data(contentsOf: url) else {
            errorMessage = "파일을 읽지 못했어요. 다시 선택해주세요."
            return
        }
        setPayload(
            data: data,
            name: url.lastPathComponent,
            contentType: UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        )
    }

    func setPayload(data: Data, name: String, contentType: String) {
        guard data.count <= Self.maxFileSize else {
            errorMessage = "64MB 이하 파일만 보낼 수 있어요. 이 파일은 \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))입니다."
            return
        }
        guard !data.isEmpty else {
            errorMessage = "빈 파일은 보낼 수 없어요."
            return
        }
        let payload = Payload(data: data, name: name, contentType: contentType)
        self.payload = payload
        self.compressedData = Self.compress(payload)
        self.quality = compressedData != nil ? .fast : .original
        self.errorMessage = nil
    }

    func clearPayload() {
        payload = nil
        compressedData = nil
    }

    func byteCount(for quality: Quality) -> Int? {
        switch quality {
        case .fast: return compressedData?.count ?? payload?.data.count
        case .original: return payload?.data.count
        }
    }

    func estimatedSeconds(for quality: Quality) -> Int? {
        byteCount(for: quality).map(Self.estimatedSeconds(byteCount:))
    }

    func startStreaming() {
        guard let payload else { return }
        let data = (quality == .fast ? compressedData : nil) ?? payload.data
        activeSession = SendSession(
            data: data,
            metadata: FileMetadata(name: payload.name, contentType: payload.contentType),
            blockSize: TransferTuning.blockSize,
            fileID: UInt32.random(in: .min ... .max),
            seed: UInt64.random(in: .min ... .max)
        )
    }

    /// 무손실 기준 최소 소요 시간. 유실만큼 늘어난다는 사실은 UI 문구가 전달한다
    nonisolated static func estimatedSeconds(byteCount: Int) -> Int {
        let blockCount = (byteCount + TransferTuning.blockSize - 1) / TransferTuning.blockSize
        let metaFrames = blockCount / (Int(SendSession.metaInterval) - 1) + 1
        let frames = blockCount + metaFrames
        let perSecond = TransferTuning.framesPerSecondTotal
        return max(1, (frames + perSecond - 1) / perSecond)
    }

    /// 빠르게 옵션의 JPEG 품질 — 실기기 실측에서 화질 대비 시간을 보고 확정한다
    private static let fastJPEGQuality: CGFloat = 0.35
    /// 압축 결과가 원본의 이 비율보다 작아야 옵션을 노출한다 (이득 없는 선택지 방지)
    private static let worthwhileRatio = 0.75

    private static func compress(_ payload: Payload) -> Data? {
        guard payload.isImage,
              let image = UIImage(data: payload.data),
              let jpeg = image.jpegData(compressionQuality: fastJPEGQuality),
              Double(jpeg.count) < Double(payload.data.count) * worthwhileRatio else {
            return nil
        }
        return jpeg
    }
}

extension SendModel {
    nonisolated static func formatDuration(_ seconds: Int) -> String {
        seconds < 60 ? "약 \(seconds)초" : "약 \(seconds / 60)분 \(seconds % 60)초"
    }

    nonisolated static func formatBytes(_ count: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
    }
}
