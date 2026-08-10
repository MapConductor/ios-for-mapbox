import Combine
import CoreLocation
import MapboxMaps
import MapConductorCore
import SwiftUI
import UIKit

public struct MapboxMapView: View {
    @ObservedObject private var state: MapboxViewState
    private let projection: MapProjection
    private let handlers: MapViewHandlers<MapboxViewState>
    private let cameraRestriction: CameraRestriction?
    private let content: () -> MapViewContent

    public init(
        state: MapboxViewState,
        projection: MapProjection = .mercator,
        cameraRestriction: CameraRestriction? = nil,
        onMapLoaded: OnMapLoadedHandler<MapboxViewState>? = nil,
        onMapClick: OnMapEventHandler? = nil,
        onMapLongClick: OnMapEventHandler? = nil,
        onCameraMoveStart: OnCameraMoveHandler? = nil,
        onCameraMove: OnCameraMoveHandler? = nil,
        onCameraMoveEnd: OnCameraMoveHandler? = nil,
        sdkInitialize: (() -> Void)? = nil,
        @MapViewContentBuilder content: @escaping () -> MapViewContent = { MapViewContent() }
    ) {
        self.state = state
        self.projection = projection
        self.handlers = MapViewHandlers(
            onMapLoaded: onMapLoaded,
            onMapClick: onMapClick,
            onMapLongClick: onMapLongClick,
            onCameraMoveStart: onCameraMoveStart,
            onCameraMove: onCameraMove,
            onCameraMoveEnd: onCameraMoveEnd,
            sdkInitialize: sdkInitialize
        )
        self.cameraRestriction = cameraRestriction
        self.content = content
    }

    public var body: some View {
        // The provider's registry is in scope only while content is being assembled —
        // the same window in which Compose provides `LocalMapServiceRegistry` around the
        // content lambda. Bracketing the pass lets a removed plugin be noticed.
        let support = state.serviceRegistry.get(MarkerRenderingSupportKey.self)
        support?.beginContentPass()
        let mapContent = MapServiceRegistryScope.with(state.serviceRegistry) { content() }
        support?.endContentPass()
        return MapViewBase(
            attributionRules: state.mapDesignType.attributionRules,
            camera: state.cameraPosition,
            content: mapContent
        ) {
            MapboxMapViewRepresentable(
                state: state,
                cameraRestriction: cameraRestriction,
                projection: projection,
                handlers: handlers,
                content: mapContent
            )
        }
    }
}

// MARK: - UIViewRepresentable

private struct MapboxMapViewRepresentable: UIViewRepresentable {
    @ObservedObject var state: MapboxViewState
    let cameraRestriction: CameraRestriction?
    let projection: MapProjection
    let handlers: MapViewHandlers<MapboxViewState>
    let content: MapViewContent

    func makeCoordinator() -> Coordinator {
        Coordinator(state: state, projection: projection, handlers: handlers)
    }

