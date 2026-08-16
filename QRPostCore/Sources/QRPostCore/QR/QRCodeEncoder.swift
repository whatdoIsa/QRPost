import Foundation

// qrdrop(팀 저장소)의 QRCodeEncoder를 이식. 구조는 Project Nayuki의
// ISO/IEC 18004 레퍼런스 구현을 따른다.
//
// CIQRCodeGenerator를 쓰지 않는 이유: Apple 생성기는 페이로드에서 숫자·영숫자
// 구간을 발견하면 세그먼트를 임의로 분할한다. 텍스트에는 맞는 동작이지만
// 바이너리 페이로드가 OS 버전에 따라 달라질 수 있는 경계로 쪼개져 나온다.
// 바이트 모드 단일 세그먼트만 내보내면 수신 측은 4비트 모드, 길이, 그 길이만큼의
// 바이트만 읽으면 된다 — 스트림에 다른 것이 절대 섞이지 않는다.

/// 인코딩된 QR 심볼. 렌더링(이미지 변환)은 앱 계층 담당.
public struct QRSymbol: Sendable {
    /// 한 변의 모듈 수
    public let size: Int
    /// 행 우선, true = 어두운 모듈
    public let modules: [Bool]

    public var version: Int { (size - 17) / 4 }

    public func module(x: Int, y: Int) -> Bool {
        modules[y * size + x]
    }
}

public enum QRErrorCorrection: Int, CaseIterable, Sendable {
    case low = 0, medium = 1, quartile = 2, high = 3

    /// 포맷 정보 영역에 기록되는 2비트 값
    var formatBits: UInt32 {
        switch self {
        case .low: return 1
        case .medium: return 0
        case .quartile: return 3
        case .high: return 2
        }
    }
}

public enum QRCodeEncoder {
    /// data를 바이트 모드 단일 세그먼트로 인코딩한다.
    /// - Parameter version: 지정하면 해당 버전 고정, nil이면 들어가는 최소 버전 선택
    public static func encode(
        _ data: Data,
        level: QRErrorCorrection,
        version pinned: Int? = nil,
        forcedMask: Int? = nil
    ) -> QRSymbol? {
        let bytes = [UInt8](data)

        let version: Int
        if let pinned {
            guard (1...40).contains(pinned), bytes.count <= capacity(version: pinned, level: level) else { return nil }
            version = pinned
        } else {
            guard let chosen = (1...40).first(where: { bytes.count <= capacity(version: $0, level: level) }) else {
                return nil
            }
            version = chosen
        }

        let codewords = dataCodewords(bytes, version: version, level: level)
        let full = addECCAndInterleave(codewords, version: version, level: level)
        return draw(codewords: full, version: version, level: level, forcedMask: forcedMask)
    }

    // MARK: - 용량

    /// 오류 정정을 빼기 전의 데이터 모듈 수
    static func rawDataModules(version: Int) -> Int {
        var result = (16 * version + 128) * version + 64
        if version >= 2 {
            let alignmentCount = version / 7 + 2
            result -= (25 * alignmentCount - 10) * alignmentCount - 55
            if version >= 7 { result -= 36 }
        }
        return result
    }

    static func dataCodewordCount(version: Int, level: QRErrorCorrection) -> Int {
        rawDataModules(version: version) / 8
            - eccCodewordsPerBlock[level.rawValue][version] * eccBlockCount[level.rawValue][version]
    }

    /// 바이트 모드 문자 수 필드의 비트 폭
    static func countBits(version: Int) -> Int {
        version <= 9 ? 8 : 16
    }

    /// 버전·레벨 조합이 담을 수 있는 최대 바이트 수
    public static func capacity(version: Int, level: QRErrorCorrection) -> Int {
        let available = dataCodewordCount(version: version, level: level) * 8 - 4 - countBits(version: version)
        return max(0, available / 8)
    }

    // MARK: - 비트스트림

