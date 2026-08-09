import SwiftUI
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

    /// 프레임 총 바이트가 v14-L 용량(458B)에 들어가는 블록 크기.
    /// 실기기 실측(#8 예정) 후 확정한다
    static let blockSize = 400
    static let framesPerSecond = 12
    static let maxFileSize = 64 * 1024 * 1024

    private(set) var payload: Payload?
    /// 빠르게 옵션용 재압축 결과. 원본보다 작을 때만 존재
    private(set) var compressedData: Data?
    var quality: Quality = .fast
    var errorMessage: String?
    var activeSession: SendSession?

    var hasQualityChoice: Bool { compressedData != nil }

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
            blockSize: Self.blockSize,
            fileID: UInt32.random(in: .min ... .max),
            seed: UInt64.random(in: .min ... .max)
        )
    }

    /// 무손실 기준 최소 소요 시간. 유실만큼 늘어난다는 사실은 UI 문구가 전달한다
    static func estimatedSeconds(byteCount: Int) -> Int {
        let blockCount = (byteCount + blockSize - 1) / blockSize
        let metaFrames = blockCount / (Int(SendSession.metaInterval) - 1) + 1
        let frames = blockCount + metaFrames
        return max(1, (frames + framesPerSecond - 1) / framesPerSecond)
    }

    private static func compress(_ payload: Payload) -> Data? {
        guard payload.isImage,
              let image = UIImage(data: payload.data),
              let jpeg = image.jpegData(compressionQuality: 0.35),
              jpeg.count < payload.data.count * 3 / 4 else {
            return nil
        }
        return jpeg
    }
}

extension SendModel {
    static func formatDuration(_ seconds: Int) -> String {
        seconds < 60 ? "약 \(seconds)초" : "약 \(seconds / 60)분 \(seconds % 60)초"
    }

    static func formatBytes(_ count: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
    }
}
