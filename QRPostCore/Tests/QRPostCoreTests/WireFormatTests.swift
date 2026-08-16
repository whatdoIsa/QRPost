import Testing
import Foundation
@testable import QRPostCore

@Suite("와이어 포맷")
struct WireFormatTests {
    private let header = TransferHeader(fileID: 0xAABB_CCDD, seed: 42, blockCount: 53, blockSize: 400, fileSize: 20_800)

    @Test("데이터 프레임 왕복 직렬화")
    func dataRoundTrip() throws {
        let packet = LTPacket(index: 7, payload: [UInt8](TestData.make(size: 400, seed: 1)))
        let frame = WireFrame.data(header: header, packet: packet)
        let decoded = try FrameCodec.decode(FrameCodec.encode(frame))
        #expect(decoded == frame)
    }

    @Test("메타 프레임 왕복 직렬화 (한글 파일명 포함)")
    func metaRoundTrip() throws {
        let metadata = FileMetadata(name: "휴가 사진.jpg", contentType: "image/jpeg")
        let frame = WireFrame.meta(header: header, metadata: metadata)
        let decoded = try FrameCodec.decode(FrameCodec.encode(frame))
        #expect(decoded == frame)
    }

    @Test("1비트 손상 프레임은 체크섬에서 거부된다")
    func rejectsBitFlip() {
        let packet = LTPacket(index: 0, payload: [UInt8](repeating: 0x5A, count: 400))
        var bytes = FrameCodec.encode(.data(header: header, packet: packet))
        bytes[bytes.count / 2] ^= 0b0001_0000
        #expect(throws: WireError.badChecksum) {
            try FrameCodec.decode(bytes)
        }
    }

    @Test("잘린 프레임, 잘못된 매직은 거부된다")
    func rejectsGarbage() {
        #expect(throws: WireError.truncated) {
            try FrameCodec.decode([0x51, 0x50, 0x01])
        }
        let packet = LTPacket(index: 0, payload: [UInt8](repeating: 0, count: 400))
        var bytes = FrameCodec.encode(.data(header: header, packet: packet))
        bytes[0] = 0x00
        // 매직 훼손은 체크섬도 함께 어긋난다 — 어느 쪽이든 거부되면 된다
        #expect((try? FrameCodec.decode(bytes)) == nil)
    }

    @Test("모순된 헤더 파라미터는 거부된다 (fileSize > K x blockSize)")
    func rejectsInconsistentHeader() {
        let bad = TransferHeader(fileID: 1, seed: 1, blockCount: 2, blockSize: 100, fileSize: 5_000)
        let bytes = FrameCodec.encode(.meta(header: bad, metadata: FileMetadata(name: "a", contentType: "b")))
        #expect(throws: WireError.malformed) {
            try FrameCodec.decode(bytes)
        }
    }
}
