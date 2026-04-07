import CoreLocation
import Foundation
import MapboxMaps
import MapConductorCore
import QuartzCore

final class MapboxViewController: MapViewControllerProtocol {
    let holder: AnyMapViewHolder
    let coroutine = CoroutineScope()
    private weak var mapView: MapView?
    private var cameraAnimator: CameraAnimator?

    private var cameraMoveStartListener: OnCameraMoveHandler?
    private var cameraMoveListener: OnCameraMoveHandler?
    private var cameraMoveEndListener: OnCameraMoveHandler?
    private var mapClickListener: OnMapEventHandler?
    private var mapLongClickListener: OnMapEventHandler?

    init(mapView: MapView) {
        self.mapView = mapView
        self.holder = AnyMapViewHolder(MapboxViewHolder(mapView: mapView))
    }

    func clearOverlays() async {}

    func setCameraMoveStartListener(listener: OnCameraMoveHandler?) { cameraMoveStartListener = listener }
    func setCameraMoveListener(listener: OnCameraMoveHandler?) { cameraMoveListener = listener }
    func setCameraMoveEndListener(listener: OnCameraMoveHandler?) { cameraMoveEndListener = listener }
    func setMapClickListener(listener: OnMapEventHandler?) { mapClickListener = listener }
    func setMapLongClickListener(listener: OnMapEventHandler?) { mapLongClickListener = listener }

    func moveCamera(position: MapCameraPosition) {
        guard let mapView else { return }
        mapView.mapboxMap.setCamera(to: position.toMapboxCameraOptions())
    }

    func animateCamera(position: MapCameraPosition, duration: Long) {
        guard let mapView else { return }
        let durationSeconds = max(0.0, Double(duration) / 1000.0)
        guard durationSeconds > 0 else {
            moveCamera(position: position)
            return
        }
        cameraAnimator?.stop()
        let from = mapView.mapboxMap.cameraState.toMapCameraPosition()
        cameraAnimator = CameraAnimator(
            mapView: mapView,
            from: from,
            to: position,
            duration: durationSeconds
        )
        cameraAnimator?.start()
    }

    func notifyCameraMoveStart(_ camera: MapCameraPosition) {
        cameraMoveStartListener?(camera)
    }
    func notifyCameraMove(_ camera: MapCameraPosition) {
        cameraMoveListener?(camera)
    }
    func notifyCameraMoveEnd(_ camera: MapCameraPosition) {
        cameraMoveEndListener?(camera)
    }
    func notifyMapClick(_ point: GeoPoint) { mapClickListener?(point) }
}

// MARK: - Camera Animator

private final class CameraAnimator {
    private weak var mapView: MapView?
    private let from: MapCameraPosition
    private let to: MapCameraPosition
    private let duration: TimeInterval
    private let zoomArcAmplitude: Double
    private var displayLink: CADisplayLink?
    private let startTime: CFTimeInterval

    init(
        mapView: MapView,
        from: MapCameraPosition,
        to: MapCameraPosition,
        duration: TimeInterval,
        zoomArcAmplitude: Double = 2.5
    ) {
        self.mapView = mapView
        self.from = from
        self.to = to
        self.duration = max(duration, 0.01)
        self.zoomArcAmplitude = zoomArcAmplitude
        self.startTime = CACurrentMediaTime()
    }

    func start() {
        let displayLink = CADisplayLink(target: self, selector: #selector(step(_:)))
        self.displayLink = displayLink
        displayLink.add(to: .main, forMode: .common)
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func step(_ displayLink: CADisplayLink) {
        guard let mapView else { stop(); return }
        let elapsed = CACurrentMediaTime() - startTime
        let linear = min(1.0, elapsed / duration)
        let t = easeInOut(linear)

        let latitude = lerp(from.position.latitude, to.position.latitude, t)
        let longitude = lerp(from.position.longitude, to.position.longitude, t)
        let zoom = lerp(from.zoom, to.zoom, t) + zoomArc(t)
        let bearing = lerpAngle(from.bearing, to.bearing, t)
        let tilt = lerp(from.tilt, to.tilt, t)

        let pos = MapCameraPosition(
            position: GeoPoint(latitude: latitude, longitude: longitude, altitude: 0),
            zoom: zoom,
            bearing: bearing,
            tilt: tilt
        )
        mapView.mapboxMap.setCamera(to: pos.toMapboxCameraOptions())
        if t >= 1.0 { stop() }
    }

    private func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
    private func lerpAngle(_ a: Double, _ b: Double, _ t: Double) -> Double {
        let delta = ((b - a + 540).truncatingRemainder(dividingBy: 360)) - 180
        return a + delta * t
    }
    private func zoomArc(_ t: Double) -> Double {
        guard zoomArcAmplitude > 0 else { return 0 }
        return -zoomArcAmplitude * sin(.pi * t)
    }
    private func easeInOut(_ t: Double) -> Double {
        guard t > 0 && t < 1 else { return t }
        return t * t * (3 - 2 * t)
    }
}
