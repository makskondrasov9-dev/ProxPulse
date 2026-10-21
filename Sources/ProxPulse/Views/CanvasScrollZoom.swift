import SwiftUI
import AppKit

/// Observe wheel events without placing a hit-test surface over draggable SwiftUI nodes.
struct CanvasScrollZoom: NSViewRepresentable {
    var zoom: @MainActor (CGFloat, CGPoint) -> Void
    final class Surface: NSView { override var isFlipped: Bool { true }; override func hitTest(_ point: NSPoint) -> NSView? { nil } }
    @MainActor final class Coordinator {
        weak var view: NSView?
        var monitor: Any?
        var zoom: @MainActor (CGFloat, CGPoint) -> Void
        init(zoom: @escaping @MainActor (CGFloat, CGPoint) -> Void) { self.zoom = zoom }
        func start(_ view: NSView) {
            self.view = view
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                let consumed = MainActor.assumeIsolated {
                    guard let self, let view = self.view, let window = view.window, event.window === window else { return false }
                    let location = view.convert(event.locationInWindow, from: nil)
                    guard view.bounds.contains(location), abs(event.scrollingDeltaY) > 0 else { return false }
                    let delta = event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 0.006 : 0.035)
                    self.zoom(min(0.3, max(-0.3, delta)), location)
                    return true
                }
                return consumed ? nil : event
            }
        }
        func stop() { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil }
    }
    func makeCoordinator() -> Coordinator { Coordinator(zoom: zoom) }
    func makeNSView(context: Context) -> Surface { let view = Surface(); context.coordinator.start(view); return view }
    func updateNSView(_ nsView: Surface, context: Context) { context.coordinator.zoom = zoom }
    static func dismantleNSView(_ nsView: Surface, coordinator: Coordinator) { coordinator.stop() }
}