    private static func dataCodewords(_ bytes: [UInt8], version: Int, level: QRErrorCorrection) -> [UInt8] {
        var bits = BitBuffer()
        bits.append(0b0100, width: 4)  // 바이트 모드
        bits.append(UInt32(bytes.count), width: countBits(version: version))
        for byte in bytes {
            bits.append(UInt32(byte), width: 8)
        }

        let capacityBits = dataCodewordCount(version: version, level: level) * 8

        // 종결자, 코드워드 경계 정렬
        bits.append(0, width: min(4, capacityBits - bits.count))
        bits.append(0, width: (8 - bits.count % 8) % 8)

        // 규격이 정한 교대 패딩 코드워드
        var pad: UInt32 = 0xEC
        while bits.count < capacityBits {
            bits.append(pad, width: 8)
            pad ^= 0xEC ^ 0x11
        }

        return bits.bytes
    }

    // MARK: - 오류 정정

    private static func addECCAndInterleave(
        _ data: [UInt8],
        version: Int,
        level: QRErrorCorrection
    ) -> [UInt8] {
        let blockCount = eccBlockCount[level.rawValue][version]
        let blockEccLength = eccCodewordsPerBlock[level.rawValue][version]
        let rawCodewords = rawDataModules(version: version) / 8
        let shortBlockCount = blockCount - rawCodewords % blockCount
        let shortBlockLength = rawCodewords / blockCount

        let divisor = reedSolomonDivisor(degree: blockEccLength)

        var blocks: [[UInt8]] = []
        var cursor = 0
        for i in 0..<blockCount {
            let dataLength = shortBlockLength - blockEccLength + (i < shortBlockCount ? 0 : 1)
            let chunk = Array(data[cursor..<(cursor + dataLength)])
            cursor += dataLength

            // 모든 블록을 같은 길이로 맞춰 인터리빙을 단순 열 순회로 만든다.
            // 짧은 블록은 슬롯 하나를 비워 둔다
            var block = chunk + [UInt8](repeating: 0, count: shortBlockLength + 1 - dataLength)
            let ecc = reedSolomonRemainder(chunk, divisor: divisor)
            block.replaceSubrange((block.count - blockEccLength)..<block.count, with: ecc)
            blocks.append(block)
        }

        var result = [UInt8]()
        result.reserveCapacity(rawCodewords)
        for i in 0...shortBlockLength {
            for j in 0..<blockCount {
                if i != shortBlockLength - blockEccLength || j >= shortBlockCount {
                    result.append(blocks[j][i])
                }
            }
        }
        return result
    }

    private static func reedSolomonDivisor(degree: Int) -> [UInt8] {
        var result = [UInt8](repeating: 0, count: degree)
        result[degree - 1] = 1
        var root: UInt8 = 1
        for _ in 0..<degree {
            for j in 0..<degree {
                result[j] = galoisMultiply(result[j], root)
                if j + 1 < degree {
                    result[j] ^= result[j + 1]
                }
            }
            root = galoisMultiply(root, 0x02)
        }
        return result
    }

    private static func reedSolomonRemainder(_ data: [UInt8], divisor: [UInt8]) -> [UInt8] {
        var result = [UInt8](repeating: 0, count: divisor.count)
        for byte in data {
            let factor = byte ^ result.removeFirst()
            result.append(0)
            for i in 0..<divisor.count {
                result[i] ^= galoisMultiply(divisor[i], factor)
            }
        }
        return result
    }

    /// GF(2^8) 곱셈, 법 x^8 + x^4 + x^3 + x^2 + 1
    private static func galoisMultiply(_ x: UInt8, _ y: UInt8) -> UInt8 {
        var result: UInt8 = 0
        var i = 7
        while i >= 0 {
            result = (result << 1) ^ ((result >> 7) &* 0x1D)
            result ^= ((y >> UInt8(i)) & 1) &* x
            i -= 1
        }
        return result
    }

    // MARK: - 모듈 배치

