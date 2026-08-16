import Testing
import Foundation
@testable import QRPostCore

@Suite("코어 단대단")
struct EndToEndCoreTests {
    @Test("파일 -> 프레임 스트림 -> 유실 30% -> 복원 파일 일치")
    func fileRoundTripUnderLoss() {
        let size = 137_000
        let original = TestData.make(size: size, seed: 8)
        let sender = SendSession(
            data: original,
            metadata: FileMetadata(name: "IMG_2041.jpg", contentType: "image/jpeg"),
            blockSize: 400,
            fileID: 0x0BAD_F00D,
            seed: 777
        )

        let receiver = ReceiveSession()
        var lossRNG = SplitMix64(seed: 99)
        var frameIndex: UInt32 = 0
        var received = 0
        while !receiver.isComplete {
            #expect(frameIndex < 4_000, "수렴 실패")
            if frameIndex >= 4_000 { return }
            let bytes = sender.frameBytes(at: frameIndex)
            frameIndex += 1
            if TestData.uniform(&lossRNG) >= 0.3 {
                received += 1
                receiver.ingest(bytes)
            }
        }

        #expect(receiver.fileData() == original, "복원 데이터 불일치")
        #expect(receiver.metadata == FileMetadata(name: "IMG_2041.jpg", contentType: "image/jpeg"))
        #expect(receiver.totalBlockCount == 343)
    }

    @Test("파일 크기가 블록 경계와 정확히 일치해도 절단이 올바르다")
    func exactBlockBoundary() {
        let size = 400 * 5
        let original = TestData.make(size: size, seed: 2)
        let sender = SendSession(data: original, metadata: FileMetadata(name: "a.bin", contentType: "application/octet-stream"), blockSize: 400, fileID: 1, seed: 3)
        let receiver = ReceiveSession()
        var index: UInt32 = 0
        while !receiver.isComplete {
            receiver.ingest(sender.frameBytes(at: index))
            index += 1
        }
        #expect(receiver.fileData() == original)
    }

    @Test("중간 진입: 프레임 100번부터 수신해도 복원되고 메타데이터도 얻는다")
    func lateJoin() {
        let original = TestData.make(size: 30_000, seed: 4)
        let sender = SendSession(data: original, metadata: FileMetadata(name: "b.pdf", contentType: "application/pdf"), blockSize: 400, fileID: 2, seed: 5)
        let receiver = ReceiveSession()
        var index: UInt32 = 100
        while !receiver.isComplete {
            #expect(index < 4_000)
            if index >= 4_000 { return }
            receiver.ingest(sender.frameBytes(at: index))
            index += 1
        }
        #expect(receiver.fileData() == original)
        #expect(receiver.metadata?.name == "b.pdf")
    }

    @Test("다른 세션의 프레임은 거부된다")
    func rejectsForeignSession() {
        let a = SendSession(data: TestData.make(size: 5_000, seed: 6), metadata: FileMetadata(name: "a", contentType: "t"), blockSize: 400, fileID: 10, seed: 11)
        let b = SendSession(data: TestData.make(size: 5_000, seed: 7), metadata: FileMetadata(name: "b", contentType: "t"), blockSize: 400, fileID: 20, seed: 21)

        let receiver = ReceiveSession()
        #expect(receiver.ingest(a.frameBytes(at: 0)) == .progressed)
        #expect(receiver.ingest(b.frameBytes(at: 1)) == .rejected)
        #expect(receiver.header?.fileID == 10)
    }

    @Test("완성 프레임은 completed를 반환하고 이후 프레임은 unchanged다")
    func outcomeSequence() {
        let sender = SendSession(data: TestData.make(size: 1_000, seed: 9), metadata: FileMetadata(name: "c", contentType: "t"), blockSize: 400, fileID: 3, seed: 4)
        let receiver = ReceiveSession()

        var sawCompleted = false
        var index: UInt32 = 0
        while !receiver.isComplete {
            if receiver.ingest(sender.frameBytes(at: index)) == .completed {
                sawCompleted = true
            }
            index += 1
        }
        #expect(sawCompleted)
        #expect(receiver.ingest(sender.frameBytes(at: index)) == .unchanged)
    }
}
