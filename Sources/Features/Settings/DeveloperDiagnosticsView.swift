import SwiftUI

/// User-initiated inspection and export, matching PumpSync's Developer diagnostics.
struct DeveloperDiagnosticsView: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var eventPreviewHeight: CGFloat = 224
    @State private var snapshot = ClientLogExport.snapshot()
    @State private var exportURL: URL?
    @State private var exportError: String?

    var body: some View {
        List {
            Section("Build") {
                LabeledContent("Version", value: "\(snapshot.appVersion) (\(snapshot.build))")
                LabeledContent("Platform", value: snapshot.platform)
            }
            Section {
                Button("Prepare Log Export", systemImage: "doc.badge.arrow.up") {
                    snapshot = .snapshot()
                    do {
                        exportURL = try snapshot.save()
                        exportError = nil
                    } catch {
                        exportURL = nil
                        exportError = "The log export could not be saved. Try again."
                    }
                }
                if let exportURL {
                    ClientLogExportActions(url: exportURL)
                }
                if let exportError {
                    Text(exportError).foregroundStyle(.red)
                }
            } header: {
                Text("Export")
            } footer: {
                Text("Includes the latest 200 app events and available performance summaries. Names, media titles, server addresses and sign-in details are excluded. Gus does not upload logs automatically. Apple TV storage may be purged by the system.")
            }
            TVClientLogTransferSection()
            WatchClientLogTransferSection()
            Section("App Events") {
                if snapshot.events.isEmpty {
                    Text("No app events recorded yet.").foregroundStyle(.secondary)
                } else {
                    if !typeSize.isAccessibilitySize {
                        if snapshot.events.count <= 4 {
                            eventRows
                        } else {
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 0) { eventRows }
                            }
                            .frame(height: eventPreviewHeight)
                        }
                    }
                    NavigationLink("View All Events") {
                        List { eventRows }.navigationTitle("App Events")
                    }
                    .accessibilityIdentifier("ClientLogs.allEvents")
                }
            }
            Section {
                if snapshot.performance.isEmpty {
                    Text("No performance reports yet.").foregroundStyle(.secondary)
                } else {
                    NavigationLink {
                        List {
                            ForEach(Array(snapshot.performance.sorted { $0.capturedAt > $1.capturedAt }.enumerated()), id: \.offset) { _, report in
                                NavigationLink {
                                    PerformanceReportDetail(report: report)
                                } label: {
                                    VStack(alignment: .leading, spacing: ContentSpacing.caption) {
                                        Text(report.kind.title)
                                        Text(report.capturedAt.formatted(date: .abbreviated, time: .standard))
                                            .font(.caption)
                                    }
                                }
                            }
                        }
                        .navigationTitle("Device Performance")
                    } label: {
                        Text("\(snapshot.performance.count) retained reports")
                    }
                }
            } header: {
                Text("Device Performance")
            } footer: {
                Text("Reports are delivered periodically by the operating system. tvOS does not provide MetricKit reports.")
            }
        }
        .navigationTitle("Client Logs")
        .toolbar {
            Button("Refresh", systemImage: "arrow.clockwise") { snapshot = .snapshot(); exportURL = nil }
        }
    }

    private var eventRows: some View {
        ForEach(Array(snapshot.events.reversed().enumerated()), id: \.offset) { _, event in
            NavigationLink {
                List {
                    LabeledContent("Event", value: event.name)
                    LabeledContent("Recorded", value: event.date.formatted(date: .abbreviated, time: .standard))
                    if !event.attributes.isEmpty {
                        Section("Attributes") {
                            ForEach(event.attributes.keys.sorted(), id: \.self) { key in
                                LabeledContent(key, value: event.attributes[key] ?? "")
                            }
                        }
                    }
                }
                .navigationTitle("Event Details")
            } label: {
                VStack(alignment: .leading, spacing: ContentSpacing.caption) {
                    Text(event.name).font(.headline)
                    Text(event.date.formatted(date: .abbreviated, time: .standard))
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .accessibilityIdentifier("ClientLogs.event." + event.name)
        }
    }
}

private extension DiagnosticSummary.Kind {
    var title: LocalizedStringKey {
        switch self {
        case .metrics: "Metrics"
        case .diagnostics: "Diagnostics"
        }
    }
}

private struct PerformanceReportDetail: View {
    let report: DiagnosticSummary

    var body: some View {
        List {
            LabeledContent("Recorded", value: report.capturedAt.formatted(date: .abbreviated, time: .standard))
            LabeledContent("Platform", value: report.platform)
            if let version = report.appVersion {
                LabeledContent("Version", value: version)
            }
            switch report.kind {
            case .diagnostics:
                LabeledContent("Crashes", value: report.crashCount.formatted())
                LabeledContent("Hangs", value: report.hangCount.formatted())
                LabeledContent("CPU Exceptions", value: report.cpuExceptionCount.formatted())
                LabeledContent("Disk Write Exceptions", value: report.diskWriteExceptionCount.formatted())
            case .metrics:
                metric("Average Time to First Draw (ms)", report.launchTimeToFirstDrawAverageMS)
                metric("Total Hang Time (s)", report.hangTimeTotalSeconds)
                metric("Peak Memory (MB)", report.peakMemoryMB)
                metric("CPU Time (s)", report.cpuTimeSeconds)
                metric("Disk Writes (MB)", report.cumulativeDiskWritesMB)
                metric("Network Transfer (MB)", report.cumulativeNetworkTransferMB)
            }
        }
        .navigationTitle(report.kind.title)
    }

    @ViewBuilder
    private func metric(_ title: LocalizedStringKey, _ value: Double?) -> some View {
        if let value {
            LabeledContent(title, value: value.formatted(.number.precision(.fractionLength(0 ... 2))))
        }
    }
}
