import Foundation

/// 파운틴 코드 세션 파라미터. 송신·수신이 완전히 동일한 값을 공유해야 하며,
/// 와이어 포맷의 패킷 헤더로 전달된다.
public struct LTParameters: Sendable, Hashable {
    /// 원본 블록 수 K
    public let blockCount: Int
    /// 블록(페이로드) 크기, 바이트
    public let blockSize: Int
    /// 세션 시드 — 패킷 인덱스와 조합해 블록 선택을 재현한다
    public let seed: UInt64

    public init(blockCount: Int, blockSize: Int, seed: UInt64) {
        precondition(blockCount >= 1 && blockSize >= 1)
        self.blockCount = blockCount
        self.blockSize = blockSize
        self.seed = seed
    }
}

/// 파운틴 패킷. 페이로드는 선택된 원본 블록들의 XOR이고,
/// 어떤 블록들이 섞였는지는 인덱스에서 결정적으로 재계산한다.
public struct LTPacket: Sendable, Equatable {
    public let index: UInt32
    public let payload: [UInt8]

    public init(index: UInt32, payload: [UInt8]) {
        self.index = index
        self.payload = payload
    }
}

/// 패킷 인덱스 → 블록 조합 유도. 인코더와 디코더가 이 한 곳만 공유하므로
/// 양쪽 구현이 어긋날 수 없다.
enum LTNeighborhood {
    static func neighbors(
        packetIndex: UInt32,
        parameters: LTParameters,
        distribution: DegreeDistribution
    ) -> [Int] {
        // 시스터매틱 프리픽스: 인덱스 < K는 원본 블록 그대로 (차수 1).
        // 무손실이면 정확히 K개로 완성되고, 유실 시에도 전 블록 커버리지가 보장된다.
        if packetIndex < UInt32(parameters.blockCount) {
            return [Int(packetIndex)]
        }
        // 인덱스를 아발란시 해시로 흩뿌려 패킷 간 난수 스트림 상관을 제거한다.
        // (단순 등차 시드는 SplitMix64 스트림이 한 칸씩 겹쳐 오버헤드가 커진다)
        var rng = SplitMix64(seed: parameters.seed ^ SplitMix64.scramble(UInt64(packetIndex) &+ 0x9E37_79B9_7F4A_7C15))
        let k = parameters.blockCount
        let degree = distribution.degree(using: &rng)

        // 희소 부분 Fisher-Yates: O(degree)로 서로 다른 인덱스 degree개 추출
        var swaps: [Int: Int] = [:]
        var result: [Int] = []
        result.reserveCapacity(degree)
        for i in 0..<degree {
            let j = i + Int(rng.next() % UInt64(k - i))
            let valueAtJ = swaps[j] ?? j
            result.append(valueAtJ)
            swaps[j] = swaps[i] ?? i
        }
        return result
    }
}
