import Foundation

/// GF(2) 연립방정식 풀이.
/// 필링 디코더가 말단에서 멈췄을 때 남은 미지 블록을 직접 해결하는 데 쓴다.
enum GF2Solver {
    struct Equation {
        let neighbors: Set<Int>
        let payload: [UInt8]
    }

    struct Solution {
        let block: Int
        let payload: [UInt8]
    }

    /// 전방+후방 소거로 RREF까지 만든 뒤, 단일 미지수만 남은 행을 해로 돌려준다.
    /// 일부만 풀려도 호출 측의 필링 연쇄가 이어받는다.
    static func solve(unknowns: [Int], equations: [Equation]) -> [Solution] {
        guard !unknowns.isEmpty, !equations.isEmpty else { return [] }

        var columnOf: [Int: Int] = [:]
        for (column, block) in unknowns.enumerated() {
            columnOf[block] = column
        }

        let words = (unknowns.count + 63) / 64
        var rows: [(mask: [UInt64], payload: [UInt8])] = []
        rows.reserveCapacity(equations.count)
        for equation in equations {
            var mask = [UInt64](repeating: 0, count: words)
            for block in equation.neighbors {
                guard let column = columnOf[block] else { continue }
                mask[column >> 6] |= 1 << UInt64(column & 63)
            }
            rows.append((mask, equation.payload))
        }

        var pivotRow = 0
        for column in 0..<unknowns.count {
            let word = column >> 6
            let bit = UInt64(column & 63)
            guard let found = (pivotRow..<rows.count).first(where: { rows[$0].mask[word] >> bit & 1 == 1 }) else {
                continue
            }
            rows.swapAt(pivotRow, found)
            for i in 0..<rows.count where i != pivotRow && rows[i].mask[word] >> bit & 1 == 1 {
                for w in 0..<words {
                    rows[i].mask[w] ^= rows[pivotRow].mask[w]
                }
                for b in 0..<rows[i].payload.count {
                    rows[i].payload[b] ^= rows[pivotRow].payload[b]
                }
            }
            pivotRow += 1
            if pivotRow == rows.count { break }
        }

        var solutions: [Solution] = []
        for row in rows {
            guard row.mask.reduce(0, { $0 + $1.nonzeroBitCount }) == 1 else { continue }
            let word = row.mask.firstIndex(where: { $0 != 0 })!
            let column = word << 6 + row.mask[word].trailingZeroBitCount
            solutions.append(Solution(block: unknowns[column], payload: row.payload))
        }
        return solutions
    }
}
