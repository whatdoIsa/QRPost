import Foundation
@testable import QRPostCore

enum TestData {
    /// 결정적 랜덤 데이터 — 시스템 난수를 쓰지 않아 테스트가 항상 재현된다
    static func make(size: Int, seed: UInt64) -> Data {
        var rng = SplitMix64(seed: seed)
        var bytes = [UInt8]()
        bytes.reserveCapacity(size)
        while bytes.count < size {
            var word = rng.next()
            for _ in 0..<8 where bytes.count < size {
                bytes.append(UInt8(truncatingIfNeeded: word))
                word >>= 8
            }
        }
        return Data(bytes)
    }

    static func uniform(_ rng: inout SplitMix64) -> Double {
        Double(rng.next() >> 11) * 0x1.0p-53
    }
}
