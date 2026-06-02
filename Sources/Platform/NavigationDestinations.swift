import SwiftUI

extension View {
    /// Registers Gus's item/library navigation destinations once, at the root of a
    /// `NavigationStack`. Feature views push `LibraryRef`/`ItemRef` values via
    /// `NavigationLink(value:)`; centralizing the destinations here avoids duplicate
    /// `navigationDestination` declarations on the same stack.
    func gusItemDestinations() -> some View {
        navigationDestination(for: LibraryRef.self) { ref in
            LibraryGridView(library: ref.item)
        }
        .navigationDestination(for: ItemRef.self) { ref in
            ItemDetailView(item: ref.item)
        }
    }
}
