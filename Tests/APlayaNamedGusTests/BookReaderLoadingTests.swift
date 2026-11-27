#if os(iOS) && canImport(ReadiumShared)
    import Foundation
    @testable import Gus
    import os
    import ReadiumNavigator
    import ReadiumShared
    import Testing

    @MainActor
    @Suite("EPUB loading and resume")
    struct BookReaderLoadingTests {
        @Test("appearance is account-scoped and reset restores animated turns")
        func readingPreferences() throws {
            let suite = "GusReaderPreferences-\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let scope = AccountScope(serverID: "server", userID: "reader")
            let other = AccountScope(serverID: "server", userID: "other")
            var edited = EPUBReaderPreferences.load(scope: scope, defaults: defaults)
            #expect(edited.animatePageTurns)
            edited.animatePageTurns = false
            edited.appearance.fontSize = 1.4
            edited.appearance.lineHeight = 1.5
            #expect(edited.effectivePreferences.lineHeight == nil)
            edited.appearance.publisherStyles = false
            #expect(edited.effectivePreferences.lineHeight == 1.5)
            edited.save(scope: scope, defaults: defaults)
            #expect(EPUBReaderPreferences.load(scope: scope, defaults: defaults) == edited)
            #expect(EPUBReaderPreferences.load(scope: other, defaults: defaults) == EPUBReaderPreferences())
            EPUBReaderPreferences().save(scope: scope, defaults: defaults)
            #expect(EPUBReaderPreferences.load(scope: scope, defaults: defaults).animatePageTurns)
        }

        @Test("concurrent readers own separate publications and load chapters")
        func independentPublications() async throws {
            let url = try fixtureURL()
            let first = makeModel(url: url)
            let second = makeModel(url: url)
            async let firstOpen: Void = first.open()
            async let secondOpen: Void = second.open()
            _ = await(firstOpen, secondOpen)

            #expect(first.state == .loaded)
            #expect(second.state == .loaded)
            let firstPublication = try #require(first.publication)
            let secondPublication = try #require(second.publication)
            #expect(firstPublication !== secondPublication)
            #expect(first.tableOfContents.map(\.title) == ["First Chapter", "Last Chapter"])
            #expect(second.tableOfContents.map(\.title) == ["First Chapter", "Last Chapter"])
        }

        @Test("exact local resume takes precedence without querying the server")
        func exactLocalResume() async throws {
            let url = try fixtureURL()
            let scope = AccountScope(serverID: UUID().uuidString, userID: "reader-test")
            let item = MediaItem(id: "reader-fixture", name: "Reader fixture", type: .book)
            let initial = BookReaderModel(item: item, fileURL: url, provider: nil, accountScope: scope)
            await initial.open()
            let publication = try #require(initial.publication)
            let href = try #require(publication.readingOrder.last?.url())
            let saved = Locator(
                href: href, mediaType: .xhtml,
                locations: .init(progression: 0.75, totalProgression: 0.875)
            )
            try BookProgressStore.shared.save(locatorJSON: saved.jsonString(), forItemID: "reader-fixture", scope: scope)
            defer {
                BookProgressStore.shared.deleteLocators(scope: scope)
                BookProgressStore.shared.flush()
            }

            let provider = FakeMediaProviderSession(capabilities: .init())
            provider.storedBookProgress = 0.05
            let reopened = BookReaderModel(item: item, fileURL: url, provider: provider, accountScope: scope)
            await reopened.open()

            #expect(reopened.state == .loaded)
            let restored = try #require(reopened.initialLocation)
            #expect(restored.href.isEquivalentTo(saved.href))
            #expect(restored.locations.progression == 0.75)
            #expect(restored.locations.totalProgression == 0.875)
            #expect(provider.bookProgressCallCount == 0)
        }

        @Test("invalid local EPUB becomes a readable failure")
        func invalidPublication() async throws {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".epub")
            try Data("This is not an EPUB archive.".utf8).write(to: url)
            defer { try? FileManager.default.removeItem(at: url) }
            let model = makeModel(url: url)
            await model.open()

            guard case let .failed(message) = model.state else {
                Issue.record("Invalid EPUB did not fail cleanly")
                return
            }
            #expect(!message.isEmpty)
            #expect(model.publication == nil)
        }

        @Test("resource errors preserve last good location and coalesce reader notices")
        func resourceRecovery() async throws {
            let model = try makeModel(url: fixtureURL())
            await model.open()
            let publication = try #require(model.publication)
            let href = try #require(publication.readingOrder.last?.url())
            let location = Locator(href: href, mediaType: .xhtml, locations: .init(progression: 0.5, totalProgression: 0.75))
            model.saveLocation(location)
            model.resourceFailed(GusError.offline)
            let notice = try #require(model.resourceNotice)
            model.resourceFailed(GusError.timeout)
            #expect(model.state == .loaded)
            #expect(model.resourceNotice == notice)
            #expect(model.readerNotice == nil)
            #expect(model.actionOutcome == .failed(.offline))
            #expect(model.initialLocation?.href.isEquivalentTo(location.href) == true)
            model.dismissResourceNotice()
            #expect(model.resourceNotice == nil)
        }

        @Test("navigator construction failure is visible and retryable")
        func navigatorRecovery() async throws {
            let model = try makeModel(url: fixtureURL())
            await model.open()
            model.navigatorConstructionFailed()
            guard case .failed = model.state else { Issue.record("Construction failure remained blank"); return }
            await model.retry()
            #expect(model.state == .loaded)
        }

        @Test("declared missing and failing resources are observable without replacing bytes or reporting cancellation")
        nonisolated func resourceDecorator() async throws {
            let events = OSAllocatedUnfairLock(initialState: [BookResourceFailure]())
            let link = Link(href: "chapter.xhtml", mediaType: .xhtml)
            let missing = BookReportingContainer(upstream: EmptyContainer(), declared: [link]) { event in
                events.withLock { $0.append(event) }
            }
            let absent = try #require(missing[link.url()])
            let missingRead = await absent.read(range: 0 ..< 1)
            guard case .failure = missingRead else { Issue.record("Missing resource read succeeded"); return }
            #expect(events.withLock { $0.map(\.error) } == [.notFound])
            let undeclared = try #require(AnyURL(string: "undeclared.xhtml"))
            #expect(missing[undeclared] == nil)

            let original = DataResource(data: Data([10, 20, 30]))
            let existing = SingleResourceContainer(resource: original, at: link.url())
            let wrapped = BookReportingContainer(upstream: existing, declared: [link]) { event in
                events.withLock { $0.append(event) }
            }
            let fragment = try #require(AnyURL(string: "chapter.xhtml?rendition=1#part"))
            let resource = try #require(wrapped[fragment])
            let range = try await resource.read(range: 1 ..< 3).get()
            #expect(range == Data([20, 30]))
            #expect(wrapped.entries == existing.entries)
            let canceled = BookReportingResource(upstream: FailureResource(error: .cancelled), href: "cancel.xhtml") { event in
                events.withLock { $0.append(event) }
            }
            let cancelRead = await canceled.read()
            guard case .failure(.cancelled) = cancelRead else { Issue.record("Cancellation type changed"); return }
            #expect(events.withLock { $0.count } == 1)

            let partial = BookReportingResource(upstream: PartialReaderFailure(), href: "partial.xhtml") { event in
                events.withLock { $0.append(event) }
            }
            let consumed = OSAllocatedUnfairLock(initialState: Data())
            let failed = await partial.stream(range: 4 ..< 8) { chunk in consumed.withLock { $0.append(chunk) } }
            guard case .failure(.decoding) = failed else { Issue.record("Stream failure was swallowed or remapped"); return }
            #expect(consumed.withLock { $0 } == Data([4, 5]))
            #expect(events.withLock { $0.map(\.href) } == ["chapter.xhtml", "partial.xhtml"])
        }

        @Test("a real missing advertised EPUB chapter fails preflight and retains the current native page and saved locator")
        func missingChapterPreflight() async throws {
            let original = try fixtureURL()
            let damaged = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".epub")
            var archive = try Data(contentsOf: original)
            let old = Data("EPUB/last.xhtml".utf8)
            let renamed = Data("EPUB/lost.xhtml".utf8)
            var replacements = 0
            while let range = archive.range(of: old) {
                archive.replaceSubrange(range, with: renamed)
                replacements += 1
            }
            try #require(replacements == 2, "Rename only the ZIP local/central member names; preserve the advertised OPF/nav target")
            try archive.write(to: damaged)
            defer { try? FileManager.default.removeItem(at: damaged) }
            let scope = AccountScope(serverID: UUID().uuidString, userID: "missing-chapter")
            let item = MediaItem(id: "reader-fixture", name: "Reader fixture", type: .book)
            let model = BookReaderModel(item: item, fileURL: damaged, provider: nil, accountScope: scope)
            defer {
                model.close()
                BookProgressStore.shared.deleteLocators(scope: scope)
                BookProgressStore.shared.flush()
                OfflinePlaybackProgressStore.shared.deleteCheckpoints(scope: scope)
            }
            await model.open()
            #expect(model.state == .loaded)
            let publication = try #require(model.publication)
            let first = try #require(publication.readingOrder.first)
            let last = try #require(model.tableOfContents.last)
            // Resource reads are covered independently without transferring the
            // actor-owned publication. Exercise its generation-checked failure relay
            // before an actual missing-member chapter preflight for the same target.
            model.acceptResourceFailure(
                BookResourceFailure(href: BookReportingContainer.canonical(last.url()).string, error: GusError.notFound),
                generation: model.navigatorIdentity
            )
            try #require(model.resourceNotice != nil)
            model.dismissResourceNotice()
            #expect(model.resourceNotice == nil)
            let saved = Locator(href: first.url(), mediaType: .xhtml, locations: .init(progression: 0.25, totalProgression: 0.1))
            model.saveLocation(saved)
            let native = try EPUBNavigatorViewController(publication: publication, initialLocation: saved)
            model.navigator = native
            let identity = model.navigatorIdentity
            model.go(to: last)
            let deadline = ContinuousClock.now + .seconds(2)
            while model.resourceNotice == nil, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            #expect(model.resourceNotice != nil)
            #expect(model.readerNotice == nil) // A preload must not become a modal page claim.
            #expect(model.actionOutcome == .failed(.notFound))
            #expect(model.navigator === native)
            #expect(model.navigatorIdentity == identity)
            #expect(model.initialLocation?.href.isEquivalentTo(saved.href) == true)
            #expect(!native.isViewLoaded) // Preflight did not ask an unmounted native renderer to navigate.
            let itemID = try #require(item.id)
            let savedJSON = try #require(BookProgressStore.shared.locatorJSON(forItemID: itemID, scope: scope))
            let actual = try Locator(jsonString: savedJSON)
            #expect(actual.href.isEquivalentTo(saved.href))
        }

        @Test("resource retry replaces publication identity while stale and canceled callbacks cannot publish new notices")
        func retryOwnership() async throws {
            let scope = AccountScope(serverID: UUID().uuidString, userID: "reader-retry")
            let model = try BookReaderModel(item: MediaItem(id: "retry", type: .book), fileURL: fixtureURL(), provider: nil, accountScope: scope)
            defer {
                model.close()
                BookProgressStore.shared.deleteLocators(scope: scope)
                BookProgressStore.shared.flush()
                OfflinePlaybackProgressStore.shared.deleteCheckpoints(scope: scope)
            }
            await model.open()
            let old = try #require(model.publication)
            let oldGeneration = model.navigatorIdentity
            let href = try #require(old.readingOrder.first?.url())
            let saved = Locator(href: href, mediaType: .xhtml, locations: .init(progression: 0.5))
            model.saveLocation(saved)
            let native = try EPUBNavigatorViewController(publication: old, initialLocation: saved)
            model.navigator = native
            model.acceptResourceFailure(.init(href: "prefetch.xhtml", error: ReadError.cancelled), generation: oldGeneration)
            #expect(model.resourceNotice == nil)
            model.acceptResourceFailure(.init(href: "prefetch.xhtml", error: GusError.offline), generation: oldGeneration)
            let notice = try #require(model.resourceNotice)
            #expect(model.readerNotice == nil)
            model.dismissResourceNotice()
            model.acceptResourceFailure(.init(href: "prefetch.xhtml", error: GusError.offline), generation: oldGeneration)
            #expect(model.resourceNotice == nil) // Repeated offscreen failures stay coalesced after dismissal.
            model.resourceFailed(GusError.timeout, href: "different.xhtml")
            #expect(model.resourceNotice == notice)
            await model.retryResource()
            #expect(model.state == .loaded)
            #expect(model.publication !== old)
            #expect(model.navigatorIdentity != oldGeneration)
            #expect(model.initialLocation?.href.isEquivalentTo(saved.href) == true)
            #expect(!model.accepts(native, generation: oldGeneration))
            model.acceptResourceFailure(.init(href: "late.xhtml", error: GusError.notFound), generation: oldGeneration)
            #expect(model.resourceNotice == nil)
            let current = model.navigatorIdentity
            model.close()
            model.acceptResourceFailure(.init(href: "closed.xhtml", error: GusError.notFound), generation: current)
            #expect(model.resourceNotice == nil)
            await model.activate() // Same surviving view can become visible again.
            #expect(model.state == .loaded)
            #expect(model.navigatorIdentity != current)
            model.acceptResourceFailure(.init(href: "still-retired.xhtml", error: GusError.notFound), generation: current)
            #expect(model.resourceNotice == nil)
        }

        @Test("chapter deadline or close rejects late native completion without waiting for cooperative cancellation", arguments: [false, true])
        func chapterOwnership(close: Bool) async throws {
            let gate = ReaderNavigationGate()
            let model = try BookReaderModel(
                item: MediaItem(id: "held-reader", type: .book), fileURL: fixtureURL(), provider: nil,
                accountScope: AccountScope(serverID: UUID().uuidString, userID: "held-reader"),
                chapterTimeout: .seconds(1), navigate: { _, _ in await gate.run() }
            )
            defer { gate.finish(); model.close() }
            await model.open()
            let publication = try #require(model.publication)
            let target = try #require(model.tableOfContents.first)
            let native = try EPUBNavigatorViewController(publication: publication, initialLocation: nil)
            model.navigator = native
            model.go(to: target)
            let startDeadline = ContinuousClock.now + .seconds(2)
            while !gate.started, ContinuousClock.now < startDeadline {
                try await Task.sleep(for: .milliseconds(5))
            }
            try #require(gate.started, "Actual target preflight must finish before the native navigation seam starts")
            if close {
                model.close()
            } else {
                let timeoutDeadline = ContinuousClock.now + .seconds(2)
                while model.resourceNotice == nil, ContinuousClock.now < timeoutDeadline {
                    try await Task.sleep(for: .milliseconds(5))
                }
                #expect(model.actionOutcome == .failed(.timeout))
            }
            gate.finish() // Simulates a cancellation-ignoring SDK result arriving late.
            let finishDeadline = ContinuousClock.now + .seconds(2)
            while !gate.returned, ContinuousClock.now < finishDeadline {
                try await Task.sleep(for: .milliseconds(5))
            }
            #expect(gate.returned)
            #expect(close ? model.resourceNotice == nil : model.actionOutcome == .failed(.timeout))
        }

        @Test("canceled initial reader loading can activate again instead of remaining in loading")
        func canceledOpenReactivation() async throws {
            let model = try makeModel(url: fixtureURL())
            let opening = Task { await model.open() }
            opening.cancel()
            await opening.value
            #expect(model.state == .idle)
            #expect(model.actionOutcome == nil)
            await model.activate()
            #expect(model.state == .loaded)
            model.close()
        }

        private func makeModel(url: URL) -> BookReaderModel {
            BookReaderModel(
                item: MediaItem(id: "reader-fixture", name: "Reader fixture", type: .book),
                fileURL: url,
                provider: nil,
                accountScope: AccountScope(serverID: UUID().uuidString, userID: "reader-test")
            )
        }

        private func fixtureURL() throws -> URL {
            try #require(Bundle(for: ReaderFixtureBundle.self).url(forResource: "ReaderOwnership", withExtension: "epub"))
        }
    }

    @MainActor
    private final class ReaderNavigationGate {
        private var continuation: CheckedContinuation<Bool, Never>?
        private(set) var started = false
        private(set) var returned = false
        func run() async -> Bool {
            started = true
            let result = await withCheckedContinuation { continuation = $0 }
            returned = true
            return result
        }

        func finish() {
            continuation?.resume(returning: true)
            continuation = nil
        }
    }

    private final class PartialReaderFailure: Resource {
        let sourceURL: AbsoluteURL? = nil
        func estimatedLength() async -> ReadResult<UInt64?> {
            .success(8)
        }

        func properties() async -> ReadResult<ResourceProperties> {
            .success(.init())
        }

        func stream(range: Range<UInt64>?, consume: @escaping (Data) -> Void) async -> ReadResult<Void> {
            guard range == (4 ..< 8) else { return .failure(.unsupportedOperation(GusError.notFound)) }
            consume(Data([4, 5]))
            return .failure(.decoding(GusError.notFound))
        }
    }

    private final class ReaderFixtureBundle: NSObject {}
#endif