    func makeUIView(context: Context) -> MapView {
        if let sdkInitialize = handlers.sdkInitialize {
            Coordinator.runOnce(sdkInitialize)
        }
        let initOptions = MapInitOptions(
            cameraOptions: state.cameraPosition.toMapboxCameraOptions(),
            styleURI: StyleURI(rawValue: state.mapDesignType.styleURI)
        )
        let mapView = MapView(frame: .zero, mapInitOptions: initOptions)
        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        mapView.gestures.options.panEnabled = state.uiSettings.scrollGesture
        mapView.gestures.options.pinchZoomEnabled = state.uiSettings.zoomGesture
        mapView.gestures.options.doubleTapToZoomInEnabled = state.uiSettings.zoomGesture
        mapView.gestures.options.doubleTouchToZoomOutEnabled = state.uiSettings.zoomGesture
        mapView.gestures.options.quickZoomEnabled = state.uiSettings.zoomGesture
        mapView.gestures.options.rotateEnabled = state.uiSettings.rotateGesture
        mapView.gestures.options.pitchEnabled = state.uiSettings.tiltGesture

        let tapGesture = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleMapTap(_:))
        )
        tapGesture.cancelsTouchesInView = false
        mapView.addGestureRecognizer(tapGesture)

        let longPressGesture = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleMarkerLongPress(_:))
        )
        longPressGesture.minimumPressDuration = 0.2
        mapView.addGestureRecognizer(longPressGesture)

        context.coordinator.attachInfoBubbleContainer(to: mapView)
        context.coordinator.mapView = mapView
        context.coordinator.bind(state: state, mapView: mapView)
        // android-for-mapbox の MapboxMapView.kt と同じ位置で適用する。
        context.coordinator.applyCameraRestriction(cameraRestriction)
        context.coordinator.updateContent(content)
        return mapView
    }

    func updateUIView(_ uiView: MapView, context: Context) {
        let newStyleURI = StyleURI(rawValue: state.mapDesignType.styleURI)
        if let newStyleURI, uiView.mapboxMap.style.uri != newStyleURI {
            uiView.mapboxMap.loadStyle(newStyleURI)
        }
        // ジェスチャはここ（updateUIView）で直接適用する。SwiftUI の同期フックは常に
        // ネイティブビューを持っているのに対し、コントローラはまだ生成されていない／
        // まだ mapView を保持していないことがあり、その場合に設定が落ちる（実機の
        // UISettingsUITests が MapLibre/MapTiler/Mapbox で検出）。
        // コントローラ側の `applyUISettings` は android-sdk と同じ API を提供するための
        // 命令的な入口で、同じ値を同じネイティブプロパティへ書く。
        uiView.gestures.options.panEnabled = state.uiSettings.scrollGesture
        uiView.gestures.options.pinchZoomEnabled = state.uiSettings.zoomGesture
        uiView.gestures.options.doubleTapToZoomInEnabled = state.uiSettings.zoomGesture
        uiView.gestures.options.doubleTouchToZoomOutEnabled = state.uiSettings.zoomGesture
        uiView.gestures.options.quickZoomEnabled = state.uiSettings.zoomGesture
        uiView.gestures.options.rotateEnabled = state.uiSettings.rotateGesture
        uiView.gestures.options.pitchEnabled = state.uiSettings.tiltGesture
        context.coordinator.setProjection(projection, mapView: uiView)
        // 制限値が変わったときだけ再適用する（毎フレーム native API を叩かない）。
        context.coordinator.applyCameraRestriction(cameraRestriction)
        context.coordinator.updateContent(content)
        context.coordinator.updateInfoBubbleLayouts()
    }

    static func dismantleUIView(_ uiView: MapView, coordinator: Coordinator) {
        coordinator.unbind()
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: MapViewCoordinatorBase<MapboxViewState> {
        /// android-sdk の `cameraRestriction?.let { controller.setCameraRestriction(it) }` 相当。
        func applyCameraRestriction(_ restriction: CameraRestriction?) {
            applyCameraRestriction(restriction, to: controller)
        }

        private var projection: MapProjection

        weak var mapView: MapView?
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

        init(
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
                }
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

        func unbind() {
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

        func updateContent(_ content: MapViewContent) {
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

        func setProjection(_ projection: MapProjection, mapView: MapView) {
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

        @objc func handleMapTap(_ recognizer: UITapGestureRecognizer) {
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
                if self.circleController?.handleTap(at: coordinate) == true { self.updateInfoBubbleLayouts(); return }
                if self.polylineController?.handleTap(at: coordinate) == true { self.updateInfoBubbleLayouts(); return }
                if self.polygonController?.handleTap(at: coordinate) == true { self.updateInfoBubbleLayouts(); return }
                if self.groundImageController?.handleTap(at: coordinate) == true { self.updateInfoBubbleLayouts(); return }

                let geoPoint = GeoPoint(latitude: coordinate.latitude, longitude: coordinate.longitude, altitude: 0)
                self.controller?.notifyMapClick(geoPoint)
                self.onMapClick?(geoPoint)
            }
        }

        @objc func handleMarkerLongPress(_ recognizer: UILongPressGestureRecognizer) {
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

        fileprivate func updateInfoBubbleLayouts() {
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
}
