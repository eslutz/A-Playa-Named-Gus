#if os(iOS)
    import ActivityKit
    import SwiftUI
    import WidgetKit

    struct GusDownloadsLiveActivity: Widget {
        var body: some WidgetConfiguration {
            ActivityConfiguration(for: GusDownloadActivityAttributes.self) { context in
                VStack(alignment: .leading, spacing: 4) {
                    Label("Downloads", systemImage: "arrow.down.circle")
                    if !context.isStale, let title = context.state.title {
                        Text(verbatim: title).lineLimit(1).privacySensitive()
                    }
                    status(context)
                }
                .padding()
                .widgetURL(URL(string: "gus://downloaded"))
            } dynamicIsland: { context in
                DynamicIsland {
                    DynamicIslandExpandedRegion(.leading) { Label("Downloads", systemImage: "arrow.down.circle") }
                    DynamicIslandExpandedRegion(.bottom) { status(context) }
                } compactLeading: {
                    Image(systemName: "arrow.down.circle")
                } compactTrailing: {
                    if let percent = context.state.percent, !context.isStale {
                        Text(Double(percent) / 100, format: .percent)
                    } else {
                        Image(systemName: "ellipsis")
                    }
                } minimal: {
                    Image(systemName: "arrow.down.circle").accessibilityLabel("Downloads")
                }
                .widgetURL(URL(string: "gus://downloaded"))
            }
        }

        @ViewBuilder
        private func status(_ context: ActivityViewContext<GusDownloadActivityAttributes>) -> some View {
            if context.isStale {
                Text("Open Gus for the latest progress.")
            } else if let percent = context.state.percent {
                ProgressView(value: Double(percent), total: 100)
                    .accessibilityLabel("Download progress")
            } else {
                Text("Active downloads: \(context.state.activeCount)")
            }
        }
    }
#endif
