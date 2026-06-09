import Foundation

public enum IMUSequence: CaseIterable {
    case sequenceA
    case sequenceB
    case sequenceC
    case sequenceD
    case sequenceE
    case sequenceF
    case sequenceG
    case sequenceH

    public var label: String {
        switch self {
        case .sequenceA: return "A"
        case .sequenceB: return "B"
        case .sequenceC: return "C"
        case .sequenceD: return "D"
        case .sequenceE: return "E"
        case .sequenceF: return "F"
        case .sequenceG: return "G"
        case .sequenceH: return "H"
        }
    }

    public var description: String {
        switch self {
        case .sequenceA: return "START_RAW_DATA 01"
        case .sequenceB: return "TOGGLE_IMU_MODE 01"
        case .sequenceC: return "START_RAW_DATA 01 → TOGGLE_IMU_MODE 01"
        case .sequenceD: return "TOGGLE_IMU_MODE 01 → START_RAW_DATA 01"
        case .sequenceE: return "START_RAW_DATA 00 → TOGGLE_IMU_MODE 01"
        case .sequenceF: return "START_RAW_DATA 01 → wait 2s → TOGGLE_IMU_MODE 01"
        case .sequenceG: return "TOGGLE_IMU_MODE 01 → wait 2s → START_RAW_DATA 01"
        case .sequenceH: return "R10R11 realtime 01 → START_RAW_DATA 01 → TOGGLE_IMU_MODE 01"
        }
    }
}
