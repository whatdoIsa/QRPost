import Foundation

/// 스캐너의 원시 비트스트림에서 페이로드를 추출한다.
///
/// Vision의 payloadData는 파싱된 페이로드가 아니라 QR 데이터 세그먼트의
/// 원시 비트스트림(4비트 모드 + 길이 필드 + 데이터)이다. 우리는 바이트 모드
/// 단일 세그먼트만 내보내므로 여기서 그 구조만 해석하면 된다.
public enum QRByteModeParser {
    public static func payload(fromRawBitstream raw: Data, version: Int) -> Data? {
        var reader = BitstreamReader(raw)
        guard reader.read(4) == 0b0100 else { return nil }
        guard let count = reader.read(QRCodeEncoder.countBits(version: version)) else { return nil }

        var out = [UInt8]()
        out.reserveCapacity(Int(count))
        for _ in 0..<count {
            guard let byte = reader.read(8) else { return nil }
            out.append(UInt8(byte))
        }
        return Data(out)
    }
}

private struct BitstreamReader {
    private let bytes: [UInt8]
    private var bitOffset = 0

    init(_ data: Data) {
        self.bytes = [UInt8](data)
    }

    /// MSB 우선으로 width비트를 읽는다. 남은 비트가 부족하면 nil
    mutating func read(_ width: Int) -> UInt32? {
        guard width <= 32, bitOffset + width <= bytes.count * 8 else { return nil }
        var value: UInt32 = 0
        for _ in 0..<width {
            let byte = bytes[bitOffset >> 3]
            let bit = (byte >> UInt8(7 - (bitOffset & 7))) & 1
            value = (value << 1) | UInt32(bit)
            bitOffset += 1
        }
        return value
    }
}
