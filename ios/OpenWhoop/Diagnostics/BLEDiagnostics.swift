import Foundation
import WhoopProtocol
import WhoopStore

enum BackfillHistoryState: String {
    case idle
    case requested
    case inFlight
    case receivedMetadata
    case receivingData
    case complete
    case failed
    case timedOut
    case noHistoryServed
}

struct IMUSequenceResult: Equatable {
    let sequenceName: String
    let commandsSent: [String]
    let payloadsSent: [[UInt8]]
    let responsesReceived: [[UInt8]]
    let responseStatuses: [String]
    let frame43CountAfter10s: Int
    let frame40CountAfter10s: Int
    let frame50CountAfter10s: Int
    let unknownFrameTypes: [Int: Int]
    let success: Bool
    let failureReason: String?
}

/// Per-frame + per-stream + per-upload diagnostics. `@MainActor` so SwiftUI views can
/// observe it without thread-hop ceremony, and so a single writer is the only contention
/// concern (the BLE delegate is on the main queue).
///
/// WHY THIS IS A SEPARATE TYPE FROM `ServerDiagnostics`: ServerDiagnostics is about the
/// *server* (configured? last upload? last pull?). This is about the *pipeline* itself —
/// are BLE frames arriving? are the type-47 offload frames showing up? did the live
/// standard-HR path persist anything? Did the last uploader drain have anything to send?
/// The two are related but not the same diagnostic question, so they stay separate.
@MainActor
final class BLEDiagnostics: ObservableObject {
    static let shared = BLEDiagnostics()

    // MARK: - Standard BLE HR (0x2A37)
    @Published private(set) var standardHRNotifications: Int = 0
    @Published private(set) var standardHRSaved: Int = 0
    @Published private(set) var standardHRSkippedDedupe: Int = 0
    @Published private(set) var standardRRSaved: Int = 0

    // MARK: - Frame 40 REALTIME_DATA live HR/RR
    @Published private(set) var frame40HRDecodeAttempts: Int = 0
    @Published private(set) var frame40HRDecoded: Int = 0
    @Published private(set) var frame40HRDecodeFailed: Int = 0
    @Published private(set) var frame40RRDecoded: Int = 0
    @Published private(set) var frame40HRSaved: Int = 0
    @Published private(set) var frame40HRSaveFailed: Int = 0
    @Published private(set) var frame40HRDeduped: Int = 0
    @Published private(set) var frame40RRSaved: Int = 0
    @Published private(set) var lastFrame40HRValue: Int? = nil
    @Published private(set) var lastFrame40RRCount: Int = 0
    @Published private(set) var lastFrame40SaveError: String = "—"
    @Published private(set) var lastFrame40DedupeReason: String = "—"
    @Published private(set) var lastFrame40DecodeFailureReason: String = "—"

    // MARK: - Live UI HR path
    @Published private(set) var lastLiveUIHRValue: Int? = nil
    @Published private(set) var lastLiveUIHRSaved: Bool? = nil

    // MARK: - Custom-service frame counters (reassembled, post-FRAME_ROUTER)
    @Published private(set) var frame40Count: Int = 0   // REALTIME_DATA
    @Published private(set) var frame43Count: Int = 0   // REALTIME_RAW_DATA
    @Published private(set) var frame47Count: Int = 0   // HISTORICAL_DATA (the type-47 biometric source)
    @Published private(set) var frame48Count: Int = 0   // EVENT
    @Published private(set) var frame49Count: Int = 0   // METADATA (HISTORY_START/END)
    @Published private(set) var frame50Count: Int = 0   // CONSOLE_LOGS

    // MARK: - Type-43 IMU / Gravity live path
    @Published private(set) var motionGravityStreamActive: Bool = false
    @Published private(set) var dataNotifyActive: Bool = false
    @Published private(set) var type43IMUDecodeAttempts: Int = 0
    @Published private(set) var type43IMUDecoded: Int = 0
    @Published private(set) var type43IMUDecodeFailed: Int = 0
    @Published private(set) var type43OpticalIgnored: Int = 0
    @Published private(set) var type43UnknownVariantCount: Int = 0
    @Published private(set) var type43Len1917Count: Int = 0
    @Published private(set) var type43Len1921Count: Int = 0
    @Published private(set) var type43OtherLenCount: Int = 0
    @Published private(set) var type43GravityRowsDerived: Int = 0
    @Published private(set) var type43GravityRowsSaved: Int = 0
    @Published private(set) var lastType43Length: Int? = nil
    @Published private(set) var lastType43DecodeError: String = "—"
    @Published private(set) var startRawDataSentCount: Int = 0
    @Published private(set) var toggleIMUModeSentCount: Int = 0
    @Published private(set) var stopRawDataSentCount: Int = 0
    @Published private(set) var lastStartRawDataPayload: String = "—"
    @Published private(set) var lastToggleIMUModePayload: String = "—"
    @Published private(set) var lastStopRawDataPayload: String = "—"
    @Published private(set) var sendR10R11RealtimeOnSentCount: Int = 0
    @Published private(set) var sendR10R11RealtimeOffSentCount: Int = 0
    @Published private(set) var lastSendR10R11RealtimePayload: String = "—"
    @Published private(set) var motionGravityAckSeen: Bool = false
    @Published private(set) var lastCommandResponseBytes: String = "—"

