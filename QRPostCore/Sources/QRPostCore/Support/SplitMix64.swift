/// 결정적 의사난수 생성기 (SplitMix64).
/// 송신·수신이 같은 시드로 동일한 블록 조합을 재현해야 하므로
/// 시스템 RNG 대신 사양이 고정된 이 구현을 사용한다.
public struct SplitMix64: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        self.state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        return Self.scramble(state)
    }

    /// SplitMix64의 출력 단계(아발란시 해시). 전단사 함수이므로
    /// 서로 다른 입력에서 상관관계 없는 시드를 유도할 때 사용한다.
    public static func scramble(_ value: UInt64) -> UInt64 {
        var z = value
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
