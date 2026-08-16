import CoreLocation
import Foundation
import MapboxMaps
// FlyToZoomArc はドライバー実装点なので @_spi 越しに取る。
@_spi(MapConductorDriver) import MapConductorCore
import QuartzCore
import UIKit

final class MapboxViewController: MapViewControllerProtocol {
    let holder: AnyMapViewHolder
    let typedHolder: MapboxMapViewHolder
    let coroutine = CoroutineScope()

    /// この地図に紐づくオーバーレイコントローラの登録簿。
    /// 拡張モジュール（ヒートマップ、マーカークラスタリング等）がここに登録して
    /// カメラ変更を受け取る。`MapViewControllerProtocol` の要件。
    let overlayControllers = OverlayControllerRegistry()
    private weak var mapView: MapView?
    private var cameraAnimator: CameraAnimator?
    private(set) var lastLogicalTilt: Double?

    private var cameraMoveStartListener: OnCameraMoveHandler?
    private var cameraMoveListener: OnCameraMoveHandler?
    private var cameraMoveEndListener: OnCameraMoveHandler?
    private var mapClickListener: OnMapEventHandler?
    private var mapLongClickListener: OnMapEventHandler?
    private var mapInitializedListener: OnMapInitializedHandler?

    init(mapView: MapView) {
        self.mapView = mapView
        let typedHolder = MapboxMapViewHolder(mapView: mapView)
        self.typedHolder = typedHolder
        self.holder = AnyMapViewHolder(typedHolder)
    }

    func clearOverlays() async {}

    func setCameraMoveStartListener(listener: OnCameraMoveHandler?) { cameraMoveStartListener = listener }
    func setCameraMoveListener(listener: OnCameraMoveHandler?) { cameraMoveListener = listener }
    func setCameraMoveEndListener(listener: OnCameraMoveHandler?) { cameraMoveEndListener = listener }
    func setMapClickListener(listener: OnMapEventHandler?) { mapClickListener = listener }
    func setMapLongClickListener(listener: OnMapEventHandler?) { mapLongClickListener = listener }
    func setMapInitializedListener(listener: OnMapInitializedHandler?) { mapInitializedListener = listener }

    func moveCamera(position: MapCameraPosition) {
        guard let mapView else { return }
        lastLogicalTilt = position.tilt
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
        let from = mapView.mapboxMap.cameraState.toMapCameraPosition(logicalTiltHint: lastLogicalTilt)
        lastLogicalTilt = position.tilt
        cameraAnimator = CameraAnimator(
            mapView: mapView,
            from: from,
            to: position,
            duration: durationSeconds
        )
        cameraAnimator?.start()
    }

    func setCameraRestriction(_ restriction: CameraRestriction?) {
        guard let mapView = mapView else { return }
        // android-for-mapbox と同じく CameraBoundsOptions で範囲・ズームを一括指定する。
        // 統一ズーム（Google 準拠）を Mapbox ズームへ変換して適用。
        var bounds: CoordinateBounds?
        if let sw = restriction?.bounds?.southWest, let ne = restriction?.bounds?.northEast {
            bounds = CoordinateBounds(
                southwest: CLLocationCoordinate2D(latitude: sw.latitude, longitude: sw.longitude),
                northeast: CLLocationCoordinate2D(latitude: ne.latitude, longitude: ne.longitude)
            )
        }
        let options = CameraBoundsOptions(
            bounds: bounds,
            // CameraBoundsOptions は CGFloat? を取るので明示変換する。
            maxZoom: restriction?.maxZoom.map { CGFloat(MapboxZoomAltitudeConverter.googleZoomToMapboxZoom($0)) },
            minZoom: restriction?.minZoom.map { CGFloat(MapboxZoomAltitudeConverter.googleZoomToMapboxZoom($0)) }
        )
        try? mapView.mapboxMap.setCameraBounds(with: options)
    }

