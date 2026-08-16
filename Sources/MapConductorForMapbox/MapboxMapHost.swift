import Combine
import CoreLocation
import MapConductorCore
import MapboxMaps
import SwiftUI
import UIKit

/// 地図一式（`MapView` + コントローラ群 + オーバーレイ結線）を保持するホスト。
///
/// SwiftUI の `UIViewRepresentable.Coordinator` として使うことも、React Native の
/// ように SwiftUI を介さないホストから直接使うこともできる。
/// `MapboxMapView` はこのホストの薄い SwiftUI ラッパーにすぎない。
/// `MapLibreMapHost` / `MapTilerMapHost` と同じ形。
///
/// アプリ開発者向けの API ではないので `@_spi(MapConductorDriver)` を付ける。
/// 付けると `.swiftinterface`（凍結対象の公開 API）には載らず、
/// `@_spi(MapConductorDriver) import` した側からだけ見える。
@MainActor
@_spi(MapConductorDriver)
public final class MapboxMapHost: MapViewCoordinatorBase<MapboxViewState> {

    /// 地図を作り、ジェスチャ・バインド・初期コンテンツまで済ませて返す。
    ///
    /// SwiftUI の `makeUIView` が踏んでいた手順をそのまま公開したもので、
    /// React Native のような非 SwiftUI ホストも**同じ入口を通ること**。
    ///
    /// **`bind(state:mapView:)` と `self.mapView = mapView` を落とさないこと。**
    /// この 2 つが無くてもコンパイルは通り、地図もタイルも普通に描画される。
    /// 死ぬのはカメライベントとオーバーレイだけなので、起動直後の画では気づけない
    /// （ios-for-maptiler で実際に踏んだ。`ios-coordinator-to-maphost-extraction` 参照）。
    public func makeMapView(
        cameraRestriction: CameraRestriction?,
        content: MapViewContent
    ) -> MapView {
        if let sdkInitialize = handlers.sdkInitialize {
            Self.runOnce(sdkInitialize)
        }
        let initOptions = MapInitOptions(
            cameraOptions: state.cameraPosition.toMapboxCameraOptions(),
            styleURI: StyleURI(rawValue: state.mapDesignType.styleURI)
        )
        let mapView = MapView(frame: .zero, mapInitOptions: initOptions)
        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        applyGestureSettings(to: mapView)

        let tapGesture = UITapGestureRecognizer(
            target: self,
            action: #selector(MapboxMapHost.handleMapTap(_:))
        )
        tapGesture.cancelsTouchesInView = false
        mapView.addGestureRecognizer(tapGesture)

        let longPressGesture = UILongPressGestureRecognizer(
            target: self,
            action: #selector(MapboxMapHost.handleMarkerLongPress(_:))
        )
        longPressGesture.minimumPressDuration = 0.2
        mapView.addGestureRecognizer(longPressGesture)

        attachInfoBubbleContainer(to: mapView)
        self.mapView = mapView
        bind(state: state, mapView: mapView)
        // android-for-mapbox の MapboxMapView.kt と同じ位置で適用する。
        applyCameraRestriction(cameraRestriction)
        updateContent(content)
        return mapView
    }

    /// state を書き換えたあとに、ネイティブビューへ直接書く分を反映する。
    /// SwiftUI の `updateUIView` が担っていた仕事のうち、コンテンツ以外。
    public func syncNativeViewSettings(cameraRestriction: CameraRestriction? = nil) {
        guard let mapView else { return }
        let newStyleURI = StyleURI(rawValue: state.mapDesignType.styleURI)
        if let newStyleURI, mapView.mapboxMap.style.uri != newStyleURI {
            mapView.mapboxMap.loadStyle(newStyleURI)
        }
        // ジェスチャはここで直接適用する。SwiftUI の同期フックは常にネイティブビューを
        // 持っているのに対し、コントローラはまだ生成されていない／まだ mapView を
        // 保持していないことがあり、その場合に設定が落ちる（実機の UISettingsUITests が
        // MapLibre/MapTiler/Mapbox で検出）。コントローラ側の `applyUISettings` は
        // android-sdk と同じ API を提供するための命令的な入口で、同じ値を同じ
        // ネイティブプロパティへ書く。
        applyGestureSettings(to: mapView)
        setProjection(projection, mapView: mapView)
        // 制限値が変わったときだけ再適用する（毎フレーム native API を叩かない）。
        applyCameraRestriction(cameraRestriction)
    }

