import Testing
import Foundation
@testable import QRPostCore

@Suite("패킷 유실 복원")
struct PacketLossTests {
    @Test("유실률 30/50/70% + 순서 셔플에도 복원된다", arguments: [0.3, 0.5, 0.7])
    func recoversUnderLoss(rate: Double) {
        let size = 50_000
        let original = TestData.make(size: size, seed: 1)
        let encoder = LTEncoder(data: original, blockSize: 400, seed: 99)

        // 유실·셔플 패턴도 결정적 — 이 테스트는 한 번 통과하면 영원히 통과한다
        var rng = SplitMix64(seed: 0xC0FF_EE00 &+ UInt64(rate * 100))
        var survivors: [LTPacket] = []
        for index in 0..<(encoder.parameters.blockCount * 6) {
            if TestData.uniform(&rng) >= rate {
                survivors.append(encoder.packet(at: UInt32(index)))
            }
        }
        for i in stride(from: survivors.count - 1, to: 0, by: -1) {
            let j = Int(rng.next() % UInt64(i + 1))
            survivors.swapAt(i, j)
        }

        let decoder = LTDecoder(parameters: encoder.parameters)
        for packet in survivors {
            decoder.ingest(packet)
            if decoder.isComplete { break }
        }

        #expect(decoder.isComplete, "유실률 \(rate)에서 복원 실패 (생존 패킷 \(survivors.count)개)")
        #expect(decoder.data()?.prefix(size) == original)
    }

    @Test("중복 패킷이 섞여도 결과가 오염되지 않는다")
    func duplicatesAreHarmless() {
        let size = 10_000
        let original = TestData.make(size: size, seed: 21)
        let encoder = LTEncoder(data: original, blockSize: 400, seed: 55)
        let decoder = LTDecoder(parameters: encoder.parameters)

        var index: UInt32 = 0
        while !decoder.isComplete {
            let packet = encoder.packet(at: index)
            decoder.ingest(packet)
            decoder.ingest(packet)
            index += 1
        }
        #expect(decoder.data()?.prefix(size) == original)
    }
}