    func fitBounds(bounds: GeoRectBounds, padding: Int) {
        guard let mapView = mapView,
              let sw = bounds.southWest,
              let ne = bounds.northEast else { return }
        let coordinates = [
            CLLocationCoordinate2D(latitude: sw.latitude, longitude: sw.longitude),
            CLLocationCoordinate2D(latitude: ne.latitude, longitude: sw.longitude),
            CLLocationCoordinate2D(latitude: ne.latitude, longitude: ne.longitude),
            CLLocationCoordinate2D(latitude: sw.latitude, longitude: ne.longitude),
        ]
        let edgeInsets = UIEdgeInsets(top: CGFloat(padding), left: CGFloat(padding), bottom: CGFloat(padding), right: CGFloat(padding))
        let cameraOptions = mapView.mapboxMap.camera(for: coordinates, padding: edgeInsets, bearing: nil, pitch: nil)
        mapView.mapboxMap.setCamera(to: cameraOptions)
    }

    func notifyCameraMoveStart(_ camera: MapCameraPosition) {
        cameraMoveStartListener?(camera)
    }
    func notifyCameraMove(_ camera: MapCameraPosition) {
        cameraMoveListener?(camera)
    }
    func notifyCameraMoveEnd(_ camera: MapCameraPosition) {
        // 登録済みオーバーレイ（拡張モジュール含む）へ伝播する。
        overlayControllers.dispatchCameraChanged(camera)
        cameraMoveEndListener?(camera)
    }
    func notifyMapClick(_ point: GeoPoint) { mapClickListener?(point) }
    func notifyMapLongClick(_ point: GeoPoint) { mapLongClickListener?(point) }

    func notifyMapInitialized() {
        mapInitializedListener?(.MapCreated)
    }
}

// MARK: - Camera Animator

private final class CameraAnimator {
    private weak var mapView: MapView?
    private let from: MapCameraPosition
    private let to: MapCameraPosition
    private let duration: TimeInterval
    /// 中心とズームの補間。van Wijk（＝ android-for-mapbox が呼ぶ
    /// `map.flyTo(cameraOptions:animationOptions:)` と同じ式）。
    /// ``FlyToZoomArc`` の説明を読むこと。
    private let arc: FlyToZoomArc
    private var displayLink: CADisplayLink?
    private let startTime: CFTimeInterval

    init(
        mapView: MapView,
        from: MapCameraPosition,
        to: MapCameraPosition,
        duration: TimeInterval
    ) {
        self.mapView = mapView
        self.from = from
        self.to = to
        self.duration = max(duration, 0.01)
        self.startTime = CACurrentMediaTime()

        let bounds = mapView.bounds
        let viewport = max(Double(max(bounds.width, bounds.height)), 1.0)
        self.arc = FlyToZoomArc(from: from, to: to, viewportSizePixels: viewport)
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

        // 中心とズームは van Wijk が決める。**`t` で素朴に補間しないこと**
        // （中心は等速でもズームだけ弧を描く、という組み合わせは移動が破綻して見える）。
        let centerT = arc.centerFraction(at: t)
        let latitude = lerp(from.position.latitude, to.position.latitude, centerT)
        let longitude = lerp(from.position.longitude, to.position.longitude, centerT)
        let zoom = arc.zoom(at: t)
        // bearing / tilt は距離と無関係なので従来どおり時間で補間する。
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
    private func easeInOut(_ t: Double) -> Double {
        guard t > 0 && t < 1 else { return t }
        return t * t * (3 - 2 * t)
    }

    /// ジェスチャの ON/OFF を地図へ適用する。
    /// android-sdk の `applyUISettings(settings:)` と同じ位置づけ。
    /// 初回適用はビュー生成時（`makeUIView`）に行い、以降の変更がここを通る。
    func applyUISettings(_ settings: MapUISettings) {
        guard let mapView else { return }
        mapView.gestures.options.panEnabled = settings.scrollGesture
        mapView.gestures.options.pinchZoomEnabled = settings.zoomGesture
        mapView.gestures.options.doubleTapToZoomInEnabled = settings.zoomGesture
        mapView.gestures.options.doubleTouchToZoomOutEnabled = settings.zoomGesture
        mapView.gestures.options.quickZoomEnabled = settings.zoomGesture
        mapView.gestures.options.rotateEnabled = settings.rotateGesture
        mapView.gestures.options.pitchEnabled = settings.tiltGesture
    }

}