    /// `makeMapView` と `syncNativeViewSettings` の両方から呼ぶ。**7 つ揃っていること。**
    /// 1 つ落としてもコンパイルは通り、そのジェスチャだけ黙って効かなくなる。
    private func applyGestureSettings(to mapView: MapView) {
        mapView.gestures.options.panEnabled = state.uiSettings.scrollGesture
        mapView.gestures.options.pinchZoomEnabled = state.uiSettings.zoomGesture
        mapView.gestures.options.doubleTapToZoomInEnabled = state.uiSettings.zoomGesture
        mapView.gestures.options.doubleTouchToZoomOutEnabled = state.uiSettings.zoomGesture
        mapView.gestures.options.quickZoomEnabled = state.uiSettings.zoomGesture
        mapView.gestures.options.rotateEnabled = state.uiSettings.rotateGesture
        mapView.gestures.options.pitchEnabled = state.uiSettings.tiltGesture
    }
    /// android-sdk の `cameraRestriction?.let { controller.setCameraRestriction(it) }` 相当。
    public func applyCameraRestriction(_ restriction: CameraRestriction?) {
        applyCameraRestriction(restriction, to: controller)
    }

    private var projection: MapProjection

    public private(set) weak var mapView: MapView?
    // updateUIView から applyUISettings を呼ぶため private を外している。
    private(set) var controller: MapboxViewController?
    private var markerController: MapboxMarkerController?
    private var polylineController: MapboxPolylineController?
    private var polygonController: MapboxPolygonController?
    private var hullPolygonController: MapboxPolygonController?
    private var circleController: MapboxCircleController?
    private var groundImageController: MapboxGroundImageController?
    private var rasterController: MapboxRasterLayerController?
    private var infoBubbleController: InfoBubbleController?
    private var overlayScope: MapOverlayScope?
    private lazy var strategyManager = StrategyMarkerManager<Feature, MapboxMarkerRenderer>(
        makeRenderer: { [weak self] strategy in
            guard let mapView = self?.mapView else { fatalError("mapView unavailable") }
            let layer = MarkerLayer(
                sourceId: "mapconductor-cluster-source-\(UUID().uuidString)",
                layerId: "mapconductor-cluster-layer-\(UUID().uuidString)"
            )
            return MapboxMarkerRenderer(mapView: mapView, markerManager: strategy.markerManager, markerLayer: layer)
        },
        shouldAddMarkers: { [weak self] in self?.isStyleLoaded ?? false },
        currentCamera: { [weak self] in
            guard let self, let mapView = self.mapView else { return nil }
            return mapView.mapboxMap.cameraState.toMapCameraPosition(
                logicalTiltHint: self.controller?.lastLogicalTilt
            )
        }
    )

    // MapboxMaps Cancelable observers
    private var styleLoadedObserver: (any Cancelable)?
    private var cameraChangedObserver: (any Cancelable)?
    private var cameraIdleObserver: (any Cancelable)?

    private var isStyleLoaded = false

    public init(
        state: MapboxViewState,
        projection: MapProjection,
        handlers: MapViewHandlers<MapboxViewState>
    ) {
        self.projection = projection
        super.init(state: state, handlers: handlers)
    }

