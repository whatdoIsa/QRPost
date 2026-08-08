import Testing
@testable import QRPostCore

@Suite("SplitMix64")
struct SplitMix64Tests {
    @Test("시드 0의 공개 참조 벡터와 일치")
    func referenceVectors() {
        var rng = SplitMix64(seed: 0)
        #expect(rng.next() == 0xE220_A839_7B1D_CDAF)
        #expect(rng.next() == 0x6E78_9E6A_A1B9_65F4)
        #expect(rng.next() == 0x06C4_5D18_8009_454F)
    }

    @Test("같은 시드는 같은 수열을 만든다 (기기 간 재현성)")
    func determinism() {
        var a = SplitMix64(seed: 0xDEAD_BEEF)
        var b = SplitMix64(seed: 0xDEAD_BEEF)
        for _ in 0..<1_000 {
            #expect(a.next() == b.next())
        }
    }

    @Test("다른 시드는 다른 수열을 만든다")
    func seedSensitivity() {
        var a = SplitMix64(seed: 1)
        var b = SplitMix64(seed: 2)
        #expect(a.next() != b.next())
    }
}
