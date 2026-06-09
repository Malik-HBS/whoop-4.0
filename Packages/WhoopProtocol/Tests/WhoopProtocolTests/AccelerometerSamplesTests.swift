import XCTest
@testable import WhoopProtocol

final class AccelerometerSamplesTests: XCTestCase {
    private func makeType43IMUFrame(timestamp: UInt32 = 31_538_447) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: 1917)
        writeU32(&data, 4, timestamp)
        data[14] = 60
        data[15] = 0
        writeI16Block(&data, 82, value: 4096, count: 100)
        writeI16Block(&data, 282, value: 0, count: 100)
        writeI16Block(&data, 482, value: 0, count: 100)
        return frameFromPayload(data, type: 43, seq: 1, cmd: 0)
    }

    private func makeType43OpticalFrame(timestamp: UInt32 = 31_538_448) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: 1921)
        writeU32(&data, 4, timestamp)
        return frameFromPayload(data, type: 43, seq: 2, cmd: 0)
    }

    private func writeU32(_ bytes: inout [UInt8], _ offset: Int, _ value: UInt32) {
        bytes[offset] = UInt8(value & 0xFF)
        bytes[offset + 1] = UInt8((value >> 8) & 0xFF)
        bytes[offset + 2] = UInt8((value >> 16) & 0xFF)
        bytes[offset + 3] = UInt8((value >> 24) & 0xFF)
    }

    private func writeI16Block(_ bytes: inout [UInt8], _ offset: Int, value: Int16, count: Int) {
        let raw = UInt16(bitPattern: value)
        for i in 0..<count {
            let base = offset + (i * 2)
            bytes[base] = UInt8(raw & 0xFF)
            bytes[base + 1] = UInt8((raw >> 8) & 0xFF)
        }
    }

    func testType43PacketInfoClassifiesIMUAndOptical() {
        XCTAssertEqual(type43PacketInfo(from: makeType43IMUFrame()),
                       Type43PacketInfo(dataLength: 1917, kind: .imu))
        XCTAssertEqual(type43PacketInfo(from: makeType43OpticalFrame()),
                       Type43PacketInfo(dataLength: 1921, kind: .optical))
    }

    func testExtractAccelerometerSamplesReturnsSamplesForIMU() throws {
        let samples = extractAccelerometerSamples(from: makeType43IMUFrame(),
                                                 deviceClockRef: 31_538_447,
                                                 wallClockRef: 1_716_400_000)
        XCTAssertEqual(samples.count, 100)
        let first = try XCTUnwrap(samples.first)
        XCTAssertEqual(first.x, 1.0, accuracy: 0.0001)
        XCTAssertEqual(first.y, 0.0, accuracy: 0.0001)
        XCTAssertEqual(first.z, 0.0, accuracy: 0.0001)
    }

    func testExtractAccelerometerSamplesIgnoresOptical() {
        let samples = extractAccelerometerSamples(from: makeType43OpticalFrame(),
                                                 deviceClockRef: 31_538_448,
                                                 wallClockRef: 1_716_400_000)
        XCTAssertTrue(samples.isEmpty)
    }
}
