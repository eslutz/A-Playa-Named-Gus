import SwiftUI

/// User-initiated inspection and export, matching PumpSync's Developer diagnostics.
struct DeveloperDiagnosticsView: View {
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
                }
                ForEach(Array(snapshot.events.reversed().enumerated()), id: \.offset) { _, event in
                    VStack(alignment: .leading) {
                        Text(event.name).font(.headline)
                        Text(event.date.formatted(date: .abbreviated, time: .standard)).font(.caption)
                        ForEach(event.attributes.keys.sorted(), id: \.self) { key in
                            Text("\(key): \(event.attributes[key] ?? "")").font(.caption)
                        }
                    }
                }
            }
            Section("Device Performance") {
                Text("\(snapshot.performance.count) retained reports")
                Text("Reports are delivered periodically by the operating system. tvOS does not provide MetricKit reports.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Client Logs")
        .toolbar {
            Button("Refresh", systemImage: "arrow.clockwise") { snapshot = .snapshot(); exportURL = nil }
        }
    }
}
