#if canImport(ReadiumShared)
    import Foundation
    import ReadiumShared

    struct BookResourceFailure: Sendable {
        let href: String
        let error: GusError

        init(href: String, error: Error) {
            self.href = href
            switch error {
            case ReadError.cancelled: self.error = .cancelled
            case ReadError.access(.fileSystem(.fileNotFound(_))): self.error = .notFound
            default: self.error = GusError(from: error)
            }
        }
    }

    /// Observe container-backed reads through Readium's public builder extension.
    /// No content, preloading settings or native WebKit delegates are replaced.
    final class BookReportingContainer: Container {
        private let upstream: Container
        private let declared: Set<AnyURL>
        private let report: @Sendable (BookResourceFailure) -> Void

        init(upstream: Container, declared: [Link], report: @escaping @Sendable (BookResourceFailure) -> Void) {
            self.upstream = upstream
            self.declared = Set(declared.map { Self.canonical($0.url()) })
            self.report = report
        }

        // Keep access on the decorated Resource instead of a direct file shortcut.
        let sourceURL: AbsoluteURL? = nil
        var entries: Set<AnyURL> {
            upstream.entries
        }

        static func canonical(_ href: AnyURL) -> AnyURL {
            href.removingQuery().removingFragment().normalized
        }

        subscript(url: any URLConvertible) -> Resource? {
            let href = Self.canonical(url.anyURL)
            let resource: Resource
            if let existing = upstream[url] ?? upstream[href] {
                resource = existing
            } else if declared.contains(href) {
                resource = FailureResource(error: .access(.fileSystem(.fileNotFound(nil))))
            } else {
                return nil
            }
            return BookReportingResource(upstream: resource, href: href.string, report: report)
        }
    }

    /// Forward range/stream semantics and the original ReadResult unchanged.
    /// Failed preloads are reported as unavailable content, not a visible-page claim.
    final class BookReportingResource: Resource {
        private let upstream: Resource
        private let href: String
        private let report: @Sendable (BookResourceFailure) -> Void

        init(upstream: Resource, href: String, report: @escaping @Sendable (BookResourceFailure) -> Void) {
            self.upstream = upstream
            self.href = href
            self.report = report
        }

        let sourceURL: AbsoluteURL? = nil

        func estimatedLength() async -> ReadResult<UInt64?> {
            await observed(upstream.estimatedLength())
        }

        func properties() async -> ReadResult<ResourceProperties> {
            await observed(upstream.properties())
        }

        func stream(range: Range<UInt64>?, consume: @escaping (Data) -> Void) async -> ReadResult<Void> {
            await observed(upstream.stream(range: range, consume: consume))
        }

        private func observed<Value>(_ result: ReadResult<Value>) -> ReadResult<Value> {
            if case let .failure(error) = result, !Task.isCancelled {
                if case .cancelled = error {
                    return result
                }
                report(BookResourceFailure(href: href, error: error))
            }
            return result
        }
    }
#endif