    func bind(state: MapboxViewState, mapView: MapView) {
        // Publish marker rendering as a map-scoped capability. Add-on modules resolve it
        // from the registry; this provider never learns that clustering exists.
        state.serviceRegistry.put(MarkerRenderingSupportKey.self, strategyManager)

        let controller = MapboxViewController(mapView: mapView)
        self.controller = controller
        state.setController(controller)
        // 拡張モジュール（ヒートマップ等）がオーバーレイコントローラを登録できるようにする。
        state.serviceRegistry.put(OverlayControllerRegistryKey.self, controller.overlayControllers)
        state.setMapViewHolder(controller.typedHolder)

        let markerController = MapboxMarkerController(mapView: mapView) { [weak self] id in
            self?.infoBubbleController?.updateInfoBubblePosition(for: id)
        }
        self.markerController = markerController

        let polylineController = MapboxPolylineController(mapView: mapView)
        self.polylineController = polylineController
        let polygonController = MapboxPolygonController(mapView: mapView)
        self.polygonController = polygonController
        self.hullPolygonController = MapboxPolygonController(mapView: mapView)
        let circleController = MapboxCircleController(mapView: mapView)
        self.circleController = circleController
        let groundImageController = MapboxGroundImageController(mapView: mapView)
        self.groundImageController = groundImageController
        let rasterController = MapboxRasterLayerController(mapView: mapView)
        self.rasterController = rasterController

        // Route the simple overlays through the shared collector so each
        // controller subscribes to one source of truth instead of the map
        // host re-diffing arrays every render.
        // クリックカスケードとスロット解決がここから kind で引く。
        // **登録を忘れるとタップに反応しなくなる。**
        controller.registerOverlayController(markerController)
        controller.registerOverlayController(circleController)
        controller.registerOverlayController(polylineController)
        controller.registerOverlayController(polygonController)
        controller.registerOverlayController(groundImageController)
        controller.registerOverlayController(rasterController)

        let overlayScope = MapOverlayScope()
        self.overlayScope = overlayScope
        bindOverlayCollector(overlayScope.circleCollector, to: circleController)
        bindOverlayCollector(overlayScope.polylineCollector, to: polylineController)
        bindOverlayCollector(overlayScope.polygonCollector, to: polygonController)
        bindOverlayCollector(overlayScope.rasterLayerCollector, to: rasterController)
        // GroundImage is not a core GroundImageController subclass on Mapbox,
        // so it stays on its own sync path (below), not the collector.

        let infoBubbleController = InfoBubbleController(
            mapView: mapView,
            container: infoBubbleContainer,
            markerController: markerController
        )
        self.infoBubbleController = infoBubbleController

        // Screen-space marker animation layer: shares the info-bubble
        // container (inserted below the bubbles) and the map projection.
        markerController.renderer.animationOverlay = MarkerAnimationOverlayCoordinator(
            container: infoBubbleContainer,
            project: { [weak mapView] point in
                guard let mapView else { return nil }
                let coordinate = CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
                let p = mapView.mapboxMap.point(for: coordinate)
                return (p.x.isFinite && p.y.isFinite) ? p : nil
            },
            projectionGate: screenProjectionGate(feature: "marker animation overlay")
        )

        // Subscribe to style loaded.
        //
        // `observe` であって `observeNext` ではない。スタイルは 1 回しか載らないものでは
        // なく、地図デザインを変えるたびに `loadStyle` で載せ直される。`observeNext` は
        // 初回だけの購読なので、2 回目以降のスタイル読み込みでソース／レイヤの
        // 再作成が走らず、オーバーレイが消えたまま戻らなかった（実機の
        // MapboxStyleReloadUITests が検出）。
        // android-for-mapbox の `subscribeStyleLoaded` も継続購読。
        // 初回だけでよい処理（notifyMapInitialized / onMapLoaded）は
        // `performMapLoadedOnce` 側で 1 回に抑えている。
        styleLoadedObserver = mapView.mapboxMap.onStyleLoaded.observe { [weak self] _ in
            self?.handleStyleLoaded(mapView: mapView)
        }

        // Subscribe to camera events
        var isCameraMoving = false
        cameraChangedObserver = mapView.mapboxMap.onCameraChanged.observe { [weak self] event in
            guard let self else { return }
            let camera = event.cameraState.toMapCameraPosition(
                logicalTiltHint: self.controller?.lastLogicalTilt,
                visibleRegion: self.visibleRegion(mapView: mapView)
            )
            self.state.updateCameraPosition(camera)
            if !isCameraMoving {
                isCameraMoving = true
                self.controller?.notifyCameraMoveStart(camera)
                self.onCameraMoveStart?(camera)
            }
            self.controller?.notifyCameraMove(camera)
            self.onCameraMove?(camera)
            Task { [weak self] in
                await self?.circleController?.onCameraChanged(mapCameraPosition: camera)
                await self?.strategyManager.onCameraChanged(camera)
            }
            self.updateInfoBubbleLayouts()
        }

        cameraIdleObserver = mapView.mapboxMap.onMapIdle.observe { [weak self] _ in
            guard let self else { return }
            let camera = mapView.mapboxMap.cameraState.toMapCameraPosition(
                logicalTiltHint: self.controller?.lastLogicalTilt,
                visibleRegion: self.visibleRegion(mapView: mapView)
            )
            isCameraMoving = false
            self.controller?.notifyCameraMoveEnd(camera)
            self.onCameraMoveEnd?(camera)
            self.updateInfoBubbleLayouts()
        }
    }

