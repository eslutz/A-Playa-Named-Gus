import SwiftUI
import WidgetKit

@main
struct GusWidgets: WidgetBundle {
    var body: some Widget {
        GusNextUpWidget()
        #if !os(visionOS)
            GusSearchControl()
            GusDownloadsControl()
        #endif
        #if os(iOS)
            GusDownloadsLiveActivity()
        #endif
    }
}

private struct NextUpEntry: TimelineEntry {
    var date: Date
    var snapshot: GusWidgetSnapshot?
}

private struct NextUpProvider: TimelineProvider {
    func placeholder(in _: Context) -> NextUpEntry {
        NextUpEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (NextUpEntry) -> Void) {
        completion(NextUpEntry(date: .now, snapshot: context.isPreview ? nil : GusWidgetSnapshot.load(from: GusWidgetSnapshot.fileURL())))
    }

    func getTimeline(in _: Context, completion: @escaping @Sendable (Timeline<NextUpEntry>) -> Void) {
        let now = Date.now
        let snapshot = GusWidgetSnapshot.load(from: GusWidgetSnapshot.fileURL(), now: now)
        var entries = [NextUpEntry(date: now, snapshot: snapshot)]
        if let expires = snapshot?.expiresAt {
            entries.append(.init(date: expires))
        }
        completion(Timeline(entries: entries, policy: .never))
    }
}

private struct GusNextUpWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: GusWidgetSnapshot.kind, provider: NextUpProvider()) { entry in
            NextUpGlance(snapshot: entry.snapshot)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(URL(string: "gus://home"))
        }
        .configurationDisplayName("Next Up")
        .description("Open Next Up and see your progress.")
        #if os(watchOS)
            .supportedFamilies([.accessoryRectangular, .accessoryCircular])
        #elseif os(iOS)
            .supportedFamilies([.systemMedium, .accessoryRectangular, .accessoryCircular])
        #else
            .supportedFamilies([.systemMedium])
        #endif
    }
}

private struct NextUpGlance: View {
    let snapshot: GusWidgetSnapshot?
    @Environment(\.widgetFamily) private var family

    var body: some View {
        #if os(iOS) || os(watchOS)
            if family == .accessoryCircular {
                if let progress = snapshot?.progress {
                    Gauge(value: progress) { Image(systemName: "play.fill") }
                        .gaugeStyle(.accessoryCircular)
                        .accessibilityLabel("Next Up")
                        .privacySensitive()
                } else {
                    Label("Next Up", systemImage: "play.circle").labelStyle(.iconOnly)
                }
            } else {
                details
            }
        #else
            details
        #endif
    }

    private var details: some View {
        VStack(alignment: .leading) {
            Label("Next Up", systemImage: "play.rectangle")
                .font(.headline)
            if let title = snapshot?.visibleTitle(lockCapable: lockCapable) {
                Text(verbatim: title).lineLimit(2).privacySensitive()
            } else if let progress = snapshot?.progress {
                ProgressView(value: progress)
                    .accessibilityLabel("Playback progress")
                    .privacySensitive()
            } else {
                Text("Open in Gus").font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var lockCapable: Bool {
        #if os(watchOS) || os(iOS)
            true
        #else
            false
        #endif
    }
}

#if !os(visionOS)
    private struct GusSearchControl: ControlWidget {
        var body: some ControlWidgetConfiguration {
            StaticControlConfiguration(kind: "dev.ericslutz.gus.control.search") {
                ControlWidgetButton(action: GusWidgetNavigationIntent(target: .search)) {
                    Label("Search Library", systemImage: "magnifyingglass")
                }
            }
            .displayName("Search Library")
        }
    }

    private struct GusDownloadsControl: ControlWidget {
        var body: some ControlWidgetConfiguration {
            StaticControlConfiguration(kind: "dev.ericslutz.gus.control.downloaded") {
                ControlWidgetButton(action: GusWidgetNavigationIntent(target: .downloaded)) {
                    Label("Downloads", systemImage: "arrow.down.circle")
                }
            }
            .displayName("Downloads")
        }
    }
#endif
