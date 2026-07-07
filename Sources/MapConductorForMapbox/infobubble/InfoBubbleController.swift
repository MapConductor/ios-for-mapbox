import CoreGraphics
import CoreLocation
import MapboxMaps
import MapConductorCore
import SwiftUI
import UIKit

@MainActor
final class InfoBubbleController {
    private weak var mapView: MapView?
    private let container: UIView
    private let markerController: MapboxMarkerController

    private var infoBubblesById: [String: InfoBubble] = [:]
    private var infoBubbleHosts: [String: UIHostingController<AnyView>] = [:]
    private var infoBubbleDirectViews: [String: UIView] = [:]

    init(mapView: MapView?, container: UIView, markerController: MapboxMarkerController) {
        self.mapView = mapView
        self.container = container
        self.markerController = markerController
    }

    func syncInfoBubbles(_ bubbles: [InfoBubble]) {
        var newBubbles: [String: InfoBubble] = [:]
        for bubble in bubbles { newBubbles[bubble.marker.id] = bubble }
        infoBubblesById = newBubbles
        syncInfoBubbleViews()
    }

    private func syncInfoBubbleViews() {
        for (id, bubble) in infoBubblesById {
            if let uiView = bubble.uiViewContent {
                // UIKit / React Native path: use the UIView directly
                if infoBubbleDirectViews[id] !== uiView {
                    infoBubbleDirectViews[id]?.removeFromSuperview()
                    infoBubbleDirectViews[id] = uiView
                }
                uiView.isUserInteractionEnabled = true
                if uiView.superview == nil { container.addSubview(uiView) }
            } else if let anyView = bubble.swiftUIContent {
                // SwiftUI path: host via UIHostingController
                let host = infoBubbleHosts[id] ?? UIHostingController(rootView: anyView)
                host.rootView = anyView
                host.view.backgroundColor = .clear
                host.view.isUserInteractionEnabled = true
                if host.view.superview == nil { container.addSubview(host.view) }
                infoBubbleHosts[id] = host
            }
        }
        let activeIds = Set(infoBubblesById.keys)
        for id in Set(infoBubbleHosts.keys).subtracting(activeIds) {
            removeInfoBubbleView(for: id)
        }
        for id in Set(infoBubbleDirectViews.keys).subtracting(activeIds) {
            removeInfoBubbleView(for: id)
        }
    }

    func removeInfoBubbleView(for id: String) {
        if let host = infoBubbleHosts.removeValue(forKey: id) {
            host.view.removeFromSuperview()
        }
        if let view = infoBubbleDirectViews.removeValue(forKey: id) {
            view.removeFromSuperview()
        }
    }

    func updateAllLayouts() {
        guard mapView != nil else { return }
        for id in infoBubblesById.keys { updateInfoBubblePosition(for: id) }
    }

    func updateInfoBubblePosition(for id: String) {
        guard let mapView,
              let bubble = infoBubblesById[id] else { return }

        let markerState = bubble.marker
        let coord = CLLocationCoordinate2D(
            latitude: markerState.position.latitude,
            longitude: markerState.position.longitude
        )
        let point = mapView.mapboxMap.point(for: coord)

        let bubbleView: UIView
        let targetSize: CGSize
        if let host = infoBubbleHosts[id] {
            targetSize = host.sizeThatFits(in: CGSize(width: 260, height: 1000))
            host.view.bounds = CGRect(origin: .zero, size: targetSize)
            bubbleView = host.view
        } else if let directView = infoBubbleDirectViews[id] {
            directView.layoutIfNeeded()
            targetSize = directView.systemLayoutSizeFitting(
                CGSize(width: 260, height: UIView.layoutFittingCompressedSize.height)
            )
            directView.bounds = CGRect(origin: .zero, size: targetSize)
            bubbleView = directView
        } else {
            return
        }

        let tailOffset = bubble.tailOffset
        let x: CGFloat
        let y: CGFloat

        if bubble.useIconMetrics {
            let bitmapIcon = markerController.getIcon(for: markerState)
            let iconSize = bitmapIcon.size
            let iconAnchor = bitmapIcon.anchor
            let infoAnchor = bitmapIcon.infoAnchor

            x = point.x
                + (-tailOffset.x * targetSize.width)
                + ((0.5 - iconAnchor.x) * iconSize.width)
                + ((infoAnchor.x - 0.5) * iconSize.width)
            y = point.y
                + (-tailOffset.y * targetSize.height)
                + ((0.5 - iconAnchor.y) * iconSize.height)
                + ((infoAnchor.y - 0.5) * iconSize.height)
        } else {
            // No icon: tail points directly at the GeoPoint screen coordinate.
            x = point.x - tailOffset.x * targetSize.width
            y = point.y - tailOffset.y * targetSize.height
        }

        bubbleView.frame = CGRect(
            origin: alignToPixel(CGPoint(x: x, y: y), scale: UIScreen.main.scale),
            size: targetSize
        )
    }

    private func alignToPixel(_ point: CGPoint, scale: CGFloat) -> CGPoint {
        guard scale > 0 else { return point }
        return CGPoint(
            x: (point.x * scale).rounded() / scale,
            y: (point.y * scale).rounded() / scale
        )
    }

    func unbind() {
        infoBubbleHosts.values.forEach { $0.view.removeFromSuperview() }
        infoBubbleHosts.removeAll()
        infoBubbleDirectViews.values.forEach { $0.removeFromSuperview() }
        infoBubbleDirectViews.removeAll()
        infoBubblesById.removeAll()
    }
}
