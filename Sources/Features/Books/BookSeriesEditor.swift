import SwiftUI

/// Reviews a fixed set of ebook metadata changes before sending any of them to Jellyfin.
struct BookSeriesEditor: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    private let scope: BookSeriesEditScope
    let members: [MediaItem]
    let seriesName: String?
    let onSave: () async -> Void

    @State private var name: String
    @State private var selected: Set<String>
    @State private var review: [Change]?
    @State private var saving = false
    @State private var report: Report?

    init(books: [MediaItem], members: [MediaItem], seriesName: String?, onSave: @escaping () async -> Void) {
        scope = BookSeriesEditScope(books.filter { $0.id != nil && ContentRatingGate.admitsStored($0) })
        self.members = members
        self.seriesName = seriesName
        self.onSave = onSave
        _name = State(initialValue: seriesName ?? "")
        _selected = State(initialValue: Set(members.compactMap(\.id)))
    }

    private struct Change: Identifiable {
        var id: String
        var title: String
        var from: String?
        var to: String?
    }

    private struct Report {
        var confirmed: [Change]
        var unconfirmed: Change?
        var remaining: [Change]
        var message: String
    }

    private var changes: [Change] {
        guard let name = name.trimmedNilIfEmpty else { return [] }
        let originalIDs = Set(members.compactMap(\.id))
        return scope.editableBooks.compactMap { book in
            guard let id = book.id, selected.contains(id) || originalIDs.contains(id) else { return nil }
            if originalIDs.contains(id), selected.contains(id), name == seriesName {
                return nil
            }
            let from = book.seriesName.flatMap { $0.isEmpty ? nil : $0 }
            let to = selected.contains(id) ? name : nil
            guard from != to else { return nil }
            return Change(id: id, title: book.displayTitle, from: from, to: to)
        }
    }

    private var targetsIDBackedSeries: Bool {
        guard let name = name.trimmedNilIfEmpty, !scope.allowsAssignment(to: name) else { return false }
        return changes.contains { $0.to != nil }
    }

    var body: some View {
        NavigationStack {
            List {
                if let report {
                    results(report)
                } else if let review {
                    Section {
                        ForEach(review) { change in
                            VStack(alignment: .leading) {
                                Text(change.title)
                                Text("\(change.from ?? String(localized: "No series")) → \(change.to ?? String(localized: "No series"))")
                                    .font(.callout).foregroundStyle(.secondary)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("BookSeries.review." + change.id)
                        }
                    } header: {
                        Text("Review Changes")
                    } footer: {
                        Text("Saving updates the series in your Jellyfin library. Embedded file tags stay as they are.")
                    }
                } else {
                    Section {
                        TextField("Name", text: $name)
                    } header: {
                        Text("Series Name")
                    } footer: {
                        if targetsIDBackedSeries {
                            Text("Jellyfin manages a series with this name by ID. Choose a different name.")
                        }
                    }
                    Section("Books") {
                        ForEach(scope.editableBooks, id: \.id) { book in
                            if let id = book.id {
                                Button {
                                    if selected.contains(id) {
                                        selected.remove(id)
                                    } else {
                                        selected.insert(id)
                                    }
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text(book.displayTitle)
                                            if let current = book.seriesName?.trimmedNilIfEmpty {
                                                Text(current).font(.caption).foregroundStyle(.secondary)
                                            }
                                        }
                                        Spacer()
                                        Image(systemName: selected.contains(id) ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(selected.contains(id) ? Color.accentColor : Color.secondary)
                                            .accessibilityHidden(true)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(selected.contains(id) ? .isSelected : [])
                                .accessibilityIdentifier("BookSeries.member." + id)
                            }
                        }
                    }
                }
            }
            .navigationTitle(seriesName == nil ? "New Series" : "Edit Series")
            .toolbar {
                if report != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { saving = true }
                            .disabled(saving)
                    }
                } else {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(review == nil ? "Cancel" : "Back") {
                            if review == nil {
                                dismiss()
                            } else {
                                review = nil
                            }
                        }
                        .disabled(saving)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        if saving {
                            ProgressView().accessibilityLabel("Saving")
                        } else if review != nil {
                            Button("Save") { saving = true }
                        } else {
                            Button("Review Changes") { review = changes }
                                .disabled(changes.isEmpty || targetsIDBackedSeries)
                        }
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 400, idealWidth: 520, minHeight: 360, idealHeight: 520)
        #endif
        .interactiveDismissDisabled(saving || report != nil)
        .task(id: saving) {
            guard saving else { return }
            if report != nil {
                await onSave()
                dismiss()
            } else if let review {
                await save(review)
            }
        }
    }

    @ViewBuilder private func results(_ report: Report) -> some View {
        Section {
            Text(report.message)
        } header: {
            Text("Series Update Stopped")
        } footer: {
            Text("Done refreshes the library so you can review its current series assignments.")
        }
        if !report.confirmed.isEmpty {
            Section("Confirmed by Jellyfin") {
                ForEach(report.confirmed) { Text($0.title).accessibilityIdentifier("BookSeries.confirmed." + $0.id) }
            }
        }
        if let unconfirmed = report.unconfirmed {
            Section("Needs Review") { Text(unconfirmed.title).accessibilityIdentifier("BookSeries.unconfirmed." + unconfirmed.id) }
        }
        if !report.remaining.isEmpty {
            Section("Not Attempted") {
                ForEach(report.remaining) { Text($0.title) }
            }
        }
    }

    private func save(_ changes: [Change]) async {
        var confirmed: [Change] = []
        var current: Change?
        defer { saving = false }
        do {
            guard session.isActive, try await session.mediaProvider.canEditBookSeries() else { throw GusError.forbidden }
            for change in changes {
                try Task.checkCancellation()
                guard session.isActive else { throw GusError.cancelled }
                current = change
                try await session.mediaProvider.setBookSeries(itemID: change.id, from: change.from, to: change.to)
                confirmed.append(change)
                current = nil
            }
            try Task.checkCancellation()
            guard session.isActive else { return }
            await onSave()
            dismiss()
        } catch {
            let failure = GusError(from: error)
            failure.handleIfUnauthorized(session: session)
            guard session.isActive, !Task.isCancelled else { return }
            report = Report(
                confirmed: confirmed,
                unconfirmed: current,
                remaining: Array(changes.dropFirst(confirmed.count + (current == nil ? 0 : 1))),
                message: failure.localizedDescription
            )
        }
    }
}