    public func unbind() {
        // 登録した capability を取り下げる。レジストリの持ち主は state で、ビューより長生きするため、
        // ここで外さないと破棄済みのコントローラを掴んだまま残る。
        state.serviceRegistry.removeProviderRegistrations()
        // 登録済みオーバーレイコントローラ（拡張モジュール含む）を破棄する。
        controller?.destroy()
        state.setController(nil)
        state.setMapViewHolder(nil)
        markerController?.renderer.animationOverlay?.unbind()
        markerController?.renderer.animationOverlay = nil
        styleLoadedObserver?.cancel()
        styleLoadedObserver = nil
        cameraChangedObserver?.cancel()
        cameraChangedObserver = nil
        cameraIdleObserver?.cancel()
        cameraIdleObserver = nil
        controller = nil
        markerController?.unbind()
        markerController = nil
        polylineController?.unbind()
        polylineController = nil
        polygonController?.unbind()
        polygonController = nil
        hullPolygonController?.unbind()
        hullPolygonController = nil
        circleController?.unbind()
        circleController = nil
        groundImageController?.unbind()
        groundImageController = nil
        rasterController?.unbind()
        rasterController = nil
        infoBubbleController?.unbind()
        infoBubbleController = nil
        overlayScope?.clear()
        overlayScope = nil
        strategyManager.clear()
        isStyleLoaded = false
    }

    public func updateContent(_ content: MapViewContent) {
        if let mapView {
            let camera = mapView.mapboxMap.cameraState.toMapCameraPosition(
                logicalTiltHint: controller?.lastLogicalTilt,
                visibleRegion: visibleRegion(mapView: mapView)
            )
            polylineController?.setCurrentCameraPosition(camera)
        }
        infoBubbleController?.syncInfoBubbles(content.infoBubbles)
        markerController?.tilingOptions = content.markerTilingOptions
        markerController?.syncMarkers(content.markers)
        groundImageController?.syncGroundImages(content.groundImages)
        overlayScope?.rasterLayerCollector.sync(content.rasterLayers.map { $0.state })
        overlayScope?.circleCollector.sync(content.circles.map { $0.state })
        overlayScope?.polylineCollector.sync(content.polylines.map { $0.state })
        overlayScope?.polygonCollector.sync(content.polygons.map { $0.state })
        for handler in content.polygonSyncHandlers {
            let hullController = hullPolygonController
            handler.bindPolygonSync { [weak hullController] states in
                await hullController?.add(data: states)
            }
        }
        infoBubbleController?.updateAllLayouts()
    }

    // MARK: - Style loaded

    private func handleStyleLoaded(mapView: MapView) {
        isStyleLoaded = true
        applyProjection(to: mapView)
        let mapboxMap: MapboxMap = mapView.mapboxMap
        groundImageController?.onStyleLoaded(mapboxMap)
        rasterController?.onStyleLoaded(mapboxMap)
        polygonController?.onStyleLoaded(mapboxMap)
        hullPolygonController?.onStyleLoaded(mapboxMap)
        polylineController?.onStyleLoaded(mapboxMap)
        circleController?.onStyleLoaded(mapboxMap)
        // Collector-routed overlays are add()ed eagerly (possibly before the
        // style was ready). Re-emit the current set now that the style is
        // loaded so their style layers are (re)created. add() is idempotent.
        overlayScope?.rasterLayerCollector.flush()
        overlayScope?.circleCollector.flush()
        overlayScope?.polylineCollector.flush()
        overlayScope?.polygonCollector.flush()
        markerController?.onStyleLoaded(mapboxMap)
        strategyManager.renderer?.onStyleLoaded(mapboxMap)
        strategyManager.flush()
        performMapLoadedOnce {
            controller?.notifyMapInitialized()
            onMapLoaded?(state)
        }
        updateInfoBubbleLayouts()
    }

