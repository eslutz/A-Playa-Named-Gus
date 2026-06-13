import GroupActivities
import SwiftUI

#if os(iOS) || os(visionOS)
    import _GroupActivities_UIKit
    import UIKit
#elseif os(macOS)
    import _GroupActivities_AppKit
    import AppKit
#endif

struct SharePlayPresentation: Identifiable {
    let id = UUID()
    let activity: GusPlaybackActivity
}

extension View {
    func sharePlaySharingPresentation(
        presentation: Binding<SharePlayPresentation?>,
        errorMessage: Binding<String?>
    ) -> some View {
        modifier(SharePlaySharingPresentationModifier(
            presentation: presentation,
            errorMessage: errorMessage
        ))
    }
}

private struct SharePlaySharingPresentationModifier: ViewModifier {
    @Binding var presentation: SharePlayPresentation?
    @Binding var errorMessage: String?

    func body(content: Content) -> some View {
        #if !os(tvOS)
            content
                .sheet(item: $presentation) { presentation in
                    SharePlaySharingController(activity: presentation.activity) { error in
                        if let error {
                            errorMessage = GusError(from: error).localizedDescription
                        }
                        self.presentation = nil
                    }
                }
                .alert(
                    "SharePlay Unavailable",
                    isPresented: Binding(
                        get: { errorMessage != nil },
                        set: { isPresented in
                            if !isPresented {
                                errorMessage = nil
                            }
                        }
                    )
                ) {
                    Button("OK", role: .cancel) {
                        errorMessage = nil
                    }
                } message: {
                    Text(errorMessage ?? "")
                }
        #else
            content
        #endif
    }
}

#if !os(tvOS)
    #if os(iOS) || os(visionOS)
        /// Native Apple SharePlay sharing sheet for starting a `GusPlaybackActivity`.
        struct SharePlaySharingController: UIViewControllerRepresentable {
            let activity: GusPlaybackActivity
            let onFinished: (Error?) -> Void

            func makeUIViewController(context: Context) -> UIViewController {
                do {
                    let controller = try GroupActivitySharingController(activity)
                    context.coordinator.observe(controller)
                    return controller
                } catch {
                    context.coordinator.finish(error)
                    return UIViewController()
                }
            }

            func updateUIViewController(_ controller: UIViewController, context: Context) {}

            func makeCoordinator() -> Coordinator {
                Coordinator(onFinished: onFinished)
            }

            @MainActor
            final class Coordinator {
                private let onFinished: (Error?) -> Void
                private var didFinish = false
                private var resultTask: Task<Void, Never>?

                init(onFinished: @escaping (Error?) -> Void) {
                    self.onFinished = onFinished
                }

                func observe(_ controller: GroupActivitySharingController) {
                    resultTask?.cancel()
                    resultTask = Task { @MainActor in
                        _ = await controller.result
                        finish(nil)
                    }
                }

                func finish(_ error: Error?) {
                    guard !didFinish else { return }
                    didFinish = true
                    onFinished(error)
                }

                deinit {
                    resultTask?.cancel()
                }
            }
        }

    #elseif os(macOS)
        /// Native Apple SharePlay sharing sheet for starting a `GusPlaybackActivity`.
        struct SharePlaySharingController: NSViewControllerRepresentable {
            let activity: GusPlaybackActivity
            let onFinished: (Error?) -> Void

            func makeNSViewController(context: Context) -> NSViewController {
                do {
                    let controller = try GroupActivitySharingController(activity)
                    context.coordinator.observe(controller)
                    return controller
                } catch {
                    context.coordinator.finish(error)
                    return NSViewController()
                }
            }

            func updateNSViewController(_ controller: NSViewController, context: Context) {}

            func makeCoordinator() -> Coordinator {
                Coordinator(onFinished: onFinished)
            }

            @MainActor
            final class Coordinator {
                private let onFinished: (Error?) -> Void
                private var didFinish = false
                private var resultTask: Task<Void, Never>?

                init(onFinished: @escaping (Error?) -> Void) {
                    self.onFinished = onFinished
                }

                func observe(_ controller: GroupActivitySharingController) {
                    resultTask?.cancel()
                    resultTask = Task { @MainActor in
                        _ = await controller.result
                        finish(nil)
                    }
                }

                func finish(_ error: Error?) {
                    guard !didFinish else { return }
                    didFinish = true
                    onFinished(error)
                }

                deinit {
                    resultTask?.cancel()
                }
            }
        }
    #endif
#endif
