import Testing
import Foundation
@testable import QRPostCore

@Suite("결정성 (기기 간 재현성)")
struct DeterminismTests {
    @Test("같은 파라미터의 두 인코더는 동일한 패킷 시퀀스를 만든다")
    func encodersAgree() {
        let data = TestData.make(size: 20_000, seed: 77)
        let a = LTEncoder(data: data, blockSize: 400, seed: 1234)
        let b = LTEncoder(data: data, blockSize: 400, seed: 1234)
        for index in 0..<200 {
            #expect(a.packet(at: UInt32(index)) == b.packet(at: UInt32(index)))
        }
    }

    @Test("이웃 블록 유도는 파라미터만으로 재현된다 (인코더 없이)")
    func neighborhoodIsPure() {
        let parameters = LTParameters(blockCount: 50, blockSize: 400, seed: 1234)
        let distribution = DegreeDistribution(blockCount: 50)
        for index in 0..<200 {
            let first = LTNeighborhood.neighbors(packetIndex: UInt32(index), parameters: parameters, distribution: distribution)
            let second = LTNeighborhood.neighbors(packetIndex: UInt32(index), parameters: parameters, distribution: distribution)
            #expect(first == second)
            #expect(Set(first).count == first.count, "이웃 블록에 중복이 있음")
            #expect(first.allSatisfy { (0..<50).contains($0) })
        }
    }

    @Test("시드가 다르면 파운틴 구간 패킷 구성이 달라진다")
    func seedChangesStream() {
        let data = TestData.make(size: 20_000, seed: 77)
        let a = LTEncoder(data: data, blockSize: 400, seed: 1)
        let b = LTEncoder(data: data, blockSize: 400, seed: 2)
        let k = UInt32(a.parameters.blockCount)

        // 인덱스 < K는 시스터매틱 구간이라 시드와 무관하게 동일한 것이 정상
        for index in 0..<k {
            #expect(a.packet(at: index) == b.packet(at: index))
        }
        var identical = 0
        for index in k..<(k + 100) where a.packet(at: index) == b.packet(at: index) {
            identical += 1
        }
        #expect(identical < 10)
    }
}
