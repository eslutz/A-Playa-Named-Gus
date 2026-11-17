import AVKit
import Foundation

/// Supplies Apple's chapter panel. HLS I-frame renditions remain in the server's
/// manifest for AVKit's own scrubber; Gus does not synthesize a JPEG timeline.
@MainActor
enum NativePlayerNavigation {
    static func install(on playerItem: AVPlayerItem, item: MediaItem, session: SessionStore) async {
        #if os(tvOS)
            let chapters = item.chapters.enumerated().filter { ($0.element.startPositionTicks ?? -1) >= 0 }
            guard !chapters.isEmpty, !Task.isCancelled, session.isActive else { return }
            let transport = session.artworkTransport.session
            let loader = ChapterArtworkLoader(isCurrent: { [weak session] in session?.isActive == true }) { request, maximumBytes in
                try await ChapterArtworkTransport.shared.load(request, maximumBytes: maximumBytes, session: transport)
            }
            let markers = chapters.map { index, chapter in
                let title = AVMutableMetadataItem()
                title.identifier = .commonIdentifierTitle
                title.value = (chapter.name ?? String(localized: "Chapter \(index + 1)")) as NSString
                title.extendedLanguageTag = "und"
                var metadata: [AVMetadataItem] = [title]
                if chapter.imageTag != nil, let url = session.mediaProvider.artworkURLs(for: item, request: .init(role: .chapter(index: index, tag: chapter.imageTag), maxWidth: 320)).first {
                    var request = URLRequest(url: url)
                    request.timeoutInterval = 2
                    if let token = session.client.accessToken {
                        request.setValue("MediaBrowser Token=\"\(token)\"", forHTTPHeaderField: "Authorization")
                    }
                    metadata.append(loader.metadataItem(for: request))
                }
                return AVTimedMetadataGroup(items: metadata, timeRange: CMTimeRange(
                    start: CMTime(seconds: PlaybackTime.seconds(fromTicks: chapter.startPositionTicks ?? 0), preferredTimescale: 600), duration: .zero
                ))
            }
            playerItem.navigationMarkerGroups = [AVNavigationMarkersGroup(title: nil, timedNavigationMarkers: markers)]
            // Keep this lifetime attached to the store's cancellation-owned task.
            // Merely installing markers never requests any artwork bytes.
            await loader.waitUntilCancelled()
        #endif
    }
}

/// AVFoundation invokes the value loader only when a consumer asks for artwork.
/// Pending work reserves bytes before starting, so concurrent requests cannot
/// exceed the per-player compressed-data budget or oversubscribe it transiently.
@MainActor
final class ChapterArtworkLoader {
    typealias Fetch = @Sendable (URLRequest, Int) async throws -> Data
    private struct Pending {
        let id = UUID()
        let request: URLRequest
        let response: NativeMetadataValueResponse
    }

    private struct Active {
        let task: Task<Void, Never>
        let response: NativeMetadataValueResponse
        let reservedBytes: Int
    }

    private let isCurrent: @MainActor @Sendable () -> Bool
    private let fetch: Fetch
    private var pending: [Pending] = []
    private var active: [UUID: Active] = [:]
    private var retirement: CheckedContinuation<Void, Never>?
    private var isActive = true
    private var acceptedRequestCount = 0
    private var usedBytes = 0
    private var reservedBytes = 0
    private(set) var startedRequestCount = 0
    private let maximumRequests = 24
    private let maximumTotalBytes = 4 * 1024 * 1024
    private let maximumImageBytes = 256 * 1024

    init(isCurrent: @escaping @MainActor @Sendable () -> Bool, fetch: @escaping Fetch) {
        self.isCurrent = isCurrent
        self.fetch = fetch
    }

    func metadataItem(for request: URLRequest) -> AVMetadataItem {
        let template = AVMutableMetadataItem()
        template.identifier = .commonIdentifierArtwork
        template.dataType = "com.apple.metadata.datatype.JPEG"
        return AVMetadataItem(propertiesOf: template) { [weak self] valueRequest in
            let response = NativeMetadataValueResponse(valueRequest)
            Task { @MainActor [weak self] in
                guard let self else { response.finish(.failure(CancellationError())); return }
                self.enqueue(request, response: response)
            }
        }
    }

