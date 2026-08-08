import Testing
import Foundation
@testable import QRPostCore

@Suite("LT 왕복")
struct LTRoundTripTests {
    @Test("다양한 크기의 무손실 왕복 (블록 경계 포함)", arguments: [1, 399, 400, 401, 1_024, 100_000])
    func roundTrip(size: Int) {
        let original = TestData.make(size: size, seed: 42)
        let encoder = LTEncoder(data: original, blockSize: 400, seed: 7)
        let decoder = LTDecoder(parameters: encoder.parameters)

        let limit = encoder.parameters.blockCount * 3 + 50
        for index in 0..<limit {
            decoder.ingest(encoder.packet(at: UInt32(index)))
            if decoder.isComplete { break }
        }

        #expect(decoder.isComplete)
        #expect(decoder.data()?.prefix(size) == original)
    }

    @Test("무손실이면 시스터매틱 프리픽스 K개로 정확히 완성된다")
    func systematicNoLoss() {
        let original = TestData.make(size: 100_000, seed: 3)
        let encoder = LTEncoder(data: original, blockSize: 400, seed: 11)
        let decoder = LTDecoder(parameters: encoder.parameters)
        let k = encoder.parameters.blockCount

        for index in 0..<(k - 1) {
            decoder.ingest(encoder.packet(at: UInt32(index)))
        }
        #expect(!decoder.isComplete, "K-1개로 완성되면 안 된다")
        decoder.ingest(encoder.packet(at: UInt32(k - 1)))
        #expect(decoder.isComplete, "무손실 오버헤드는 0이어야 한다")
        #expect(decoder.data()?.prefix(100_000) == original)
    }

    @Test("파운틴 구간만으로도 복원된다 (프리픽스 전체 유실 가정)")
    func fountainOnly() {
        let original = TestData.make(size: 20_000, seed: 3)
        let encoder = LTEncoder(data: original, blockSize: 400, seed: 11)
        let decoder = LTDecoder(parameters: encoder.parameters)
        let k = encoder.parameters.blockCount  // 50

        var used = 0
        while !decoder.isComplete && used < k * 4 {
            decoder.ingest(encoder.packet(at: UInt32(k + used)))  // 프리픽스 건너뜀
            used += 1
        }
        #expect(decoder.isComplete, "파운틴 패킷만으로 수렴 실패")
        #expect(decoder.data()?.prefix(20_000) == original)
    }

    @Test("완료 후 추가 패킷은 무시된다")
    func redundantAfterComplete() {
        let original = TestData.make(size: 2_000, seed: 5)
        let encoder = LTEncoder(data: original, blockSize: 400, seed: 13)
        let decoder = LTDecoder(parameters: encoder.parameters)

        var index: UInt32 = 0
        while !decoder.isComplete {
            decoder.ingest(encoder.packet(at: index))
            index += 1
        }
        #expect(decoder.ingest(encoder.packet(at: index + 1)) == false)
        #expect(decoder.data()?.prefix(2_000) == original)
    }

    @Test("잘못된 크기의 페이로드는 거부된다")
    func rejectsWrongSize() {
        let encoder = LTEncoder(data: TestData.make(size: 1_000, seed: 8), blockSize: 400, seed: 1)
        let decoder = LTDecoder(parameters: encoder.parameters)
        #expect(decoder.ingest(LTPacket(index: 0, payload: [1, 2, 3])) == false)
    }
}
