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
    /// 最後に指定されたパディング。`CameraOptions.padding` には当てず、カメラの中心をずらして
    /// 再現する（``CameraPaddingEmulation``）。読み戻しでは逆にずらす。
    ///
    /// ネイティブのパディングは視野を上へ広げる。tilt があると上のパディングが大きいほど
    /// 画面の上端が地平線の向こうまで届き、タイルを地平線まで読み込んで固まる。中心を
    /// ずらせば視野はパディングが無いときと同じになる（Google / HERE と同じ方式）。
    private(set) var lastPaddings: MapPaddingsProtocol?

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

    /// ``clearOverlays()`` の中身。オーバーレイのコントローラはホストが持っているので、
    /// ホストが生成時に設定する（android-sdk と同じく、各コントローラの `clear()` を呼ぶ）。
    var clearOverlaysHandler: (@MainActor () async -> Void)?

    func clearOverlays() async {
        await clearOverlaysHandler?()
    }

    func setCameraMoveStartListener(listener: OnCameraMoveHandler?) { cameraMoveStartListener = listener }
    func setCameraMoveListener(listener: OnCameraMoveHandler?) { cameraMoveListener = listener }
    func setCameraMoveEndListener(listener: OnCameraMoveHandler?) { cameraMoveEndListener = listener }
    func setMapClickListener(listener: OnMapEventHandler?) { mapClickListener = listener }
    func setMapLongClickListener(listener: OnMapEventHandler?) { mapLongClickListener = listener }
    func setMapInitializedListener(listener: OnMapInitializedHandler?) { mapInitializedListener = listener }

    func moveCamera(position: MapCameraPosition) {
        guard let mapView else { return }
        lastLogicalTilt = position.tilt
        if let paddings = position.paddings { lastPaddings = paddings }
        let requested = position.copy(paddings: lastPaddings ?? MapPaddings.Zeros)
        mapView.mapboxMap.setCamera(to: paddingApplied(requested, to: mapView).toMapboxCameraOptions())
        scheduleCorrection(requested)
    }

    func animateCamera(position: MapCameraPosition, duration: Long) {
        guard let mapView else { return }
        let durationSeconds = max(0.0, Double(duration) / 1000.0)
        guard durationSeconds > 0 else {
            moveCamera(position: position)
            return
        }
        cameraAnimator?.stop()
        // 補間は「地図に渡す中心」の空間で行う（from は地図の生の中心、to はずらした中心）。
        let from = mapView.mapboxMap.cameraState.toMapCameraPosition(logicalTiltHint: lastLogicalTilt)
        lastLogicalTilt = position.tilt
        if let paddings = position.paddings { lastPaddings = paddings }
        let requested = position.copy(paddings: lastPaddings ?? MapPaddings.Zeros)
        cameraAnimator = CameraAnimator(
            mapView: mapView,
            from: from,
            to: paddingApplied(requested, to: mapView),
            duration: durationSeconds,
            completion: { [weak self] in self?.scheduleCorrection(requested) }
        )
        cameraAnimator?.start()
    }

    /// 地図に渡すカメラ。パディングの分だけ中心をずらし、ネイティブのパディングは 0。
    private func paddingApplied(_ requested: MapCameraPosition, to mapView: MapView) -> MapCameraPosition {
        CameraPaddingEmulation.applied(
            to: requested,
            fov: mapboxVerticalFieldOfView,
            viewportSize: mapView.bounds.size
        ).copy(paddings: MapPaddings.Zeros)
    }

    /// 補正の世代。新しい移動が始まったら、前の移動の補正は捨てる。
    private var correctionGeneration = 0

    /// 補正は地図がカメラを描き終えてから測る（移動の直後は投影がまだ古い）。
    private func scheduleCorrection(_ requested: MapCameraPosition) {
        correctionGeneration += 1
        let generation = correctionGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.correctPaddedTarget(requested, generation: generation)
        }
    }

    /// 計算で置いた中心は、tilt の上限などでわずかにずれる。地図の投影で実際の位置を測り、
    /// パディングの残りの中央に来るまで中心だけを動かし直す。
    private func correctPaddedTarget(_ requested: MapCameraPosition, generation: Int, remaining: Int = 4) {
        guard remaining > 0, generation == correctionGeneration, let mapView,
              let desired = CameraPaddingEmulation.paddedCenterPoint(
                  paddings: requested.paddings,
                  viewportSize: mapView.bounds.size
              ) else { return }
        let map: MapboxMap = mapView.mapboxMap
        let actual = map.point(for: CLLocationCoordinate2D(
            latitude: requested.position.latitude,
            longitude: requested.position.longitude
        ))
        let deltaX = actual.x - desired.x
        let deltaY = actual.y - desired.y
        guard abs(deltaX) >= 0.5 || abs(deltaY) >= 0.5 else { return }
        // 目標が画面の外（パディングが地図より大きい）なら、地図の投影が当てにならないので詰めない
        // （Mapbox は画面外の点を (-1, -1) で返す）。
        guard mapView.bounds.contains(actual) else { return }
        let currentCenter = map.point(for: map.cameraState.center)
        let center = map.coordinate(for: CGPoint(x: currentCenter.x + deltaX, y: currentCenter.y + deltaY))
        map.setCamera(to: CameraOptions(center: center))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.correctPaddedTarget(requested, generation: generation, remaining: remaining - 1)
        }
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
    private let completion: (() -> Void)?
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
        duration: TimeInterval,
        completion: (() -> Void)? = nil
    ) {
        self.completion = completion
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
        if t >= 1.0 {
            stop()
            completion?()
        }
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
