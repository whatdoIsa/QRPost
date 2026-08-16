import Foundation
import QRPostCore
import Observation

@Observable
final class ReceiveModel {
    enum Phase: Equatable {
        /// 카메라 권한 대기 또는 거부
        case needsPermission
        /// 프레임 대기 중
        case scanning
        /// 수신 진행 중
        case receiving
        /// 파일 완성
        case completed
    }

    private(set) var phase: Phase = .needsPermission
    /// 권한이 명시적으로 거부된 상태 (needsPermission과 구분: 요청 전 대기일 수도 있다)
    private(set) var isPermissionDenied = false
    private var session = ReceiveSession()
    private var startedAt: Date?

    private(set) var fileName: String?
    private(set) var decodedBlocks = 0
    private(set) var totalBlocks = 0
    private(set) var bytesPerSecond = 0
    private(set) var result: ReceivedFile?
    /// 프레임이 한동안 끊겼을 때의 안내 노출용
    private(set) var lastProgressAt: Date?

    struct ReceivedFile: Equatable {
        let data: Data
        let name: String
        let contentType: String
        let seconds: Int
        let blockCount: Int

        var isImage: Bool { contentType.hasPrefix("image/") }
        var isVideo: Bool { contentType.hasPrefix("video/") }
    }

    func cameraAuthorized() {
        isPermissionDenied = false
        if phase == .needsPermission {
            phase = .scanning
        }
    }

    func cameraDenied() {
        isPermissionDenied = true
        phase = .needsPermission
    }

    /// 수신 중인데 일정 시간 프레임이 끊겼는지 — 거리 안내 노출 조건
    func isStalled(at now: Date) -> Bool {
        guard phase == .receiving, let lastProgressAt else { return false }
        return now.timeIntervalSince(lastProgressAt) > 2
    }

    /// 스캐너가 뽑은 페이로드 후보들을 세션에 공급한다.
    /// 손상·중복·다른 세션 프레임은 코어가 걸러낸다
    func ingest(_ candidates: [Data]) {
        guard phase == .scanning || phase == .receiving else { return }
        for candidate in candidates {
            let outcome = session.ingest([UInt8](candidate))
            switch outcome {
            case .progressed:
                noteProgress()
            case .completed:
                noteProgress()
                finish()
                return
            case .unchanged, .rejected:
                continue
            }
        }
    }

    func reset() {
        session = ReceiveSession()
        startedAt = nil
        fileName = nil
        decodedBlocks = 0
        totalBlocks = 0
        bytesPerSecond = 0
        result = nil
        lastProgressAt = nil
        phase = .scanning
    }

    private func noteProgress() {
        if startedAt == nil {
            startedAt = .now
            phase = .receiving
        }
        lastProgressAt = .now
        fileName = session.metadata?.name
        decodedBlocks = session.decodedBlockCount
        totalBlocks = session.totalBlockCount ?? 0

        if let startedAt, let header = session.header {
            let elapsed = Date.now.timeIntervalSince(startedAt)
            if elapsed > 0.5 {
                bytesPerSecond = Int(Double(decodedBlocks * Int(header.blockSize)) / elapsed)
            }
        }
    }

    private func finish() {
        guard let data = session.fileData() else { return }
        let seconds = startedAt.map { Int(Date.now.timeIntervalSince($0)) } ?? 0
        result = ReceivedFile(
            data: data,
            name: session.metadata?.name ?? "받은 파일",
            contentType: session.metadata?.contentType ?? "application/octet-stream",
            seconds: max(1, seconds),
            blockCount: session.decodedBlockCount
        )
        phase = .completed
    }
}