    // MARK: - Backfill state (mirrors BLEManager + Backfiller)
    @Published private(set) var historyState: BackfillHistoryState = .idle
    @Published private(set) var backfillInFlight: Bool = false
    @Published private(set) var backfillLastReason: String = "—"
    @Published private(set) var backfillStartCount: Int = 0
    @Published private(set) var backfillCompleteCount: Int = 0
    @Published private(set) var backfillTimeoutCount: Int = 0
    @Published private(set) var backfillErrorCount: Int = 0
    @Published private(set) var backfillLastAtUnix: Double? = nil
    @Published private(set) var historySendCount: Int = 0
    @Published private(set) var lastHistoryPayload: String = "—"
    @Published private(set) var historyAckSeen: Bool = false
    @Published private(set) var lastDataRangeResponse: String = "—"
    @Published private(set) var historyMetadataStartCount: Int = 0
    @Published private(set) var historyMetadataEndCount: Int = 0
    @Published private(set) var historyMetadataCompleteCount: Int = 0
    @Published private(set) var frame47DecodeSucceeded: Int = 0
    @Published private(set) var frame47DecodeFailed: Int = 0
    @Published private(set) var lastFrame47DecodeError: String = "—"
    @Published private(set) var lastType47Timestamp: Int? = nil
    @Published private(set) var savedSpO2Rows: Int = 0
    @Published private(set) var savedSkinTempRows: Int = 0
    @Published private(set) var savedRespRows: Int = 0
    @Published private(set) var savedGravityRows: Int = 0

    // MARK: - Raw capture (research toggle)
    @Published private(set) var rawCaptureEnabled: Bool = false
    @Published private(set) var rawLocalBatches: Int = 0
    @Published private(set) var rawLocalBytes: Int = 0
    @Published private(set) var rawLatestBatchAt: Date? = nil

    // MARK: - Local store snapshot (per-decoded-stream)
    @Published private(set) var localSnapshot: LocalStoreSnapshot? = nil
    @Published private(set) var localSnapshotAt: Date? = nil

    // MARK: - Last upload payload counts (per stream, what was actually sent)
    @Published private(set) var lastUploadPayloadCounts: [String: Int] = [:]
    @Published private(set) var lastUploadPendingCounts: [String: Int] = [:]
    @Published private(set) var lastUploadAt: Date? = nil

    // MARK: - IMU/Gravity Developer Diagnostics
    @Published private(set) var keepIMUStreamOnWhileOpen: Bool = false
    @Published private(set) var gravityTestStartedAt: Date? = nil
    @Published private(set) var gravityTestShouldStopAt: Date? = nil
    @Published private(set) var gravityTestStopReason: String = "—"
    @Published private(set) var lastCommandResponseDecoded: String = "—"
    @Published private(set) var lastCommandResponseStatus: String = "—"
    @Published private(set) var lastCommandResponseCommand: String = "—"
    @Published private(set) var lastCommandResponseMeaning: String = "—"
    @Published private(set) var frameHistogram: [Int: Int] = [:]
    @Published private(set) var lastUnknownFrameType: Int? = nil
    @Published private(set) var lastUnknownFrameLength: Int? = nil
    @Published private(set) var last10FrameTypes: [(type: Int, length: Int)] = []
    @Published private(set) var frame51Count: Int = 0
    @Published private(set) var frame52Count: Int = 0
    @Published private(set) var bonded: Bool = false
    @Published private(set) var encryptionState: String = "—"
    @Published private(set) var cmdCharDiscovered: Bool = false
    @Published private(set) var dataCharNotifyEnabled: Bool = false
    @Published private(set) var lastWriteType: String = "—"
    @Published private(set) var lastWriteSuccess: Bool = false
    @Published private(set) var handshakeRawStopSent: Bool = false
    @Published private(set) var sendR10R11RealtimeStopSent: Bool = false
    @Published private(set) var backfillDisabledRawStream: Bool = false
    @Published private(set) var gravityStreamRestartedAfterHandshake: Bool = false
    @Published private(set) var gravityStreamRestartedAfterBackfill: Bool = false
    @Published private(set) var legacyRawAccelFrame43Count: Int = 0
    @Published private(set) var legacyRawAccelFrame40Count: Int = 0
    @Published private(set) var legacyRawAccelFrame50Count: Int = 0
    @Published private(set) var legacyRawAccelUnknownFrames: [Int: Int] = [:]
    @Published private(set) var legacyRawAccelSequence: String = "—"
    @Published private(set) var legacyRawAccelResponses: [String] = []
    @Published private(set) var imuSequenceResults: [String: IMUSequenceResult] = [:]
    @Published private(set) var imuSequenceCurrent: String = "—"

