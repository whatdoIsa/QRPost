import Foundation

/// 수신 세션. QR에서 뽑은 프레임 바이트를 순서 무관으로 받아들여 파일을 복원한다.
/// 첫 유효 프레임의 세션에 고정되며, 다른 fileID의 프레임은 거부한다.
public final class ReceiveSession {
    public enum IngestOutcome: Equatable {
        /// 새 정보를 얻었다
        case progressed
        /// 유효하지만 이미 아는 정보다 (중복)
        case unchanged
        /// 손상되었거나 다른 세션의 프레임이다
        case rejected
        /// 이 프레임으로 파일이 완성되었다
        case completed
    }

    public private(set) var header: TransferHeader?
    public private(set) var metadata: FileMetadata?
    private var decoder: LTDecoder?

    public init() {}

    public var isComplete: Bool { decoder?.isComplete ?? false }
    public var decodedBlockCount: Int { decoder?.decodedBlockCount ?? 0 }
    public var totalBlockCount: Int? { header.map { Int($0.blockCount) } }

    @discardableResult
    public func ingest(_ frameBytes: [UInt8]) -> IngestOutcome {
        guard let frame = try? FrameCodec.decode(frameBytes) else { return .rejected }
        guard adopt(frame.header) else { return .rejected }

        switch frame {
        case .meta(_, let incoming):
            if metadata == nil {
                metadata = incoming
                return .progressed
            }
            return .unchanged
        case .data(_, let packet):
            guard let decoder, !decoder.isComplete else { return .unchanged }
            let useful = decoder.ingest(packet)
            if decoder.isComplete {
                return .completed
            }
            return useful ? .progressed : .unchanged
        }
    }

    /// 원본 길이로 절단된 파일 데이터. 완성 전에는 nil
    public func fileData() -> Data? {
        guard let header, let full = decoder?.data() else { return nil }
        return full.prefix(Int(header.fileSize))
    }

    private func adopt(_ incoming: TransferHeader) -> Bool {
        if let header {
            return header == incoming
        }
        header = incoming
        decoder = LTDecoder(parameters: incoming.ltParameters)
        return true
    }
}
