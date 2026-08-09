import Foundation

/// 송신 세션. 파일 하나를 프레임 바이트의 무한 시퀀스로 바꾼다.
/// n번째 프레임은 언제나 같은 바이트 — 재전송 개념 없이 이어 재생만 한다.
public struct SendSession: Sendable {
    public let header: TransferHeader
    public let metadata: FileMetadata
    private let encoder: LTEncoder

    /// 이 간격마다 메타 프레임(파일명·종류)을 끼워 넣는다.
    /// 수신자가 중간 진입해도 곧 파일 정보를 얻도록 하는 값
    public static let metaInterval: UInt32 = 16

    public init(data: Data, metadata: FileMetadata, blockSize: Int, fileID: UInt32, seed: UInt64) {
        self.encoder = LTEncoder(data: data, blockSize: blockSize, seed: seed)
        self.header = TransferHeader(
            fileID: fileID,
            seed: seed,
            blockCount: UInt32(encoder.parameters.blockCount),
            blockSize: UInt16(blockSize),
            fileSize: UInt64(data.count)
        )
        self.metadata = metadata
    }

    /// n번째 프레임의 바이트. metaInterval 배수 위치는 메타 프레임,
    /// 나머지는 패킷 인덱스가 연속되는 데이터 프레임이다
    /// (시스터매틱 프리픽스가 초반에 그대로 유지되도록).
    public func frameBytes(at index: UInt32) -> [UInt8] {
        if index % Self.metaInterval == 0 {
            return FrameCodec.encode(.meta(header: header, metadata: metadata))
        }
        let packetIndex = index - index / Self.metaInterval - 1
        return FrameCodec.encode(.data(header: header, packet: encoder.packet(at: packetIndex)))
    }
}
