import Combine
import CoreLocation
import MapboxMaps
import MapConductorCore
import SwiftUI
import UIKit

/// A container view that only intercepts touches on its subviews (InfoBubbles),
/// allowing touches elsewhere to pass through to the map view below.
private class PassthroughContainerView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hitView = super.hitTest(point, with: event)
        return hitView == self ? nil : hitView
    }
}

public struct MapboxMapView: View {
    @ObservedObject private var state: MapboxViewState
    private let projection: MapProjection

    private let onMapLoaded: OnMapLoadedHandler<MapboxViewState>?
    private let onMapClick: OnMapEventHandler?
    private let onMapLongClick: OnMapEventHandler?
    private let onCameraMoveStart: OnCameraMoveHandler?
    private let onCameraMove: OnCameraMoveHandler?
    private let onCameraMoveEnd: OnCameraMoveHandler?
    private let sdkInitialize: (() -> Void)?
    private let content: () -> MapViewContent

    public init(
        state: MapboxViewState,
        projection: MapProjection = .mercator,
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
        self.onMapLoaded = onMapLoaded
        self.onMapClick = onMapClick
        self.onMapLongClick = onMapLongClick
        self.onCameraMoveStart = onCameraMoveStart
        self.onCameraMove = onCameraMove
        self.onCameraMoveEnd = onCameraMoveEnd
        self.sdkInitialize = sdkInitialize
        self.content = content
    }

    public var body: some View {
        let mapContent = content()
        return ZStack {
            MapboxMapViewRepresentable(
                state: state,
                projection: projection,
                onMapLoaded: onMapLoaded,
                onMapClick: onMapClick,
                onMapLongClick: onMapLongClick,
                onCameraMoveStart: onCameraMoveStart,
                onCameraMove: onCameraMove,
                onCameraMoveEnd: onCameraMoveEnd,
                sdkInitialize: sdkInitialize,
                content: mapContent
            )
            ForEach(0..<mapContent.views.count, id: \.self) { index in
                mapContent.views[index]
            }
            MapAttributionOverlay(
                designRules: state.mapDesignType.attributionRules,
                rasterLayers: mapContent.rasterLayers,
                camera: state.cameraPosition
            )
        }
    }
}

// MARK: - UIViewRepresentable

private struct MapboxMapViewRepresentable: UIViewRepresentable {
    @ObservedObject var state: MapboxViewState
    let projection: MapProjection

    let onMapLoaded: OnMapLoadedHandler<MapboxViewState>?
    let onMapClick: OnMapEventHandler?
    let onMapLongClick: OnMapEventHandler?
    let onCameraMoveStart: OnCameraMoveHandler?
    let onCameraMove: OnCameraMoveHandler?
    let onCameraMoveEnd: OnCameraMoveHandler?
    let sdkInitialize: (() -> Void)?
    let content: MapViewContent

    func makeCoordinator() -> Coordinator {
        Coordinator(
            state: state,
            projection: projection,
            onMapLoaded: onMapLoaded,
            onMapClick: onMapClick,
            onMapLongClick: onMapLongClick,
            onCameraMoveStart: onCameraMoveStart,
            onCameraMove: onCameraMove,
            onCameraMoveEnd: onCameraMoveEnd
        )
    }

    func makeUIView(context: Context) -> MapView {
        if let sdkInitialize {
            Coordinator.runOnce(sdkInitialize)
        }
        let initOptions = MapInitOptions(
            cameraOptions: state.cameraPosition.toMapboxCameraOptions(),
            styleURI: StyleURI(rawValue: state.mapDesignType.styleURI)
        )
        let mapView = MapView(frame: .zero, mapInitOptions: initOptions)
        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        mapView.gestures.options.panEnabled = state.uiSettings.scrollGesture

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
        context.coordinator.updateContent(content)
        return mapView
    }

    func updateUIView(_ uiView: MapView, context: Context) {
        let newStyleURI = StyleURI(rawValue: state.mapDesignType.styleURI)
        if let newStyleURI, uiView.mapboxMap.style.uri != newStyleURI {
            uiView.mapboxMap.loadStyle(newStyleURI)
        }
        uiView.gestures.options.panEnabled = state.uiSettings.scrollGesture
        context.coordinator.setProjection(projection, mapView: uiView)
        context.coordinator.updateContent(content)
        context.coordinator.updateInfoBubbleLayouts()
    }

