import Testing
import Foundation
@testable import QRPostCore

@Suite("QR 인코더")
struct QREncoderTests {
    @Test("용량 테이블이 규격 값과 일치한다 (레벨 L)")
    func capacityTable() {
        // ISO/IEC 18004 바이트 모드 용량 (레벨 L)
        let known: [Int: Int] = [1: 17, 2: 32, 3: 53, 10: 271, 14: 458, 20: 858, 40: 2_953]
        for (version, expected) in known {
            #expect(QRCodeEncoder.capacity(version: version, level: .low) == expected)
        }
    }

    @Test("심볼 크기는 4v+17이고 자동 버전 선택이 동작한다")
    func sizeAndVersionSelection() {
        let small = QRCodeEncoder.encode(Data(repeating: 1, count: 10), level: .low)
        #expect(small?.version == 1)
        #expect(small?.size == 21)

        let large = QRCodeEncoder.encode(Data(repeating: 1, count: 300), level: .low)
        #expect(large?.version == 10 + 1)  // 271 < 300 <= 321
    }

    @Test("용량 초과와 잘못된 버전 고정은 nil을 반환한다")
    func rejectsOverCapacity() {
        #expect(QRCodeEncoder.encode(Data(repeating: 0, count: 18), level: .low, version: 1) == nil)
        #expect(QRCodeEncoder.encode(Data(repeating: 0, count: 3_000), level: .low) == nil)
        #expect(QRCodeEncoder.encode(Data([1]), level: .low, version: 41) == nil)
    }

    @Test("파인더 패턴이 세 모서리에 존재한다")
    func finderPatterns() throws {
        let symbol = try #require(QRCodeEncoder.encode(Data([0xAB]), level: .low))
        let n = symbol.size
        // 파인더 중심 3x3은 어둡고, 그 바깥 한 겹은 밝다
        for (cx, cy) in [(3, 3), (n - 4, 3), (3, n - 4)] {
            #expect(symbol.module(x: cx, y: cy))
            #expect(!symbol.module(x: cx + 2, y: cy + 2))
            #expect(symbol.module(x: cx + 3, y: cy + 3))
        }
    }

    @Test("같은 입력은 같은 심볼을 만든다 (결정성)")
    func deterministic() throws {
        let data = TestData.make(size: 200, seed: 15)
        let a = try #require(QRCodeEncoder.encode(data, level: .low))
        let b = try #require(QRCodeEncoder.encode(data, level: .low))
        #expect(a.modules == b.modules)
    }
}

#if canImport(Vision) && canImport(CoreGraphics)
import Vision
import CoreGraphics

@Suite("QR 인코더 - Vision 왕복 검증")
struct QRVisionRoundTripTests {
    @Test("생성한 심볼이 표준 디코더(Vision)로 읽힌다", arguments: [5, 11, 14, 20])
    func visionDecodes(version: Int) throws {
        let capacity = QRCodeEncoder.capacity(version: version, level: .low)
        let payload = TestData.make(size: capacity, seed: UInt64(version))
        let symbol = try #require(QRCodeEncoder.encode(payload, level: .low, version: version))

        let raw = try #require(Self.decodeWithVision(symbol), "Vision이 심볼을 인식하지 못함 (버전 \(version))")
        let decoded = try #require(QRByteModeParser.payload(fromRawBitstream: raw, version: symbol.version))
        #expect(decoded == payload, "디코딩 페이로드 불일치 (버전 \(version))")
    }

    @Test("와이어 프레임 크기의 실전 페이로드가 왕복된다")
    func wireFramePayload() throws {
        let sender = SendSession(
            data: TestData.make(size: 10_000, seed: 77),
            metadata: FileMetadata(name: "roundtrip.bin", contentType: "application/octet-stream"),
            blockSize: 400,
            fileID: 9,
            seed: 10
        )
        let frame = sender.frameBytes(at: 1)
        let symbol = try #require(QRCodeEncoder.encode(Data(frame), level: .low))
        let raw = try #require(Self.decodeWithVision(symbol))
        let decoded = try #require(QRByteModeParser.payload(fromRawBitstream: raw, version: symbol.version))

        let receiver = ReceiveSession()
        #expect(receiver.ingest([UInt8](decoded)) == .progressed)
        #expect(receiver.header?.fileID == 9)
    }

    /// 심볼을 비트맵으로 그려 Vision 바코드 인식기에 통과시킨다.
    /// 모듈당 8px, 규격 최소치인 4모듈 콰이어트 존을 둔다
    private static func decodeWithVision(_ symbol: QRSymbol) -> Data? {
        let scale = 8
        let quiet = 4 * scale
        let imageSize = symbol.size * scale + quiet * 2

        var pixels = [UInt8](repeating: 255, count: imageSize * imageSize)
        for y in 0..<symbol.size {
            for x in 0..<symbol.size where symbol.module(x: x, y: y) {
                for py in 0..<scale {
                    let row = (quiet + y * scale + py) * imageSize
                    for px in 0..<scale {
                        pixels[row + quiet + x * scale + px] = 0
                    }
                }
            }
        }

        guard let context = CGContext(
            data: &pixels,
            width: imageSize,
            height: imageSize,
            bitsPerComponent: 8,
            bytesPerRow: imageSize,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ), let image = context.makeImage() else { return nil }

        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        let handler = VNImageRequestHandler(cgImage: image)
        try? handler.perform([request])
        guard let observation = request.results?.first else { return nil }
        return observation.payloadData
    }
}
#endif
