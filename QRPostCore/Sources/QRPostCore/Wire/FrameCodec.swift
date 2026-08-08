import Foundation

public enum WireError: Error, Equatable {
    case truncated
    case badMagic
    case unsupportedVersion
    case badChecksum
    case malformed
}

/// 프레임 <-> 바이트 직렬화. 리틀 엔디언.
///
/// 공통 헤더: magic(2) version(1) type(1) fileID(4) seed(8) blockCount(4) blockSize(2) fileSize(8)
/// 데이터 프레임: packetIndex(4) + payload(blockSize)
/// 메타 프레임: nameLen(1) name(UTF-8) typeLen(1) type(UTF-8)
/// 꼬리: CRC32(4) — 꼬리를 제외한 전체 바이트 대상
public enum FrameCodec {
    static let magic: [UInt8] = [0x51, 0x50]
    static let version: UInt8 = 1
    private static let dataType: UInt8 = 0
    private static let metaType: UInt8 = 1

    public static func encode(_ frame: WireFrame) -> [UInt8] {
        var out: [UInt8] = []
        let header = frame.header
        out.append(contentsOf: magic)
        out.append(version)
        switch frame {
        case .data: out.append(dataType)
        case .meta: out.append(metaType)
        }
        appendLE(header.fileID, to: &out)
        appendLE(header.seed, to: &out)
        appendLE(header.blockCount, to: &out)
        appendLE(header.blockSize, to: &out)
        appendLE(header.fileSize, to: &out)

        switch frame {
        case .data(_, let packet):
            appendLE(packet.index, to: &out)
            out.append(contentsOf: packet.payload)
        case .meta(_, let metadata):
            let name = Array(metadata.name.utf8)
            let type = Array(metadata.contentType.utf8)
            precondition(name.count <= 255 && type.count <= 255, "메타데이터 문자열은 255바이트 이하")
            out.append(UInt8(name.count))
            out.append(contentsOf: name)
            out.append(UInt8(type.count))
            out.append(contentsOf: type)
        }

        appendLE(CRC32.checksum(out), to: &out)
        return out
    }

    public static func decode(_ bytes: [UInt8]) throws -> WireFrame {
        guard bytes.count >= 34 else { throw WireError.truncated }

        let body = Array(bytes.dropLast(4))
        var tail = ByteReader(Array(bytes.suffix(4)))
        guard try tail.u32() == CRC32.checksum(body) else { throw WireError.badChecksum }

        var reader = ByteReader(body)
        guard try reader.bytes(2) == magic else { throw WireError.badMagic }
        guard try reader.u8() == version else { throw WireError.unsupportedVersion }
        let frameType = try reader.u8()

        let header = TransferHeader(
            fileID: try reader.u32(),
            seed: try reader.u64(),
            blockCount: try reader.u32(),
            blockSize: try reader.u16(),
            fileSize: try reader.u64()
        )
        // 카메라 입력은 신뢰할 수 없다 — 파라미터 정합성 검증
        guard header.blockCount >= 1, header.blockSize >= 1,
              header.fileSize >= 1,
              header.fileSize <= UInt64(header.blockCount) * UInt64(header.blockSize) else {
            throw WireError.malformed
        }

        switch frameType {
        case dataType:
            let index = try reader.u32()
            let payload = try reader.bytes(Int(header.blockSize))
            guard reader.isAtEnd else { throw WireError.malformed }
            return .data(header: header, packet: LTPacket(index: index, payload: payload))
        case metaType:
            let name = try reader.bytes(Int(reader.u8()))
            let type = try reader.bytes(Int(reader.u8()))
            guard reader.isAtEnd,
                  let nameString = String(bytes: name, encoding: .utf8),
                  let typeString = String(bytes: type, encoding: .utf8) else {
                throw WireError.malformed
            }
            return .meta(header: header, metadata: FileMetadata(name: nameString, contentType: typeString))
        default:
            throw WireError.malformed
        }
    }

    private static func appendLE<T: FixedWidthInteger>(_ value: T, to out: inout [UInt8]) {
        withUnsafeBytes(of: value.littleEndian) { out.append(contentsOf: $0) }
    }
}

private struct ByteReader {
    private let bytes: [UInt8]
    private var offset = 0

    init(_ bytes: [UInt8]) {
        self.bytes = bytes
    }

    var isAtEnd: Bool { offset == bytes.count }

    mutating func bytes(_ count: Int) throws -> [UInt8] {
        guard count >= 0, offset + count <= bytes.count else { throw WireError.truncated }
        defer { offset += count }
        return Array(bytes[offset..<offset + count])
    }

    mutating func u8() throws -> UInt8 { try fixed() }
    mutating func u16() throws -> UInt16 { try fixed() }
    mutating func u32() throws -> UInt32 { try fixed() }
    mutating func u64() throws -> UInt64 { try fixed() }

    private mutating func fixed<T: FixedWidthInteger>() throws -> T {
        let raw = try bytes(MemoryLayout<T>.size)
        var value: T = 0
        withUnsafeMutableBytes(of: &value) { $0.copyBytes(from: raw) }
        return T(littleEndian: value)
    }
}