    public func setProjection(_ projection: MapProjection, mapView: MapView) {
        guard self.projection != projection else { return }
        self.projection = projection
        applyProjection(to: mapView)
    }

    private func applyProjection(to mapView: MapView) {
        let name: StyleProjectionName = projection == .globe ? .globe : .mercator
        do {
            try mapView.mapboxMap.setProjection(StyleProjection(name: name))
        } catch {
            MCLog.map("Unable to set Mapbox projection: \(error)")
        }
    }

    // MARK: - Gestures

    @objc public func handleMapTap(_ recognizer: UITapGestureRecognizer) {
        guard let mapView, recognizer.state == .ended else { return }
        let point = recognizer.location(in: mapView)
        let camera = mapView.mapboxMap.cameraState.toMapCameraPosition(
            logicalTiltHint: controller?.lastLogicalTilt,
            visibleRegion: visibleRegion(mapView: mapView)
        )
        polylineController?.setCurrentCameraPosition(camera)
        Task { [weak self] in
            guard let self else { return }
            if await self.markerController?.handleTap(at: point) == true {
                self.updateInfoBubbleLayouts()
                return
            }
            if await self.handleStrategyTap(at: point) {
                self.updateInfoBubbleLayouts()
                return
            }
            let mapboxMap: MapboxMap = mapView.mapboxMap
            let coordinate = mapboxMap.coordinate(for: point)
            // circle → groundImage → polyline → polygon の一本道。
            // 順序と先勝ちはコアの dispatchOverlayTap が持つ。
            let tapped = GeoPoint(latitude: coordinate.latitude, longitude: coordinate.longitude, altitude: 0)
            if self.controller?.dispatchOverlayTap(position: tapped) == true {
                self.updateInfoBubbleLayouts()
                return
            }

            let geoPoint = GeoPoint(latitude: coordinate.latitude, longitude: coordinate.longitude, altitude: 0)
            self.controller?.notifyMapClick(geoPoint)
            self.onMapClick?(geoPoint)
        }
    }

    @objc public func handleMarkerLongPress(_ recognizer: UILongPressGestureRecognizer) {
        let handledByMarker = markerController?.handleLongPress(recognizer) ?? false
        if !handledByMarker, recognizer.state == .began, let mapView {
            let point = recognizer.location(in: mapView)
            let coordinate = mapView.mapboxMap.coordinate(for: point)
            let geoPoint = GeoPoint(latitude: coordinate.latitude, longitude: coordinate.longitude, altitude: 0)
            controller?.notifyMapLongClick(geoPoint)
            onMapLongClick?(geoPoint)
        }
        updateInfoBubbleLayouts()
    }

    // MARK: - Helpers

    public func updateInfoBubbleLayouts() {
        infoBubbleController?.updateAllLayouts()
    }

    /// 4 隅の逆投影は全プロバイダ共通なのでコアの ``buildVisibleRegion`` を使う。
    ///
    /// ★ ここで隅の取り違えが 1 件直っている。移行前は
    /// `nearLeft = se`（右下）/ `nearRight = sw`（左下）/
    /// `farLeft = ne`（右上）/ `farRight = nw`（左上）と**左右が入れ替わって**いた。
    /// android と ios-for-maplibre はどちらも
    /// nearLeft = 左下 / nearRight = 右下 / farLeft = 左上 / farRight = 右上。
    private func visibleRegion(mapView: MapView) -> VisibleRegion? {
        MapboxMapViewHolder(mapView: mapView).buildVisibleRegion()
    }

    private func handleStrategyTap(at point: CGPoint) async -> Bool {
        guard let markerId = await strategyManager.renderer?.markerId(at: point),
              let state = strategyManager.controller?.markerManager.getEntity(markerId)?.state,
              state.clickable else { return false }
        strategyManager.controller?.dispatchClick(state)
        return true
    }
}
