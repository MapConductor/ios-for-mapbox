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

    // 地図の組み立てと結線は `MapboxMapHost` が持つ。ここは SwiftUI のライフサイクルを
    // ホストの呼び出しへ翻訳するだけにして、React Native のような非 SwiftUI ホストと
    // まったく同じ経路を通るようにしている。
    func makeCoordinator() -> MapboxMapHost {
        MapboxMapHost(state: state, projection: projection, handlers: handlers)
    }

    func makeUIView(context: Context) -> MapView {
        context.coordinator.makeMapView(cameraRestriction: cameraRestriction, content: content)
    }

    func updateUIView(_ uiView: MapView, context: Context) {
        context.coordinator.syncNativeViewSettings(cameraRestriction: cameraRestriction)
        context.coordinator.updateContent(content)
        context.coordinator.updateInfoBubbleLayouts()
    }

    static func dismantleUIView(_ uiView: MapView, coordinator: MapboxMapHost) {
        coordinator.unbind()
    }
}