    static func dismantleUIView(_ uiView: MapView, coordinator: Coordinator) {
        coordinator.unbind()
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject {
        private let state: MapboxViewState
        private var projection: MapProjection
        private let onMapLoaded: OnMapLoadedHandler<MapboxViewState>?
        private let onMapClick: OnMapEventHandler?
        private let onMapLongClick: OnMapEventHandler?
        private let onCameraMoveStart: OnCameraMoveHandler?
        private let onCameraMove: OnCameraMoveHandler?
        private let onCameraMoveEnd: OnCameraMoveHandler?

        weak var mapView: MapView?
        private var controller: MapboxViewController?
        private var markerController: MapboxMarkerController?
        private var polylineController: MapboxPolylineController?
        private var polygonController: MapboxPolygonController?
        private var hullPolygonController: MapboxPolygonController?
        private var circleController: MapboxCircleController?
        private var groundImageController: MapboxGroundImageController?
        private var rasterController: MapboxRasterLayerController?
        private var infoBubbleController: InfoBubbleController?
        private lazy var strategyManager = StrategyMarkerManager<Feature, MapboxMarkerRenderer>(
            makeRenderer: { [weak self] strategy in
                guard let mapView = self?.mapView else { fatalError("mapView unavailable") }
                let layer = MarkerLayer(
                    sourceId: "mapconductor-cluster-source-\(UUID().uuidString)",
                    layerId: "mapconductor-cluster-layer-\(UUID().uuidString)"
                )
                return MapboxMarkerRenderer(mapView: mapView, markerManager: strategy.markerManager, markerLayer: layer)
            },
            shouldAddMarkers: { [weak self] in self?.isStyleLoaded ?? false }
        )

        // MapboxMaps Cancelable observers
        private var styleLoadedObserver: (any Cancelable)?
        private var cameraChangedObserver: (any Cancelable)?
        private var cameraIdleObserver: (any Cancelable)?

        private var isStyleLoaded = false
        private var didCallMapLoaded = false
        private let infoBubbleContainer = PassthroughContainerView()

        private static var hasInitializedSdk = false

        static func runOnce(_ initializer: () -> Void) {
            if hasInitializedSdk { return }
            hasInitializedSdk = true
            initializer()
        }

        init(
            state: MapboxViewState,
            projection: MapProjection,
            onMapLoaded: OnMapLoadedHandler<MapboxViewState>?,
            onMapClick: OnMapEventHandler?,
            onMapLongClick: OnMapEventHandler?,
            onCameraMoveStart: OnCameraMoveHandler?,
            onCameraMove: OnCameraMoveHandler?,
            onCameraMoveEnd: OnCameraMoveHandler?
        ) {
            self.state = state
            self.projection = projection
            self.onMapLoaded = onMapLoaded
            self.onMapClick = onMapClick
            self.onMapLongClick = onMapLongClick
            self.onCameraMoveStart = onCameraMoveStart
            self.onCameraMove = onCameraMove
            self.onCameraMoveEnd = onCameraMoveEnd
        }

        func bind(state: MapboxViewState, mapView: MapView) {
            let controller = MapboxViewController(mapView: mapView)
            self.controller = controller
            state.setController(controller)
            state.setMapViewHolder(controller.holder)

            let markerController = MapboxMarkerController(mapView: mapView) { [weak self] id in
                self?.infoBubbleController?.updateInfoBubblePosition(for: id)
            }
            self.markerController = markerController

            self.polylineController = MapboxPolylineController(mapView: mapView)
            self.polygonController = MapboxPolygonController(mapView: mapView)
            self.hullPolygonController = MapboxPolygonController(mapView: mapView)
            self.circleController = MapboxCircleController(mapView: mapView)
            self.groundImageController = MapboxGroundImageController(mapView: mapView)
            self.rasterController = MapboxRasterLayerController(mapView: mapView)

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

            // Subscribe to style loaded
            styleLoadedObserver = mapView.mapboxMap.onStyleLoaded.observeNext { [weak self] _ in
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
            if let mapView {
                strategyManager.update(
                    content: content,
                    initialCamera: mapView.mapboxMap.cameraState.toMapCameraPosition(
                        logicalTiltHint: controller?.lastLogicalTilt
                    )
                )
            }
            groundImageController?.syncGroundImages(content.groundImages)
            rasterController?.syncRasterLayers(content.rasterLayers)
            circleController?.syncCircles(content.circles)
            polylineController?.syncPolylines(content.polylines)
            polygonController?.syncPolygons(content.polygons)
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
            markerController?.onStyleLoaded(mapboxMap)
            strategyManager.renderer?.onStyleLoaded(mapboxMap)
            strategyManager.flush()
            if !didCallMapLoaded {
                didCallMapLoaded = true
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

        fileprivate func attachInfoBubbleContainer(to mapView: MapView) {
            guard infoBubbleContainer.superview !== mapView else { return }
            infoBubbleContainer.backgroundColor = .clear
            infoBubbleContainer.isUserInteractionEnabled = true
            infoBubbleContainer.frame = mapView.bounds
            infoBubbleContainer.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            mapView.addSubview(infoBubbleContainer)
        }

        fileprivate func updateInfoBubbleLayouts() {
            infoBubbleController?.updateAllLayouts()
        }

        private func visibleRegion(mapView: MapView) -> VisibleRegion? {
            let bounds = mapView.bounds
            guard !bounds.isEmpty else { return nil }
            let mapboxMap: MapboxMap = mapView.mapboxMap
            let sw = mapboxMap.coordinate(for: CGPoint(x: 0, y: bounds.height))
            let ne = mapboxMap.coordinate(for: CGPoint(x: bounds.width, y: 0))
            let nw = mapboxMap.coordinate(for: CGPoint(x: 0, y: 0))
            let se = mapboxMap.coordinate(for: CGPoint(x: bounds.width, y: bounds.height))
            let geoBounds = GeoRectBounds(
                southWest: GeoPoint(latitude: sw.latitude, longitude: sw.longitude, altitude: 0),
                northEast: GeoPoint(latitude: ne.latitude, longitude: ne.longitude, altitude: 0)
            )
            return VisibleRegion(
                bounds: geoBounds,
                nearLeft: GeoPoint(latitude: se.latitude, longitude: se.longitude, altitude: 0),
                nearRight: GeoPoint(latitude: sw.latitude, longitude: sw.longitude, altitude: 0),
                farLeft: GeoPoint(latitude: ne.latitude, longitude: ne.longitude, altitude: 0),
                farRight: GeoPoint(latitude: nw.latitude, longitude: nw.longitude, altitude: 0)
            )
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