    private func enqueue(_ request: URLRequest, response: NativeMetadataValueResponse) {
        guard isActive, isCurrent() else { response.finish(.failure(CancellationError())); return }
        guard acceptedRequestCount < maximumRequests else { response.finish(.failure(URLError(.dataLengthExceedsMaximum))); return }
        acceptedRequestCount += 1
        pending.append(Pending(request: request, response: response))
        startPendingRequests()
    }

    private func startPendingRequests() {
        guard isActive, isCurrent() else { invalidate(); return }
        while !pending.isEmpty {
            let available = maximumTotalBytes - usedBytes - reservedBytes
            guard available > 0 else {
                if active.isEmpty {
                    pending.forEach { $0.response.finish(.failure(URLError(.dataLengthExceedsMaximum))) }
                    pending.removeAll()
                }
                return
            }
            let next = pending.removeFirst()
            let reservation = min(maximumImageBytes, available)
            reservedBytes += reservation
            startedRequestCount += 1
            let fetch = fetch
            let task = Task { [weak self] in
                let result: Result<Data, Error>
                do {
                    let data = try await PlaybackDeadline.run(for: .seconds(2)) {
                        try await fetch(next.request, reservation)
                    }
                    guard data.count <= reservation else { throw URLError(.dataLengthExceedsMaximum) }
                    result = .success(data)
                } catch { result = .failure(error) }
                self?.complete(next.id, result: result)
            }
            active[next.id] = Active(task: task, response: next.response, reservedBytes: reservation)
        }
    }

    private func complete(_ id: UUID, result: Result<Data, Error>) {
        guard let request = active.removeValue(forKey: id) else { return }
        reservedBytes -= request.reservedBytes
        if isActive, isCurrent() {
            if case let .success(data) = result {
                usedBytes += data.count
            }
            request.response.finish(result)
            startPendingRequests()
        } else {
            request.response.finish(.failure(CancellationError()))
            invalidate()
        }
    }

    func waitUntilCancelled() async {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard isActive, !Task.isCancelled else { invalidate(); continuation.resume(); return }
                retirement = continuation
            }
        } onCancel: { Task { @MainActor in self.invalidate() } }
    }

    func invalidate() {
        guard isActive else { return }
        isActive = false
        pending.forEach { $0.response.finish(.failure(CancellationError())) }
        pending.removeAll()
        for request in active.values {
            request.task.cancel()
            request.response.finish(.failure(CancellationError()))
        }
        active.removeAll()
        reservedBytes = 0
        retirement?.resume()
        retirement = nil
    }
}

/// AVFoundation explicitly permits asynchronous responses from its arbitrary
/// callback queue. This bridge owns each native request and responds at most once.
private final class NativeMetadataValueResponse: @unchecked Sendable {
    private let lock = NSLock()
    private var request: AVMetadataItemValueRequest?
    init(_ request: AVMetadataItemValueRequest) {
        self.request = request
    }

    func finish(_ result: Result<Data, Error>) {
        let request = lock.withLock {
            defer { self.request = nil }
            return self.request
        }
        guard let request else { return }
        switch result {
        case let .success(data): request.respond(value: data as NSData)
        case let .failure(error): request.respond(error: error as NSError)
        }
    }
}

/// Byte accumulation has its own executor so optional images never monopolize UI work.
private actor ChapterArtworkTransport {
    static let shared = ChapterArtworkTransport()
    func load(_ request: URLRequest, maximumBytes: Int, session: URLSession) async throws -> Data {
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse, (200 ..< 300).contains(response.statusCode), response.mimeType == "image/jpeg" else { throw URLError(.badServerResponse) }
        if response.expectedContentLength > Int64(maximumBytes) {
            throw URLError(.dataLengthExceedsMaximum)
        }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < maximumBytes else { throw URLError(.dataLengthExceedsMaximum) }
            data.append(byte)
        }
        return data
    }
}
