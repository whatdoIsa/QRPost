import Testing
@testable import QRPostCore

@Suite("CRC32")
struct CRC32Tests {
    @Test("표준 벡터 '123456789' → 0xCBF43926")
    func standardVector() {
        let bytes = Array("123456789".utf8)
        #expect(CRC32.checksum(bytes) == 0xCBF4_3926)
    }

    @Test("빈 입력은 0")
    func emptyInput() {
        #expect(CRC32.checksum([]) == 0)
    }

    @Test("1비트 손상도 감지한다")
    func detectsSingleBitFlip() {
        var bytes = [UInt8](repeating: 0xA5, count: 512)
        let original = CRC32.checksum(bytes)
        bytes[137] ^= 0b0000_0100
        #expect(CRC32.checksum(bytes) != original)
    }
}
