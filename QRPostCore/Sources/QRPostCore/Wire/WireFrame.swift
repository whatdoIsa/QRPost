import Foundation

/// 전송 세션의 고정 파라미터. 모든 프레임 헤더에 실려
/// 수신자가 어느 프레임부터 받아도 세션을 복원할 수 있다.
public struct TransferHeader: Sendable, Hashable {
    /// 세션 식별자. 다른 전송의 프레임이 섞여 들어오는 것을 막는다
    public let fileID: UInt32
    public let seed: UInt64
    public let blockCount: UInt32
    public let blockSize: UInt16
    /// 원본 파일 길이. 마지막 블록의 패딩 절단에 사용한다
    public let fileSize: UInt64

    public init(fileID: UInt32, seed: UInt64, blockCount: UInt32, blockSize: UInt16, fileSize: UInt64) {
        self.fileID = fileID
        self.seed = seed
        self.blockCount = blockCount
        self.blockSize = blockSize
        self.fileSize = fileSize
    }

    var ltParameters: LTParameters {
        LTParameters(blockCount: Int(blockCount), blockSize: Int(blockSize), seed: seed)
    }
}

/// 파일 이름과 종류. 메타 프레임으로 주기 전송된다.
public struct FileMetadata: Sendable, Equatable {
    public let name: String
    /// MIME 타입 또는 UTType identifier
    public let contentType: String

    public init(name: String, contentType: String) {
        self.name = name
        self.contentType = contentType
    }
}

/// QR 한 장에 실리는 프레임.
public enum WireFrame: Sendable, Equatable {
    case data(header: TransferHeader, packet: LTPacket)
    case meta(header: TransferHeader, metadata: FileMetadata)

    public var header: TransferHeader {
        switch self {
        case .data(let header, _), .meta(let header, _):
            return header
        }
    }
}
