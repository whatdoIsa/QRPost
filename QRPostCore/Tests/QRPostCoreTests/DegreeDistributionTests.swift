import Testing
import Foundation
@testable import QRPostCore

@Suite("Robust Soliton 분포")
struct DegreeDistributionTests {
    @Test("차수는 항상 1...K 범위다")
    func degreeInRange() {
        let k = 1_000
        let distribution = DegreeDistribution(blockCount: k)
        var rng = SplitMix64(seed: 9)
        for _ in 0..<10_000 {
            let d = distribution.degree(using: &rng)
            #expect((1...k).contains(d))
        }
    }

    @Test("평균 차수는 낮게 유지된다 (스파스 코드)")
    func meanDegreeIsLow() {
        let distribution = DegreeDistribution(blockCount: 1_000)
        var rng = SplitMix64(seed: 10)
        var total = 0
        let samples = 20_000
        for _ in 0..<samples {
            total += distribution.degree(using: &rng)
        }
        let mean = Double(total) / Double(samples)
        #expect(mean < 40, "평균 차수 \(mean) — 분포 구성 오류 의심")
        #expect(mean > 2, "평균 차수가 비정상적으로 낮음")
    }

    @Test("차수 1이 충분히 자주 나온다 (디코딩 시동 조건)")
    func degreeOneExists() {
        let distribution = DegreeDistribution(blockCount: 500)
        var rng = SplitMix64(seed: 11)
        var ones = 0
        for _ in 0..<10_000 where distribution.degree(using: &rng) == 1 {
            ones += 1
        }
        #expect(ones > 50)
    }

    @Test("K=1 경계: 차수는 항상 1")
    func singleBlock() {
        let distribution = DegreeDistribution(blockCount: 1)
        var rng = SplitMix64(seed: 12)
        for _ in 0..<100 {
            #expect(distribution.degree(using: &rng) == 1)
        }
    }
}
