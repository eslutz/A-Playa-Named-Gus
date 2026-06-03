import AVKit
import SwiftUI

struct AirPlayRoutePicker: View {
    var body: some View {
        #if os(visionOS)
            EmptyView()
        #elseif os(macOS)
            MacAirPlayRoutePicker()
                .frame(width: 32, height: 32)
        #else
            UIKitAirPlayRoutePicker()
                .frame(width: 44, height: 44)
        #endif
    }
}

#if os(iOS) || os(tvOS)
    private struct UIKitAirPlayRoutePicker: UIViewRepresentable {
        func makeUIView(context: Context) -> AVRoutePickerView {
            let view = AVRoutePickerView()
            view.prioritizesVideoDevices = true
            return view
        }

        func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
    }
#endif

#if os(macOS)
    private struct MacAirPlayRoutePicker: NSViewRepresentable {
        func makeNSView(context: Context) -> AVRoutePickerView {
            AVRoutePickerView()
        }

        func updateNSView(_ nsView: AVRoutePickerView, context: Context) {}
    }
#endif