    private static func draw(
        codewords: [UInt8],
        version: Int,
        level: QRErrorCorrection,
        forcedMask: Int?
    ) -> QRSymbol {
        let size = version * 4 + 17
        var modules = [Bool](repeating: false, count: size * size)
        var isFunction = [Bool](repeating: false, count: size * size)

        func set(_ x: Int, _ y: Int, _ dark: Bool) {
            guard x >= 0, x < size, y >= 0, y < size else { return }
            modules[y * size + x] = dark
            isFunction[y * size + x] = true
        }

        // 타이밍 패턴
        for i in 0..<size {
            set(6, i, i % 2 == 0)
            set(i, 6, i % 2 == 0)
        }

        // 파인더 패턴과 분리대
        for (cx, cy) in [(3, 3), (size - 4, 3), (3, size - 4)] {
            for dy in -4...4 {
                for dx in -4...4 {
                    let distance = max(abs(dx), abs(dy))
                    set(cx + dx, cy + dy, distance != 2 && distance != 4)
                }
            }
        }

        // 정렬 패턴 (파인더와 겹치는 세 모서리는 제외)
        let positions = alignmentPositions(version: version)
        for (i, ax) in positions.enumerated() {
            for (j, ay) in positions.enumerated() {
                let isCorner = (i == 0 && j == 0)
                    || (i == 0 && j == positions.count - 1)
                    || (i == positions.count - 1 && j == 0)
                guard !isCorner else { continue }
                for dy in -2...2 {
                    for dx in -2...2 {
                        set(ax + dx, ay + dy, max(abs(dx), abs(dy)) != 1)
                    }
                }
            }
        }

        // 버전 정보 (버전 7 이상)
        if version >= 7 {
            var remainder = UInt32(version)
            for _ in 0..<12 {
                remainder = (remainder << 1) ^ ((remainder >> 11) * 0x1F25)
            }
            let bits = (UInt32(version) << 12) | remainder
            for i in 0..<18 {
                let dark = (bits >> UInt32(i)) & 1 != 0
                let a = size - 11 + i % 3
                let b = i / 3
                set(a, b, dark)
                set(b, a, dark)
            }
        }

        // 포맷 정보 영역 예약. 실제 비트는 마스크 확정 후 기록한다
        drawFormatBits(mask: 0, level: level, size: size, set: set)

        // 데이터 코드워드 배치 — 두 모듈 폭 열을 지그재그로
        var bitIndex = 0
        let totalBits = codewords.count * 8
        var right = size - 1
        while right >= 1 {
            if right == 6 { right = 5 }  // 세로 타이밍 패턴 열
            for vertical in 0..<size {
                for j in 0..<2 {
                    let x = right - j
                    let upward = ((right + 1) & 2) == 0
                    let y = upward ? size - 1 - vertical : vertical
                    guard !isFunction[y * size + x], bitIndex < totalBits else { continue }
                    let byte = codewords[bitIndex >> 3]
                    modules[y * size + x] = (byte >> UInt8(7 - (bitIndex & 7))) & 1 != 0
                    bitIndex += 1
                }
            }
            right -= 2
        }

        // 모든 마스크를 시험해 패널티가 가장 낮은 것을 선택한다
        var best = modules
        var bestPenalty = Int.max
        let candidates = forcedMask.map { [$0] } ?? Array(0..<8)
        for mask in candidates {
            var candidate = modules
            applyMask(mask, to: &candidate, isFunction: isFunction, size: size)
            var withFormat = candidate
            drawFormatBits(mask: mask, level: level, size: size) { x, y, dark in
                guard x >= 0, x < size, y >= 0, y < size else { return }
                withFormat[y * size + x] = dark
            }
            let penalty = penaltyScore(withFormat, size: size)
            if penalty < bestPenalty {
                bestPenalty = penalty
                best = withFormat
            }
        }

        return QRSymbol(size: size, modules: best)
    }

