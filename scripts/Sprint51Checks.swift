import Foundation
import CoreGraphics
import ProxPulseCore

func verifySprint51() {
    let nodes = [CGRect(x: -600, y: 40, width: 166, height: 190), CGRect(x: 780, y: -320, width: 294, height: 112), CGRect(x: 500, y: 800, width: 270, height: 112)]
    let bounds = TopologyCamera.bounds(nodes)
    precondition(nodes.allSatisfy { bounds.contains($0) })
    for viewport in [CGSize(width: 640, height: 420), CGSize(width: 1440, height: 900), CGSize(width: 2200, height: 1400)] {
        let fit = TopologyCamera.fit(bounds: bounds, viewport: viewport)
        for scale in [fit / 2, fit, fit * 3, 5] {
            for x: CGFloat in [-1_000_000, -800, 0, 900, 1_000_000] {
                for y: CGFloat in [-1_000_000, -600, 0, 1200, 1_000_000] {
                    let scale = TopologyCamera.visibleScale(scale, bounds: bounds, viewport: viewport)
                    let pan = TopologyCamera.clamp(CGSize(width: x, height: y), bounds: bounds, viewport: viewport, scale: scale)
                    let screen = TopologyCamera.screenBounds(bounds: bounds, viewport: viewport, scale: scale, pan: pan)
                    precondition(screen.minX >= 24 - 0.0001 && screen.maxX <= viewport.width - 24 + 0.0001)
                    precondition(screen.minY >= 24 - 0.0001 && screen.maxY <= viewport.height - 24 + 0.0001)
                    precondition(screen.intersects(CGRect(origin: .zero, size: viewport)))
                }
            }
        }
        let centered = TopologyCamera.screenBounds(bounds: bounds, viewport: viewport, scale: fit, pan: .zero)
        precondition(abs(centered.midX - viewport.width/2) < 0.0001 && abs(centered.midY - viewport.height/2) < 0.0001)
    }
    var archive = TopologyLayoutArchive()
    archive.save(["guest/lxc/105": .init(x: -500, y: 810), "host/server": .init(x: 120, y: 50)], in: "profile-A/node-A")
    archive.save(["guest/lxc/105": .init(x: 42, y: 88)], in: "profile-B/node-A")
    archive = TopologyLayoutArchive(data: archive.data)
    precondition(archive.positions(in: "profile-A/node-A")["guest/lxc/105"]?.x == -500)
    precondition(archive.positions(in: "profile-B/node-A")["guest/lxc/105"]?.x == 42)
    archive.reset("profile-A/node-A")
    precondition(archive.positions(in: "profile-A/node-A").isEmpty && !archive.positions(in: "profile-B/node-A").isEmpty)
    precondition(TopologyLayoutArchive(data: Data("invalid".utf8)).scopes.isEmpty)
    // Corner drags at different zoom levels and nonzero camera offsets must keep full cards inside.
    for viewport in [CGSize(width: 640, height: 420), CGSize(width: 1440, height: 900)] {
        for scale: CGFloat in [0.25, 0.75, 1] {
            for size in [CGSize(width: 166, height: 190), CGSize(width: 110, height: 70), CGSize(width: 294, height: 112), CGSize(width: 270, height: 112)] {
                for pan in [CGSize.zero, CGSize(width: -123, height: 95)] {
                    let center = CGPoint(x: -250, y: 850)
                    for x: CGFloat in [-1_000_000, 1_000_000] {
                        for y: CGFloat in [-1_000_000, 1_000_000] {
                            let point = TopologyCamera.nodePosition(CGPoint(x: x, y: y), size: size, viewport: viewport, center: center, pan: pan, scale: scale)
                            let screen = TopologyCamera.screenPoint(point, viewport: viewport, center: center, pan: pan, scale: scale)
                            let rect = CGRect(x: screen.x-size.width*scale/2, y: screen.y-size.height*scale/2, width: size.width*scale, height: size.height*scale)
                            precondition(rect.minX >= 23.9999 && rect.minY >= 23.9999 && rect.maxX <= viewport.width-23.9999 && rect.maxY <= viewport.height-23.9999)
                            let again = TopologyCamera.nodePosition(point, size: size, viewport: viewport, center: center, pan: pan, scale: scale)
                            precondition(abs(point.x-again.x) < 0.0001 && abs(point.y-again.y) < 0.0001)
                        }
                    }
                }
            }
        }
    }
    for pair: (Double?, Double?) in [(nil,nil),(0,0),(9.99,9.99),(-50,2),(.nan,.infinity)] {
        precondition(!TopologyTrafficBadge.isVisible(receive: pair.0, transmit: pair.1))
    }
    for pair: (Double?, Double?) in [(10,0),(0,10),(nil,100),(286,91)] {
        precondition(TopologyTrafficBadge.isVisible(receive: pair.0, transmit: pair.1))
    }
    for start in [CGPoint(x: -125, y: 900), CGPoint(x: 900, y: -300)] {
        for end in [CGPoint(x: 250, y: 20), CGPoint(x: -800, y: 450)] {
            let midpoint = TopologyTrafficBadge.curvePoint(start: start, end: end, t: 0.5)
            precondition(abs(midpoint.x-(start.x+end.x)/2) < 0.0001 && abs(midpoint.y-(start.y+end.y)/2) < 0.0001)
            let moved = TopologyTrafficBadge.curvePoint(start: start, end: CGPoint(x: end.x+84, y: end.y-42), t: 0.5)
            precondition(abs(moved.x-midpoint.x-42) < 0.0001 && abs(moved.y-midpoint.y+21) < 0.0001)
        }
    }
    print("PASS: 300 strict camera/zoom cases; 192 node/camera/zoom corner drags; full 24pt containment, persistence/reset, idle badge thresholds and exact moving Bezier midpoint")
}