    private init() {}

    // MARK: - Mutators (call from the BLE delegate path — all on the main actor)

    func recordStandardHRNotification() { standardHRNotifications &+= 1 }

    func recordStandardHRSaved(_ hr: Bool, rr: Int) {
        if hr { standardHRSaved &+= 1 }
        standardRRSaved &+= rr
    }

    func recordStandardHRSkippedDedupe() { standardHRSkippedDedupe &+= 1 }

    // MARK: - Frame 40 mutators
    func recordFrame40DecodeAttempt() { frame40HRDecodeAttempts &+= 1 }
    func recordFrame40Decoded(hr: Int, rrCount: Int) {
        frame40HRDecoded &+= 1
        frame40RRDecoded &+= rrCount
        lastFrame40HRValue = hr
        lastFrame40RRCount = rrCount
        lastFrame40DecodeFailureReason = "—"
    }
    func recordFrame40DecodeFailed(_ reason: String) {
        frame40HRDecodeFailed &+= 1
        lastFrame40DecodeFailureReason = reason
    }
    func recordFrame40PersistResult(_ result: LiveHeartRatePersistResult) {
        if result.insertedHR { frame40HRSaved &+= 1 }
        if result.insertedRRCount > 0 { frame40RRSaved &+= result.insertedRRCount }
        if result.hrDeduped {
            frame40HRDeduped &+= 1
            lastFrame40DedupeReason = result.dedupeReason ?? "duplicate live HR"
        }
        if let error = result.errorDescription {
            frame40HRSaveFailed &+= 1
            lastFrame40SaveError = error
        } else if result.insertedHR || result.insertedRRCount > 0 {
            lastFrame40SaveError = "—"
        }
    }
    func recordLiveUIHeartRate(value: Int, saved: Bool?) {
        lastLiveUIHRValue = value
        lastLiveUIHRSaved = saved
    }

    func recordFrame(_ typeByte: UInt8) {
        switch typeByte {
        case 40: frame40Count &+= 1
        case 43: frame43Count &+= 1
        case 47: frame47Count &+= 1
        case 48: frame48Count &+= 1
        case 49: frame49Count &+= 1
        case 50: frame50Count &+= 1
        default: break
        }
    }

    func setMotionGravityStreamActive(_ active: Bool) {
        motionGravityStreamActive = active
    }

    func setDataNotifyActive(_ active: Bool) {
        dataNotifyActive = active
    }

    func recordMotionGravityCommand(_ command: WhoopCommand, payload: [UInt8]) {
        let rendered = payload.isEmpty ? "(empty)" : payload.map { String(format: "%02x", $0) }.joined(separator: " ")
        motionGravityAckSeen = false
        switch command {
        case .startRawData:
            startRawDataSentCount &+= 1
            lastStartRawDataPayload = rendered
        case .toggleIMUMode:
            toggleIMUModeSentCount &+= 1
            lastToggleIMUModePayload = rendered
        case .stopRawData:
            stopRawDataSentCount &+= 1
            lastStopRawDataPayload = rendered
        case .sendR10R11Realtime:
            lastSendR10R11RealtimePayload = rendered
            if payload.first == 0x01 {
                sendR10R11RealtimeOnSentCount &+= 1
            } else {
                sendR10R11RealtimeOffSentCount &+= 1
            }
        default:
            break
        }
    }

    func recordMotionGravityCommandResponse(_ frame: [UInt8]) {
        motionGravityAckSeen = true
        lastCommandResponseBytes = frame.map { String(format: "%02x", $0) }.joined(separator: " ")
    }

