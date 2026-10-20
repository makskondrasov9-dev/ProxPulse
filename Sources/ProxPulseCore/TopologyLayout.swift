import Foundation
import CoreGraphics

public struct CanvasPosition: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
    public var point: CGPoint { CGPoint(x: x, y: y) }
}

public struct TopologyLayoutArchive: Codable, Sendable {
    public var scopes: [String: [String: CanvasPosition]] = [:]
    public init(data: Data = Data()) {
        self = (try? JSONDecoder().decode(Self.self, from: data)) ?? Self.empty
    }
    private static var empty: Self { var value = Self(internal: ()); value.scopes = [:]; return value }
    private init(internal: Void) {}
    public func positions(in scope: String) -> [String: CanvasPosition] {
        (scopes[scope] ?? [:]).filter { $0.value.x.isFinite && $0.value.y.isFinite }
    }
    public mutating func save(_ positions: [String: CanvasPosition], in scope: String) {
        scopes[scope] = positions.filter { $0.value.x.isFinite && $0.value.y.isFinite }
    }
    public mutating func reset(_ scope: String) { scopes.removeValue(forKey: scope) }
    public var data: Data { (try? JSONEncoder().encode(self)) ?? Data() }
}

/// Camera coordinates are relative to the center of the actual node bounding box.
public enum TopologyCamera {
    public static func bounds(_ rects: [CGRect]) -> CGRect {
        rects.reduce(CGRect.null) { $0.union($1) }.standardized
    }
    public static func fit(bounds: CGRect, viewport: CGSize, padding: CGFloat = 72) -> CGFloat {
        guard !bounds.isNull, bounds.width > 0, bounds.height > 0 else { return 1 }
        return max(0.001, min(max(1, viewport.width - 2*padding)/bounds.width, max(1, viewport.height - 2*padding)/bounds.height))
    }
    public static func clamp(_ proposed: CGSize, bounds: CGRect, viewport: CGSize, scale: CGFloat, padding: CGFloat = 24) -> CGSize {
        func axis(_ value: CGFloat, span: CGFloat, viewport: CGFloat) -> CGFloat {
            let inset = min(padding, max(0, viewport/2 - 1))
            let extent = span * max(0.001, scale)
            let limit = max(0, viewport - 2*inset - extent) / 2
            return min(limit, max(-limit, value))
        }
        guard !bounds.isNull else { return .zero }
        return CGSize(width: axis(proposed.width, span: bounds.width, viewport: viewport.width), height: axis(proposed.height, span: bounds.height, viewport: viewport.height))
    }
    /// Keep all cards visible: magnification cannot exceed the graph's available viewport.
    public static func visibleScale(_ requested: CGFloat, bounds: CGRect, viewport: CGSize) -> CGFloat {
        min(max(0.001, requested), fit(bounds: bounds, viewport: viewport, padding: 24))
    }
    public static func screenPoint(_ world: CGPoint, viewport: CGSize, center: CGPoint, pan: CGSize, scale: CGFloat) -> CGPoint {
        CGPoint(x: viewport.width/2 + pan.width + (world.x-center.x)*scale,
                y: viewport.height/2 + pan.height + (world.y-center.y)*scale)
    }
    public static func nodePosition(_ proposed: CGPoint, size: CGSize, viewport: CGSize, center: CGPoint, pan: CGSize, scale: CGFloat, margin: CGFloat = 24) -> CGPoint {
        guard viewport.width > 0, viewport.height > 0, scale > 0 else { return proposed }
        let screen = screenPoint(proposed, viewport: viewport, center: center, pan: pan, scale: scale)
        func axis(_ value: CGFloat, extent: CGFloat, available: CGFloat) -> CGFloat {
            let low = margin + extent * scale / 2, high = available - margin - extent * scale / 2
            return high >= low ? min(high, max(low, value)) : available / 2
        }
        let x = axis(screen.x, extent: size.width, available: viewport.width)
        let y = axis(screen.y, extent: size.height, available: viewport.height)
        return CGPoint(x: center.x + (x - viewport.width/2 - pan.width)/scale,
                       y: center.y + (y - viewport.height/2 - pan.height)/scale)
    }
    public static func screenBounds(bounds: CGRect, viewport: CGSize, scale: CGFloat, pan: CGSize) -> CGRect {
        CGRect(x: viewport.width/2 + pan.width - bounds.width*scale/2, y: viewport.height/2 + pan.height - bounds.height*scale/2, width: bounds.width*scale, height: bounds.height*scale)
    }
}

public enum TopologyTrafficBadge {
    public static func isVisible(receive: Double?, transmit: Double?) -> Bool {
        [receive, transmit].contains { rate in rate.map { $0.isFinite && $0 >= 10 } ?? false }
    }
    public static func curvePoint(start: CGPoint, end: CGPoint, t: CGFloat) -> CGPoint {
        let middle = (start.x + end.x) / 2, u = 1 - t
        return CGPoint(x: u*u*u*start.x + 3*u*u*t*middle + 3*u*t*t*middle + t*t*t*end.x,
                       y: u*u*u*start.y + 3*u*u*t*start.y + 3*u*t*t*end.y + t*t*t*end.y)
    }
}