    private static func drawFormatBits(
        mask: Int,
        level: QRErrorCorrection,
        size: Int,
        set: (Int, Int, Bool) -> Void
    ) {
        let data = (level.formatBits << 3) | UInt32(mask)
        var remainder = data
        for _ in 0..<10 {
            remainder = (remainder << 1) ^ ((remainder >> 9) * 0x537)
        }
        let bits = ((data << 10) | remainder) ^ 0x5412

        func bit(_ i: Int) -> Bool { (bits >> UInt32(i)) & 1 != 0 }

        for i in 0..<6 { set(8, i, bit(i)) }
        set(8, 7, bit(6))
        set(8, 8, bit(7))
        set(7, 8, bit(8))
        for i in 9..<15 { set(14 - i, 8, bit(i)) }

        for i in 0..<8 { set(size - 1 - i, 8, bit(i)) }
        for i in 8..<15 { set(8, size - 15 + i, bit(i)) }
        set(8, size - 8, true)  // 항상 어두운 모듈
    }

    private static func applyMask(_ mask: Int, to modules: inout [Bool], isFunction: [Bool], size: Int) {
        for y in 0..<size {
            for x in 0..<size {
                guard !isFunction[y * size + x] else { continue }
                let invert: Bool
                switch mask {
                case 0: invert = (x + y) % 2 == 0
                case 1: invert = y % 2 == 0
                case 2: invert = x % 3 == 0
                case 3: invert = (x + y) % 3 == 0
                case 4: invert = (x / 3 + y / 2) % 2 == 0
                case 5: invert = (x * y) % 2 + (x * y) % 3 == 0
                case 6: invert = ((x * y) % 2 + (x * y) % 3) % 2 == 0
                default: invert = ((x + y) % 2 + (x * y) % 3) % 2 == 0
                }
                if invert { modules[y * size + x].toggle() }
            }
        }
    }

    private static func alignmentPositions(version: Int) -> [Int] {
        guard version > 1 else { return [] }
        let count = version / 7 + 2
        let size = version * 4 + 17
        let step = version == 32 ? 26 : (version * 4 + count * 2 + 1) / (count * 2 - 2) * 2

        var result = [Int](repeating: 0, count: count)
        result[0] = 6
        var position = size - 7
        var i = count - 1
        while i >= 1 {
            result[i] = position
            position -= step
            i -= 1
        }
        return result
    }

    // MARK: - 마스크 패널티

    private static func penaltyScore(_ modules: [Bool], size: Int) -> Int {
        let n1 = 3, n2 = 3, n3 = 40, n4 = 10
        var score = 0

        func dark(_ x: Int, _ y: Int) -> Bool { modules[y * size + x] }

        // 규칙 1: 같은 색 5개 이상 연속
        for y in 0..<size {
            var runColor = dark(0, y)
            var runLength = 1
            for x in 1..<size {
                if dark(x, y) == runColor {
                    runLength += 1
                } else {
                    if runLength >= 5 { score += n1 + runLength - 5 }
                    runColor = dark(x, y)
                    runLength = 1
                }
            }
            if runLength >= 5 { score += n1 + runLength - 5 }
        }
        for x in 0..<size {
            var runColor = dark(x, 0)
            var runLength = 1
            for y in 1..<size {
                if dark(x, y) == runColor {
                    runLength += 1
                } else {
                    if runLength >= 5 { score += n1 + runLength - 5 }
                    runColor = dark(x, y)
                    runLength = 1
                }
            }
            if runLength >= 5 { score += n1 + runLength - 5 }
        }

        // 규칙 2: 2x2 단색 블록
        for y in 0..<(size - 1) {
            for x in 0..<(size - 1) {
                let c = dark(x, y)
                if c == dark(x + 1, y), c == dark(x, y + 1), c == dark(x + 1, y + 1) {
                    score += n2
                }
            }
        }

        // 규칙 3: 파인더를 흉내 내는 1:1:3:1:1 시그니처
        let pattern: [Bool] = [true, false, true, true, true, false, true]
        for y in 0..<size {
            for x in 0..<(size - 6) {
                var matches = true
                for k in 0..<7 where dark(x + k, y) != pattern[k] { matches = false; break }
                guard matches else { continue }
                let leftClear = (max(0, x - 4)..<x).allSatisfy { !dark($0, y) } && x >= 4
                let rightClear = ((x + 7)..<min(size, x + 11)).allSatisfy { !dark($0, y) } && x + 11 <= size
                if leftClear || rightClear { score += n3 }
            }
        }
        for x in 0..<size {
            for y in 0..<(size - 6) {
                var matches = true
                for k in 0..<7 where dark(x, y + k) != pattern[k] { matches = false; break }
                guard matches else { continue }
                let topClear = (max(0, y - 4)..<y).allSatisfy { !dark(x, $0) } && y >= 4
                let bottomClear = ((y + 7)..<min(size, y + 11)).allSatisfy { !dark(x, $0) } && y + 11 <= size
                if topClear || bottomClear { score += n3 }
            }
        }

        // 규칙 4: 명암 비율의 치우침
        let darkCount = modules.reduce(0) { $0 + ($1 ? 1 : 0) }
        let total = size * size
        let deviation = abs(darkCount * 20 - total * 10) / total
        score += deviation * n4

        return score
    }