    func recordType43PacketLength(_ length: Int) {
        lastType43Length = length
        switch length {
        case 1917:
            type43Len1917Count &+= 1
        case 1921:
            type43Len1921Count &+= 1
        default:
            type43OtherLenCount &+= 1
        }
    }

    func recordType43IMUDecodeAttempt() {
        type43IMUDecodeAttempts &+= 1
    }

    func recordType43IMUDecoded() {
        type43IMUDecoded &+= 1
        lastType43DecodeError = "—"
    }

    func recordType43OpticalIgnored() {
        type43OpticalIgnored &+= 1
    }

    func recordType43UnknownVariant(length: Int) {
        type43UnknownVariantCount &+= 1
        lastType43Length = length
        lastType43DecodeError = "Unknown type-43 variant length \(length)"
    }

    func recordType43IMUDecodeFailed(_ reason: String) {
        type43IMUDecodeFailed &+= 1
        lastType43DecodeError = reason
    }

    func recordType43CollectorStats(imuFrames: Int,
                                    opticalFrames: Int,
                                    unknownFrames: Int,
                                    gravityRowsDerived: Int,
                                    gravityRowsSaved: Int) {
        _ = opticalFrames
        _ = unknownFrames
        type43IMUDecoded &+= imuFrames
        type43GravityRowsDerived &+= gravityRowsDerived
        type43GravityRowsSaved &+= gravityRowsSaved
        if imuFrames > 0 {
            lastType43DecodeError = "—"
        }
    }

    func recordBackfillRequested(payload: [UInt8]) {
        historySendCount &+= 1
        lastHistoryPayload = payload.isEmpty ? "(empty)" : payload.map { String(format: "%02x", $0) }.joined(separator: " ")
        historyAckSeen = false
        historyMetadataStartCount = 0
        historyMetadataEndCount = 0
        historyMetadataCompleteCount = 0
        historyState = .requested
        backfillLastReason = "requested"
    }

    func recordBackfillStart() {
        backfillStartCount &+= 1
        backfillInFlight = true
        backfillLastAtUnix = Date().timeIntervalSince1970
        historyState = .inFlight
    }

    func recordBackfillAckSeen() {
        historyAckSeen = true
        if historyState == .requested {
            historyState = .inFlight
        }
    }

    func recordDataRangeResponse(oldest: Int?, newest: Int?) {
        lastDataRangeResponse = "oldest=\(oldest.map(String.init) ?? "—") newest=\(newest.map(String.init) ?? "—")"
    }

    func recordHistoryMetadata(_ meta: HistoricalMeta) {
        switch meta {
        case .start:
            historyMetadataStartCount &+= 1
            historyState = .receivedMetadata
        case .end:
            historyMetadataEndCount &+= 1
            if historyState != .complete {
                historyState = .receivingData
            }
        case .complete:
            historyMetadataCompleteCount &+= 1
        case .other:
            break
        }
    }

    func recordFrame47Decoded(timestamp: Int?) {
        frame47DecodeSucceeded &+= 1
        lastType47Timestamp = timestamp
        lastFrame47DecodeError = "—"
        historyState = .receivingData
    }

    func recordFrame47DecodeFailed(_ reason: String) {
        frame47DecodeFailed &+= 1
        lastFrame47DecodeError = reason
    }

    func recordBackfillChunkPersisted(spo2: Int, skinTemp: Int, resp: Int, gravity: Int) {
        savedSpO2Rows &+= spo2
        savedSkinTempRows &+= skinTemp
        savedRespRows &+= resp
        savedGravityRows &+= gravity
    }

    func recordBackfillFailure(_ reason: String) {
        backfillErrorCount &+= 1
        backfillInFlight = false
        backfillLastReason = reason
        historyState = .failed
    }

    func recordBackfillComplete() {
        backfillCompleteCount &+= 1
        backfillInFlight = false
        backfillLastReason = "HISTORY_COMPLETE"
        historyState = hasServedHistory ? .complete : .noHistoryServed
    }

    func recordBackfillTimeout() {
        backfillTimeoutCount &+= 1
        backfillInFlight = false
        backfillLastReason = hasServedHistory ? "timeout" : "no history served"
        historyState = hasServedHistory ? .timedOut : .noHistoryServed
    }
    func recordBackfillError() { recordBackfillFailure("error") }
    func recordBackfillReason(_ reason: String) { backfillLastReason = reason }

