import Cocoa
import SwiftUI

/// Snapshot-only adapter. Filtering, aggregation and formatting happen before presentation.
struct KeyboardHeatmapRepresentable: NSViewRepresentable {
    let keyCounts: [String: Int]

    final class Coordinator {
        var applyState = KeyboardHeatmapApplyState()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> HeatmapContainerView {
        HeatmapContainerView(frame: .zero)
    }

    func updateNSView(_ nsView: HeatmapContainerView, context: Context) {
        if context.coordinator.applyState.accept(keyCounts) {
            nsView.renderer.apply(keyCounts: keyCounts)
        }
    }

    /// Appearance invalidation belongs to this host, not the unchanged global controller.
    final class HeatmapContainerView: NSView {
        let renderer = KeyboardHeatmapView()

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            renderer.frame = bounds
            renderer.autoresizingMask = [.width, .height]
            renderer.wantsLayer = true
            addSubview(renderer)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            renderer.needsDisplay = true
        }
    }
}
