import Foundation

/// LT 필링(peeling) 디코더. 패킷을 순서 무관·중복 허용으로 받아들이고,
/// 차수가 1로 줄어든 패킷에서 블록을 확정한 뒤 연쇄적으로 전파한다.
public final class LTDecoder {
    public let parameters: LTParameters
    private let distribution: DegreeDistribution

    private var decodedBlocks: [[UInt8]?]
    public private(set) var decodedBlockCount = 0

    private var pendingNeighbors: [Int: Set<Int>] = [:]
    private var pendingPayloads: [Int: [UInt8]] = [:]
    private var blockToPending: [Int: Set<Int>] = [:]
    private var nextPendingID = 0

    public convenience init(parameters: LTParameters) {
        self.init(parameters: parameters, distribution: nil)
    }

    /// 분포 파라미터 실험용 — 내부 전용 (LTEncoder 참조)
    init(parameters: LTParameters, distribution: DegreeDistribution?) {
        self.parameters = parameters
        self.distribution = distribution ?? DegreeDistribution(blockCount: parameters.blockCount)
        self.decodedBlocks = Array(repeating: nil, count: parameters.blockCount)
    }

    public var isComplete: Bool {
        decodedBlockCount == parameters.blockCount
    }

    /// 반환값: 이 패킷이 새 정보를 제공했는지 (중복·불량 패킷이면 false)
    @discardableResult
    public func ingest(_ packet: LTPacket) -> Bool {
        guard !isComplete, packet.payload.count == parameters.blockSize else { return false }
        let useful = process(packet)
        // 필링이 끝까지 못 가는 말단 구간은 가우스 소거로 마무리한다
        if !isComplete {
            attemptGaussianElimination()
        }
        return useful
    }

    private func process(_ packet: LTPacket) -> Bool {
        var payload = packet.payload
        var unresolved = Set(LTNeighborhood.neighbors(
            packetIndex: packet.index,
            parameters: parameters,
            distribution: distribution
        ))

        // 이미 확정된 블록은 XOR로 소거
        for block in unresolved.filter({ decodedBlocks[$0] != nil }) {
            xor(&payload, decodedBlocks[block]!)
            unresolved.remove(block)
        }

        switch unresolved.count {
        case 0:
            return false
        case 1:
            solve(block: unresolved.first!, payload: payload)
            return true
        default:
            let id = nextPendingID
            nextPendingID += 1
            pendingNeighbors[id] = unresolved
            pendingPayloads[id] = payload
            for block in unresolved {
                blockToPending[block, default: []].insert(id)
            }
            return true
        }
    }

    /// 완성된 전체 데이터 (K × blockSize, 마지막 블록 패딩 포함).
    /// 원본 길이 절단은 파일 크기를 아는 상위 계층 담당.
    public func data() -> Data? {
        guard isComplete else { return nil }
        var out = [UInt8]()
        out.reserveCapacity(parameters.blockCount * parameters.blockSize)
        for block in decodedBlocks {
            out.append(contentsOf: block!)
        }
        return Data(out)
    }

    private func solve(block: Int, payload: [UInt8]) {
        var queue: [(Int, [UInt8])] = [(block, payload)]
        while let (solved, solvedPayload) = queue.popLast() {
            guard decodedBlocks[solved] == nil else { continue }
            decodedBlocks[solved] = solvedPayload
            decodedBlockCount += 1

            guard let referencing = blockToPending.removeValue(forKey: solved) else { continue }
            for id in referencing {
                guard var neighbors = pendingNeighbors[id], var pending = pendingPayloads[id] else { continue }
                xor(&pending, solvedPayload)
                neighbors.remove(solved)
                if neighbors.count == 1 {
                    let last = neighbors.first!
                    pendingNeighbors[id] = nil
                    pendingPayloads[id] = nil
                    blockToPending[last]?.remove(id)
                    queue.append((last, pending))
                } else {
                    pendingNeighbors[id] = neighbors
                    pendingPayloads[id] = pending
                }
            }
        }
    }

    private func xor(_ target: inout [UInt8], _ source: [UInt8]) {
        for i in 0..<target.count {
            target[i] ^= source[i]
        }
    }

    // MARK: - 가우스 소거 폴백

    /// 미지 블록이 이 수 이하로 남았을 때만 소거를 시도한다 (비용 상한)
    private let eliminationUnknownLimit = 128
    /// 방정식 수 상한 — 미지수 대비 여유분
    private let eliminationEquationSlack = 64

    /// 순수 필링은 말단에서 차수 1 패킷을 기다리며 오버헤드를 키운다.
    /// 남은 미지 블록이 적고 방정식(대기 패킷)이 충분하면 GF2Solver로 직접 푼다.
    private func attemptGaussianElimination() {
        let unknownCount = parameters.blockCount - decodedBlockCount
        guard unknownCount > 0,
              unknownCount <= eliminationUnknownLimit,
              pendingNeighbors.count >= unknownCount else { return }

        var unknowns: [Int] = []
        unknowns.reserveCapacity(unknownCount)
        for block in 0..<parameters.blockCount where decodedBlocks[block] == nil {
            unknowns.append(block)
        }

        // 방정식은 차수 낮은 것부터, 결정적 순서로
        let equations = pendingNeighbors
            .sorted { ($0.value.count, $0.key) < ($1.value.count, $1.key) }
            .prefix(unknownCount + eliminationEquationSlack)
            .map { GF2Solver.Equation(neighbors: $0.value, payload: pendingPayloads[$0.key]!) }

        for solution in GF2Solver.solve(unknowns: unknowns, equations: equations)
        where decodedBlocks[solution.block] == nil {
            solve(block: solution.block, payload: solution.payload)
        }
    }
}
