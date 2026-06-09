import Foundation

public struct AccelerometerSample: Equatable, Codable, Sendable {
    public let timestamp: Date
    public let x: Double
    public let y: Double
    public let z: Double
    public let unit: String

    public init(timestamp: Date, x: Double, y: Double, z: Double, unit: String = "g") {
        self.timestamp = timestamp
        self.x = x
        self.y = y
        self.z = z
        self.unit = unit
    }
}

public enum Type43PacketKind: String, Equatable, Sendable {
    case imu
    case optical
    case unknown
}

public struct Type43PacketInfo: Equatable, Sendable {
    public let dataLength: Int
    public let kind: Type43PacketKind

    public init(dataLength: Int, kind: Type43PacketKind) {
        self.dataLength = dataLength
        self.kind = kind
    }
}

private func protocolU16(_ f: [UInt8], _ off: Int) -> Int? {
    off + 2 <= f.count ? Int(f[off]) | (Int(f[off + 1]) << 8) : nil
}

private func protocolU32(_ f: [UInt8], _ off: Int) -> UInt32? {
    guard off + 4 <= f.count else { return nil }
    return UInt32(f[off]) | (UInt32(f[off + 1]) << 8) | (UInt32(f[off + 2]) << 16) | (UInt32(f[off + 3]) << 24)
}

private func protocolI16Block(_ frame: [UInt8], _ off: Int, _ count: Int) -> [Int] {
    var n = count
    if off + n * 2 > frame.count {
        n = max(0, (frame.count - off) / 2)
    }
    guard n > 0 else { return [] }

    var out: [Int] = []
    out.reserveCapacity(n)
    for i in 0..<n {
        let p = off + i * 2
        let raw = UInt16(frame[p]) | (UInt16(frame[p + 1]) << 8)
        out.append(Int(Int16(bitPattern: raw)))
    }
    return out
}

public func type43PacketInfo(from frame: [UInt8]) -> Type43PacketInfo? {
    guard frame.count > 17, frame[4] == 43 else { return nil }
    let length = Int(frame[1]) | (Int(frame[2]) << 8)
    let dataLen = length - 7
    guard let spec = loadSchema().packet(forType: Int(frame[4])),
          let variant = spec.variants[String(dataLen)] else {
        return Type43PacketInfo(dataLength: dataLen, kind: .unknown)
    }

    let kind: Type43PacketKind
    switch variant.kind {
    case "imu":
        kind = .imu
    case "optical":
        kind = .optical
    default:
        kind = .unknown
    }
    return Type43PacketInfo(dataLength: dataLen, kind: kind)
}

/// Extracts per-sample accelerometer readings from WHOOP type-43 realtime IMU frames.
///
/// The verified Gen 4 layout carries 100 signed i16 samples per axis at roughly 100 Hz with
/// scale 1/4096 g. Returned timestamps are wall-clock dates derived from the device clock
/// correlation plus the packet subseconds and evenly-spaced intra-packet sample offsets.
public func extractAccelerometerSamples(from frames: [[UInt8]],
                                        deviceClockRef: Int,
                                        wallClockRef: Int,
                                        sampleRateHz: Double = 100.0) -> [AccelerometerSample] {
    frames.flatMap {
        extractAccelerometerSamples(from: $0,
                                    deviceClockRef: deviceClockRef,
                                    wallClockRef: wallClockRef,
                                    sampleRateHz: sampleRateHz)
    }
}

public func extractAccelerometerSamples(from frame: [UInt8],
                                        deviceClockRef: Int,
                                        wallClockRef: Int,
                                        sampleRateHz: Double = 100.0) -> [AccelerometerSample] {
    guard frame.count > 17, frame[4] == 43 else { return [] }
    guard let packetInfo = type43PacketInfo(from: frame),
          packetInfo.kind == .imu else {
        return []
    }

    guard let spec = loadSchema().packet(forType: Int(frame[4])),
          let variant = spec.variants[String(packetInfo.dataLength)],
          let sampleCount = variant.samples,
          let timestamp = protocolU32(frame, 11).map(Int.init) else {
        return []
    }

    let accelAxes = variant.axes.filter { $0.cat == "accel" }
    guard accelAxes.count >= 3 else { return [] }

    let xValues = protocolI16Block(frame, accelAxes[0].off, sampleCount)
    let yValues = protocolI16Block(frame, accelAxes[1].off, sampleCount)
    let zValues = protocolI16Block(frame, accelAxes[2].off, sampleCount)
    let count = min(sampleCount, xValues.count, yValues.count, zValues.count)
    guard count > 0 else { return [] }

    let scale = variant.accelScale ?? (1.0 / 4096.0)
    let unit = variant.accelUnit ?? "g"
    let subseconds = Double(protocolU16(frame, 15) ?? 0) / 32768.0
    let packetStart = Double(wallClockRef + (timestamp - deviceClockRef)) + subseconds
    let interval = sampleRateHz > 0 ? 1.0 / sampleRateHz : 0.01

    var samples: [AccelerometerSample] = []
    samples.reserveCapacity(count)
    for i in 0..<count {
        samples.append(AccelerometerSample(
            timestamp: Date(timeIntervalSince1970: packetStart + Double(i) * interval),
            x: Double(xValues[i]) * scale,
            y: Double(yValues[i]) * scale,
            z: Double(zValues[i]) * scale,
            unit: unit
        ))
    }
    return samples
}