    // MARK: - 규격 테이블

    // 인덱스는 [레벨][버전], 0번 항목은 미사용
    private static let eccCodewordsPerBlock: [[Int]] = [
        // L
        [-1, 7, 10, 15, 20, 26, 18, 20, 24, 30, 18, 20, 24, 26, 30, 22, 24, 28, 30, 28,
         28, 28, 28, 30, 30, 26, 28, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30],
        // M
        [-1, 10, 16, 26, 18, 24, 16, 18, 22, 22, 26, 30, 22, 22, 24, 24, 28, 28, 26, 26,
         26, 26, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28],
        // Q
        [-1, 13, 22, 18, 26, 18, 24, 18, 22, 20, 24, 28, 26, 24, 20, 30, 24, 28, 28, 26,
         30, 28, 30, 30, 30, 30, 28, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30],
        // H
        [-1, 17, 28, 22, 16, 22, 28, 26, 26, 24, 28, 24, 28, 22, 24, 24, 30, 28, 28, 26,
         28, 30, 24, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30],
    ]

    private static let eccBlockCount: [[Int]] = [
        // L
        [-1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 4, 4, 4, 4, 4, 6, 6, 6, 6, 7,
         8, 8, 9, 9, 10, 12, 12, 12, 13, 14, 15, 16, 17, 18, 19, 19, 20, 21, 22, 24, 25],
        // M
        [-1, 1, 1, 1, 2, 2, 4, 4, 4, 5, 5, 5, 8, 9, 9, 10, 10, 11, 13, 14,
         16, 17, 17, 18, 20, 21, 23, 25, 26, 28, 29, 31, 33, 35, 37, 38, 40, 43, 45, 47, 49],
        // Q
        [-1, 1, 1, 2, 2, 4, 4, 6, 6, 8, 8, 8, 10, 12, 16, 12, 17, 16, 18, 21,
         20, 23, 23, 25, 27, 29, 34, 34, 35, 38, 40, 43, 45, 48, 51, 53, 56, 59, 62, 65, 68],
        // H
        [-1, 1, 1, 2, 4, 4, 4, 5, 6, 8, 8, 11, 11, 16, 16, 18, 16, 19, 21, 25,
         25, 25, 34, 30, 32, 35, 37, 40, 42, 45, 48, 51, 54, 57, 60, 63, 66, 70, 74, 77, 81],
    ]
}

// MARK: - 비트 버퍼

private struct BitBuffer {
    private(set) var bytes: [UInt8] = []
    private(set) var count = 0

    mutating func append(_ value: UInt32, width: Int) {
        guard width > 0 else { return }
        var i = width - 1
        while i >= 0 {
            if count % 8 == 0 { bytes.append(0) }
            let bit = (value >> UInt32(i)) & 1
            if bit != 0 {
                bytes[count / 8] |= 1 << UInt8(7 - count % 8)
            }
            count += 1
            i -= 1
        }
    }
}
