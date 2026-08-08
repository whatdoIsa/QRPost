import Foundation

/// LT 파운틴 인코더. 원본 데이터를 고정 크기 블록으로 나눠 보관하고,
/// 임의의 패킷 인덱스에 대해 결정적으로 패킷을 생성한다 — 무한 스트림.
public struct LTEncoder: Sendable {
    public let parameters: LTParameters
    private let blocks: [[UInt8]]
    private let distribution: DegreeDistribution

    public init(data: Data, blockSize: Int, seed: UInt64) {
        self.init(data: data, blockSize: blockSize, seed: seed, distribution: nil)
    }

    /// 분포 파라미터 실험용 — 프로토콜 기본값과 다른 분포는 기기 간 호환이 깨지므로 내부 전용
    init(data: Data, blockSize: Int, seed: UInt64, distribution: DegreeDistribution?) {
        precondition(!data.isEmpty, "빈 데이터는 인코딩할 수 없다 — 메타데이터 전용 전송은 상위 계층 담당")
        precondition(blockSize >= 1)

        let bytes = [UInt8](data)
        let blockCount = (bytes.count + blockSize - 1) / blockSize
        var blocks: [[UInt8]] = []
        blocks.reserveCapacity(blockCount)
        for i in 0..<blockCount {
            let start = i * blockSize
            let end = Swift.min(start + blockSize, bytes.count)
            var block = Array(bytes[start..<end])
            if block.count < blockSize {
                block.append(contentsOf: repeatElement(0, count: blockSize - block.count))
            }
            blocks.append(block)
        }

        self.blocks = blocks
        self.parameters = LTParameters(blockCount: blockCount, blockSize: blockSize, seed: seed)
        self.distribution = distribution ?? DegreeDistribution(blockCount: blockCount)
    }

    /// 인덱스만 알면 언제든 같은 패킷을 다시 만들 수 있다 (재전송 개념이 없음).
    public func packet(at index: UInt32) -> LTPacket {
        let neighbors = LTNeighborhood.neighbors(
            packetIndex: index,
            parameters: parameters,
            distribution: distribution
        )
        var payload = blocks[neighbors[0]]
        for n in neighbors.dropFirst() {
            let block = blocks[n]
            for i in 0..<payload.count {
                payload[i] ^= block[i]
            }
        }
        return LTPacket(index: index, payload: payload)
    }
}