    func setRawCaptureEnabled(_ enabled: Bool) { rawCaptureEnabled = enabled }

    func setRawLocalStats(batches: Int, bytes: Int, latestAt: Date?) {
        rawLocalBatches = batches
        rawLocalBytes = bytes
        rawLatestBatchAt = latestAt
    }

    func setLocalSnapshot(_ snap: LocalStoreSnapshot) {
        localSnapshot = snap
        localSnapshotAt = Date()
    }

    func recordUploadPayload(sent: [String: Int], pendingBefore: [String: Int]) {
        lastUploadPayloadCounts = sent
        lastUploadPendingCounts = pendingBefore
        lastUploadAt = Date()
    }

    // MARK: - IMU/Gravity Developer Diagnostics Mutators
    func setKeepIMUStreamOnWhileOpen(_ enabled: Bool) {
        keepIMUStreamOnWhileOpen = enabled
    }

    func recordGravityTestStarted(at: Date, shouldStopAt: Date) {
        gravityTestStartedAt = at
        gravityTestShouldStopAt = shouldStopAt
        gravityTestStopReason = "timer running"
    }

    func recordGravityTestStopped(reason: String) {
        gravityTestStopReason = reason
    }

    func recordCommandResponseDecoded(command: WhoopCommand, statusByte: UInt8, statusMeaning: String, accepted: Bool) {
        lastCommandResponseDecoded = command.label
        lastCommandResponseCommand = command.label
        lastCommandResponseStatus = String(format: "0x%02X", statusByte)
        lastCommandResponseMeaning = accepted ? "ACCEPTED: \(statusMeaning)" : "REJECTED: \(statusMeaning)"
    }

    func recordFrameHistogram(_ frame: [UInt8]) {
        guard frame.count > 4 else { return }
        let type = Int(frame[4])
        frameHistogram[type, default: 0] &+= 1

        last10FrameTypes.append((type: type, length: frame.count))
        if last10FrameTypes.count > 10 { last10FrameTypes.removeFirst() }
    }

    func recordUnknownFrame(type: Int, length: Int) {
        lastUnknownFrameType = type
        lastUnknownFrameLength = length
        frameHistogram[type, default: 0] &+= 1
    }

    func recordFrame51() { frame51Count &+= 1 }
    func recordFrame52() { frame52Count &+= 1 }

    func setBonded(_ bonded: Bool) { self.bonded = bonded }
    func setEncryptionState(_ state: String) { encryptionState = state }
    func setCmdCharDiscovered(_ discovered: Bool) { cmdCharDiscovered = discovered }
    func setDataCharNotifyEnabled(_ enabled: Bool) { dataCharNotifyEnabled = enabled }
    func setLastWriteType(_ type: String) { lastWriteType = type }
    func setLastWriteSuccess(_ success: Bool) { lastWriteSuccess = success }

    func recordHandshakeRawStopSent() { handshakeRawStopSent = true }
    func recordSendR10R11RealtimeStopSent() { sendR10R11RealtimeStopSent = true }
    func recordBackfillDisabledRawStream() { backfillDisabledRawStream = true }
    func recordGravityStreamRestartedAfterHandshake() { gravityStreamRestartedAfterHandshake = true }
    func recordGravityStreamRestartedAfterBackfill() { gravityStreamRestartedAfterBackfill = true }

    func recordLegacyRawAccelStart(sequence: String) {
        legacyRawAccelSequence = sequence
        legacyRawAccelFrame43Count = 0
        legacyRawAccelFrame40Count = 0
        legacyRawAccelFrame50Count = 0
        legacyRawAccelUnknownFrames = [:]
        legacyRawAccelResponses = []
    }

    func recordLegacyRawAccelFrame(type: Int) {
        switch type {
        case 43: legacyRawAccelFrame43Count &+= 1
        case 40: legacyRawAccelFrame40Count &+= 1
        case 50: legacyRawAccelFrame50Count &+= 1
        default: legacyRawAccelUnknownFrames[type, default: 0] &+= 1
        }
    }

    func recordLegacyRawAccelResponse(_ response: String) {
        legacyRawAccelResponses.append(response)
    }

    func recordIMUSequenceResult(_ sequence: String, result: IMUSequenceResult) {
        imuSequenceResults[sequence] = result
        imuSequenceCurrent = sequence
    }

    private var hasServedHistory: Bool {
        historyMetadataStartCount > 0 ||
        historyMetadataEndCount > 0 ||
        historyMetadataCompleteCount > 0 ||
        frame47DecodeSucceeded > 0
    }
}
