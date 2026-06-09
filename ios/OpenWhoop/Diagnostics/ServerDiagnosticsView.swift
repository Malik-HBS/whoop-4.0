import SwiftUI
import WhoopStore

struct ServerDiagnosticsView: View {
    @EnvironmentObject private var diagnostics: ServerDiagnostics
    @EnvironmentObject private var bleDiag: BLEDiagnostics
    @EnvironmentObject private var metrics: MetricsRepository
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: WH.Spacing.md) {
                    configCard
                    syncCard
                    developerCard
                }
                .padding(WH.Spacing.md)
            }
            .background(WH.Color.background.ignoresSafeArea())
            .navigationTitle("Check Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .task { diagnostics.refreshConfiguration() }
    }

    private var configCard: some View {
        card {
            VStack(alignment: .leading, spacing: WH.Spacing.sm) {
                header("Configuration")
                statusRow("WHOOP_BASE_URL",
                          value: diagnostics.config.isBaseURLConfigured ? "Configured" : "Missing",
                          accent: diagnostics.config.isBaseURLConfigured ? WH.Color.recoveryGreen : WH.Color.recoveryYellow)
                valueRow("Base URL", diagnostics.config.baseURL ?? "Not set")
                statusRow("WHOOP_API_KEY",
                          value: diagnostics.config.isAPIKeyConfigured ? "Configured" : "Missing",
                          accent: diagnostics.config.isAPIKeyConfigured ? WH.Color.recoveryGreen : WH.Color.recoveryYellow)
                valueRow("API Key", maskedKey(diagnostics.config.apiKey))

                if !diagnostics.isConfigured || !diagnostics.serverAvailable {
                    Text(diagnostics.localProcessingSummary)
                        .font(WH.Font.caption)
                        .foregroundStyle(WH.Color.recoveryYellow)
                        .padding(WH.Spacing.sm)
                        .background(WH.Color.recoveryYellow.opacity(0.10),
                                    in: RoundedRectangle(cornerRadius: WH.Radius.chip, style: .continuous))
                }
            }
        }
    }

    private var syncCard: some View {
        card {
            VStack(alignment: .leading, spacing: WH.Spacing.sm) {
                header("Sync Status")
                operationSection(
                    title: "Upload Status",
                    snapshot: diagnostics.upload,
                    fallbackDetail: "Decoded data upload to your server."
                )
                Divider().background(WH.Color.separator)
                operationSection(
                    title: "Last Server Pull Status",
                    snapshot: diagnostics.pull,
                    fallbackDetail: diagnostics.localProcessingSummary
                )
            }
        }
    }

    /// Developer-only pipeline diagnostics card: which links of the BLE → store → uploader →
    /// server chain are producing data right now. Each section is a one-glance "is this OK"
    /// check so an empty `/v1/summary` immediately points at collect / store / uploader / server.
    private var developerCard: some View {
        card {
            VStack(alignment: .leading, spacing: WH.Spacing.sm) {
                header("Developer Diagnostics")
                Text("Live snapshot of the BLE → store → uploader → server chain. Updated every 5 s.")
                    .font(WH.Font.caption)
                    .foregroundStyle(WH.Color.textSecondary)
                localMetricsProcessingSection
                Divider().background(WH.Color.separator)
                standardHRSection
                Divider().background(WH.Color.separator)
                frame40Section
                Divider().background(WH.Color.separator)
                bleFramesSection
                Divider().background(WH.Color.separator)
                type43GravitySection
                Divider().background(WH.Color.separator)
                backfillSection
                Divider().background(WH.Color.separator)
                localStoreSection
                Divider().background(WH.Color.separator)
                uploadPayloadSection
                Divider().background(WH.Color.separator)
                rawCaptureSection
            }
        }
    }

    // MARK: - Developer card sections

    private var localMetricsProcessingSection: some View {
        VStack(alignment: .leading, spacing: WH.Spacing.xs) {
            sectionHeader("Local metric engine")
            valueRow("Mode", diagnostics.localProcessingSummary)
            valueRow("Enabled", yesNo(metrics.localProcessingState.localProcessingEnabled))
            valueRow("Server optional", yesNo(metrics.localProcessingState.serverSyncOptional))
            valueRow("Last trigger", metrics.localProcessingState.lastTrigger?.rawValue ?? "—")
            valueRow("Last compute at", formatted(date: metrics.localProcessingState.lastComputeAt))
            valueRow("Last compute duration", metrics.localProcessingState.lastComputeDuration.map { String(format: "%.2fs", $0) } ?? "—")
            valueRow("Last compute result", metrics.localProcessingState.lastComputeResult ?? "—")
            valueRow("Daily computed", yesNo(metrics.localProcessingState.dailyComputed))
            valueRow("Recovery computed", yesNo(metrics.localProcessingState.recoveryComputed))
            valueRow("Strain computed", yesNo(metrics.localProcessingState.strainComputed))
            valueRow("Sleep computed", yesNo(metrics.localProcessingState.sleepComputed))
            valueRow("Workout computed", yesNo(metrics.localProcessingState.workoutComputed))
            valueRow("Reason", metrics.localProcessingState.reason ?? metrics.localProcessingState.lastComputeError ?? "—")
            Button {
                Task { await metrics.runLocalProcessingNow(trigger: .manual) }
            } label: {
                Text(metrics.isRefreshing ? "Running Local Metrics..." : "Run Local Metrics Now")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(WH.Color.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(WH.Color.surface2, in: RoundedRectangle(cornerRadius: WH.Radius.small, style: .continuous))
            }
            .buttonStyle(.plain)
            ForEach(metrics.localProcessingState.diagnostics.prefix(6), id: \.key) { entry in
                valueRow(entry.key, entry.value)
            }
        }
    }

    private var standardHRSection: some View {
        VStack(alignment: .leading, spacing: WH.Spacing.xs) {
            sectionHeader("Standard BLE HR (0x2A37)")
            valueRow("Notifications", "\(bleDiag.standardHRNotifications)")
            valueRow("HR samples saved", "\(bleDiag.standardHRSaved)")
            valueRow("R-R intervals saved", "\(bleDiag.standardRRSaved)")
            valueRow("HR deduped (same bpm / same second)", "\(bleDiag.standardHRSkippedDedupe)")
        }
    }

    private var frame40Section: some View {
        VStack(alignment: .leading, spacing: WH.Spacing.xs) {
            sectionHeader("Frame 40 / live UI HR")
            valueRow("Frame40 HR decode attempts", "\(bleDiag.frame40HRDecodeAttempts)")
            valueRow("Frame40 HR decoded", "\(bleDiag.frame40HRDecoded)")
            valueRow("Frame40 HR decode failed", "\(bleDiag.frame40HRDecodeFailed)")
            valueRow("Frame40 HR saved", "\(bleDiag.frame40HRSaved)")
            valueRow("Frame40 HR save failed", "\(bleDiag.frame40HRSaveFailed)")
            valueRow("Frame40 HR deduped", "\(bleDiag.frame40HRDeduped)")
            valueRow("Last frame40 HR value", bleDiag.lastFrame40HRValue.map(String.init) ?? "—")
            valueRow("Last frame40 RR count", "\(bleDiag.lastFrame40RRCount)")
            valueRow("Last frame40 dedupe reason", bleDiag.lastFrame40DedupeReason)
            valueRow("Last frame40 save error", bleDiag.lastFrame40SaveError)
            valueRow("Last frame40 decode failure", bleDiag.lastFrame40DecodeFailureReason)
            valueRow("Last live UI HR value", bleDiag.lastLiveUIHRValue.map(String.init) ?? "—")
            valueRow("Last live UI HR saved", yesNoUnknown(bleDiag.lastLiveUIHRSaved))
        }
    }

    private var bleFramesSection: some View {
        VStack(alignment: .leading, spacing: WH.Spacing.xs) {
            sectionHeader("Custom-service frame counters")
            valueRow("40 REALTIME_DATA", "\(bleDiag.frame40Count)")
            valueRow("43 REALTIME_RAW_DATA", "\(bleDiag.frame43Count)")
            valueRow("47 HISTORICAL_DATA", "\(bleDiag.frame47Count)")
            valueRow("48 EVENT", "\(bleDiag.frame48Count)")
            valueRow("49 METADATA (HISTORY_START/END)", "\(bleDiag.frame49Count)")
            valueRow("50 CONSOLE_LOGS", "\(bleDiag.frame50Count)")
            Text("Gravity/motion can be derived from type-43 IMU raw packets. Type-47 historical data remains a separate backfill source and gravity should not depend only on type-47.")
                .font(WH.Font.caption)
                .foregroundStyle(WH.Color.textSecondary)
        }
    }

    private var type43GravitySection: some View {
        VStack(alignment: .leading, spacing: WH.Spacing.xs) {
            sectionHeader("Type-43 IMU / Gravity")
            valueRow("Motion/gravity stream active", yesNo(bleDiag.motionGravityStreamActive))
            valueRow("Data char notify active", yesNo(bleDiag.dataNotifyActive))
            valueRow("START_RAW_DATA sent", "\(bleDiag.startRawDataSentCount)")
            valueRow("TOGGLE_IMU_MODE sent", "\(bleDiag.toggleIMUModeSentCount)")
            valueRow("STOP_RAW_DATA sent", "\(bleDiag.stopRawDataSentCount)")
            valueRow("Last START payload", bleDiag.lastStartRawDataPayload)
            valueRow("Last TOGGLE payload", bleDiag.lastToggleIMUModePayload)
            valueRow("Last STOP payload", bleDiag.lastStopRawDataPayload)
            valueRow("Command response seen", yesNo(bleDiag.motionGravityAckSeen))
            valueRow("Last cmd response bytes", bleDiag.lastCommandResponseBytes)
            valueRow("Type-43 IMU decode attempts", "\(bleDiag.type43IMUDecodeAttempts)")
            valueRow("Type-43 IMU decoded", "\(bleDiag.type43IMUDecoded)")
            valueRow("Type-43 IMU decode failed", "\(bleDiag.type43IMUDecodeFailed)")
            valueRow("Type-43 optical ignored", "\(bleDiag.type43OpticalIgnored)")
            valueRow("Type-43 unknown variants", "\(bleDiag.type43UnknownVariantCount)")
            valueRow("Type-43 len 1917 / 1921 / other", "\(bleDiag.type43Len1917Count) / \(bleDiag.type43Len1921Count) / \(bleDiag.type43OtherLenCount)")
            valueRow("Gravity rows derived / saved", "\(bleDiag.type43GravityRowsDerived) / \(bleDiag.type43GravityRowsSaved)")
            valueRow("Last type-43 length", bleDiag.lastType43Length.map(String.init) ?? "—")
            valueRow("Last type-43 error", bleDiag.lastType43DecodeError)
        }
    }

    private var backfillSection: some View {
        VStack(alignment: .leading, spacing: WH.Spacing.xs) {
            sectionHeader("Backfill (type-47 offload)")
            valueRow("History state", bleDiag.historyState.rawValue)
            valueRow("In flight", bleDiag.backfillInFlight ? "yes" : "no")
            valueRow("Last reason", bleDiag.backfillLastReason)
            valueRow("Starts / completes", "\(bleDiag.backfillStartCount) / \(bleDiag.backfillCompleteCount)")
            valueRow("Timeouts", "\(bleDiag.backfillTimeoutCount)")
            valueRow("Errors", "\(bleDiag.backfillErrorCount)")
            valueRow("Send count", "\(bleDiag.historySendCount)")
            valueRow("Last payload", bleDiag.lastHistoryPayload)
            valueRow("Ack seen", bleDiag.historyAckSeen ? "yes" : "no")
            valueRow("Data-range", bleDiag.lastDataRangeResponse)
            valueRow("Metadata start / end / complete", "\(bleDiag.historyMetadataStartCount) / \(bleDiag.historyMetadataEndCount) / \(bleDiag.historyMetadataCompleteCount)")
            valueRow("Type-47 decoded ok / failed", "\(bleDiag.frame47DecodeSucceeded) / \(bleDiag.frame47DecodeFailed)")
            valueRow("Last type-47 ts", bleDiag.lastType47Timestamp.map { formatted(unix: Double($0)) } ?? "—")
            valueRow("Last type-47 decode error", bleDiag.lastFrame47DecodeError)
            valueRow("Saved rows spO2 / skin / resp / gravity", "\(bleDiag.savedSpO2Rows) / \(bleDiag.savedSkinTempRows) / \(bleDiag.savedRespRows) / \(bleDiag.savedGravityRows)")
            if let last = bleDiag.backfillLastAtUnix {
                valueRow("Last attempt", formatted(unix: last))
            }
        }
    }

    private var localStoreSection: some View {
        VStack(alignment: .leading, spacing: WH.Spacing.xs) {
            sectionHeader("Local store (decoded, this device)")
            if let snap = bleDiag.localSnapshot {
                valueRow("Local HR row count", "\(snap.hr.count)")
                valueRow("Local RR row count", "\(snap.rr.count)")
                valueRow("Last local HR timestamp", snap.hr.latestTs.map { formatted(unix: Double($0)) } ?? "—")
                valueRow("Last local RR timestamp", snap.rr.latestTs.map { formatted(unix: Double($0)) } ?? "—")
                streamStatRow("HR",      snap.hr)
                streamStatRow("RR",      snap.rr)
                streamStatRow("Events",  snap.events)
                streamStatRow("Battery", snap.battery)
                streamStatRow("SpO2",    snap.spo2)
                streamStatRow("Skin T",  snap.skinTemp)
                streamStatRow("Resp",    snap.resp)
                streamStatRow("Gravity", snap.gravity)
                streamStatRow("Raw",     snap.raw)
                streamStatRow("Daily",   snap.dailyMetrics)
                streamStatRow("Sleep",   snap.sleepSessions)
                streamStatRow("Workout", snap.workouts)
                streamStatRow("Recovery", snap.recoveryMetrics)
                streamStatRow("Strain",  snap.strainMetrics)
            } else {
                Text("No snapshot yet — connect the strap and wait a few seconds.")
                    .font(WH.Font.caption)
                    .foregroundStyle(WH.Color.textSecondary)
            }
            if let at = bleDiag.localSnapshotAt {
                valueRow("Snapshot at", formatted(date: at))
            }
        }
    }

    private var uploadPayloadSection: some View {
        VStack(alignment: .leading, spacing: WH.Spacing.xs) {
            sectionHeader("Last uploader drain")
            if bleDiag.lastUploadAt == nil {
                Text("No drain yet — uploader runs every 30 s while connected.")
                    .font(WH.Font.caption)
                    .foregroundStyle(WH.Color.textSecondary)
            } else {
                valueRow("Drain at", formatted(date: bleDiag.lastUploadAt!))
                Text("Pending before drain (what we wanted to send):")
                    .font(WH.Font.caption)
                    .foregroundStyle(WH.Color.textSecondary)
                countsRow(bleDiag.lastUploadPendingCounts)
                Text("Sent (what actually reached the server):")
                    .font(WH.Font.caption)
                    .foregroundStyle(WH.Color.textSecondary)
                countsRow(bleDiag.lastUploadPayloadCounts)
            }
        }
    }

    private var rawCaptureSection: some View {
        VStack(alignment: .leading, spacing: WH.Spacing.xs) {
            sectionHeader("Raw capture (research toggle)")
            valueRow("Toggle enabled", bleDiag.rawCaptureEnabled ? "yes" : "no")
            valueRow("Local batches", "\(bleDiag.rawLocalBatches)")
            valueRow("Local bytes", "\(bleDiag.rawLocalBytes)")
            if let at = bleDiag.rawLatestBatchAt {
                valueRow("Latest batch at", formatted(date: at))
            }
        }
    }

    // MARK: - Shared row helpers

    private func streamStatRow(_ name: String, _ stat: StreamStat) -> some View {
        HStack(alignment: .top) {
            Text(name)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(WH.Color.textPrimary)
                .frame(width: 64, alignment: .leading)
            Text("\(stat.count) rows")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(stat.count > 0 ? WH.Color.recoveryGreen : WH.Color.textSecondary)
            Spacer()
            if let ts = stat.latestTs {
                Text("latest \(formatted(unix: Double(ts)))")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(WH.Color.textSecondary)
            } else {
                Text("—")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(WH.Color.textSecondary)
            }
        }
    }

    private func countsRow(_ counts: [String: Int]) -> some View {
        let keys = ["hr", "rr", "events", "battery", "spo2", "skin_temp", "resp", "gravity"]
        let present = keys.filter { (counts[$0] ?? 0) > 0 }
        return Group {
            if present.isEmpty {
                Text("(empty)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(WH.Color.textSecondary)
            } else {
                Text(present.map { "\($0)=\(counts[$0] ?? 0)" }.joined(separator: "  "))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(WH.Color.textPrimary)
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(WH.Font.cardTitle)
            .foregroundStyle(WH.Color.textSecondary)
            .tracking(1.0)
    }

    private func yesNoUnknown(_ value: Bool?) -> String {
        guard let value else { return "—" }
        return value ? "yes" : "no"
    }

    private func yesNo(_ value: Bool) -> String {
        value ? "yes" : "no"
    }

    // MARK: - Operation/sync helpers (unchanged)

    private func operationSection(title: String,
                                  snapshot: ServerDiagnostics.OperationSnapshot,
                                  fallbackDetail: String) -> some View {
        VStack(alignment: .leading, spacing: WH.Spacing.xs) {
            statusRow(title, value: snapshot.state.title, accent: color(for: snapshot.state))
            valueRow("Last time", formatted(date: snapshot.lastCompletedAt))
            valueRow("HTTP status", snapshot.httpStatus.map(String.init) ?? "—")
            valueRow("Detail", snapshot.detail ?? fallbackDetail)
        }
    }

    private func statusRow(_ label: String, value: String, accent: Color) -> some View {
        HStack(alignment: .top, spacing: WH.Spacing.sm) {
            Text(label)
                .font(WH.Font.cardTitle)
                .foregroundStyle(WH.Color.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(accent)
                .multilineTextAlignment(.trailing)
        }
    }

    private func valueRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: WH.Spacing.sm) {
            Text(label)
                .font(WH.Font.caption)
                .foregroundStyle(WH.Color.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(WH.Color.textPrimary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func header(_ title: String) -> some View {
        Text(title.uppercased())
            .font(WH.Font.cardTitle)
            .foregroundStyle(WH.Color.textSecondary)
            .tracking(1.5)
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(WH.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(WH.Color.surface,
                        in: RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))
    }

    private func color(for state: ServerDiagnostics.SyncState) -> Color {
        switch state {
        case .idle: return WH.Color.textSecondary
        case .notConfigured: return WH.Color.recoveryYellow
        case .inProgress: return WH.Color.strainBlue
        case .success: return WH.Color.recoveryGreen
        case .failed: return WH.Color.recoveryRed
        }
    }

    private func formatted(date: Date?) -> String {
        guard let date else { return "Never" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func formatted(unix: Double) -> String {
        let date = Date(timeIntervalSince1970: unix)
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    private func maskedKey(_ key: String?) -> String {
        guard let key, !key.isEmpty else { return "Not set" }
        if key.count <= 8 { return String(repeating: "•", count: key.count) }
        return "\(key.prefix(4))••••\(key.suffix(4))"
    }
}

#Preview("Server Diagnostics") {
    ServerDiagnosticsView()
        .environmentObject(ServerDiagnostics.shared)
        .environmentObject(BLEDiagnostics.shared)
        .environmentObject(MetricsRepository(deviceId: "preview"))
}
