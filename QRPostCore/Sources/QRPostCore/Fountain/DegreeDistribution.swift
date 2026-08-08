import Foundation

/// Robust Soliton 차수 분포.
/// 대부분의 패킷은 낮은 차수(적은 블록의 XOR)를 갖고, K/R 지점의 스파이크가
/// 디코딩 말미의 고립 블록을 해소한다. 파라미터(c, delta)는 프로토콜 상수로,
/// 송수신 간 절대 달라서는 안 된다.
public struct DegreeDistribution: Sendable {
    /// cdf[d-1] = P(차수 ≤ d)
    private let cdf: [Double]

    /// 기본 c/δ는 K=250, 유실률 50% 그리드 실측(2026-08-08)에서
    /// 수신 오버헤드가 가장 낮았던 값 (평균 17%, 최악 33%).
    /// 프로토콜 상수 — 변경 시 기기 간 호환이 깨진다.
    public init(blockCount k: Int, c: Double = 0.05, delta: Double = 0.05) {
        precondition(k >= 1)
        guard k > 1 else {
            self.cdf = [1.0]
            return
        }

        let kd = Double(k)
        let r = max(1.0, c * log(kd / delta) * kd.squareRoot())
        let spike = min(k, max(1, Int((kd / r).rounded())))

        // 인덱스 = 차수 (0은 미사용)
        var pmf = [Double](repeating: 0, count: k + 1)
        pmf[1] = 1.0 / kd
        for d in 2...k {
            pmf[d] = 1.0 / (Double(d) * Double(d - 1))
        }
        for d in 1..<spike {
            pmf[d] += r / (Double(d) * kd)
        }
        pmf[spike] += r * log(r / delta) / kd

        let total = pmf.reduce(0, +)
        var cumulative = 0.0
        var table = [Double](repeating: 0, count: k)
        for d in 1...k {
            cumulative += pmf[d] / total
            table[d - 1] = cumulative
        }
        table[k - 1] = 1.0
        self.cdf = table
    }

    /// 균등 난수 하나로 차수를 샘플링한다 (CDF 이진 탐색).
    func degree(using rng: inout SplitMix64) -> Int {
        let u = Double(rng.next() >> 11) * 0x1.0p-53
        var low = 0
        var high = cdf.count - 1
        while low < high {
            let mid = (low + high) / 2
            if cdf[mid] < u {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low + 1
    }
}
