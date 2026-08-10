import Combine
import Foundation
import MapConductorCore

/// Mapbox の state。
///
/// カメラの保持と委譲、`uiSettings`、`id` はコアの ``MapViewState`` が持つ。
/// ここに残るのは **Mapbox 固有のもの**だけ:
///  - `mapDesignType`（プロバイダ固有の型）
///  - プロバイダ型のホルダーと、それを返す `getMapViewHolder()` の絞り込み
public final class MapboxViewState: MapViewState<MapboxMapDesignType> {
    @Published private var _mapDesignType: MapboxMapDesignType

    /// Provider-typed holder: `mapView` is `MapView`, `map` is `MapboxMap`, no cast needed.
    public private(set) var mapViewHolder: MapboxMapViewHolder?

    public override var mapDesignType: MapboxMapDesignType {
        get { _mapDesignType }
        set { _mapDesignType = newValue }
    }

    public init(
        id: String,
        mapDesignType: MapboxMapDesignType = MapboxMapDesign.Standard,
        cameraPosition: MapCameraPosition = .Default,
        uiSettings: MapUISettings = MapUISettings()
    ) {
        self._mapDesignType = mapDesignType
        super.init(id: id, initialCameraPosition: cameraPosition, uiSettings: uiSettings)
    }

    public convenience init(
        mapDesignType: MapboxMapDesignType = MapboxMapDesign.Standard,
        cameraPosition: MapCameraPosition = .Default,
        uiSettings: MapUISettings = MapUISettings()
    ) {
        self.init(id: UUID().uuidString, mapDesignType: mapDesignType, cameraPosition: cameraPosition, uiSettings: uiSettings)
    }

    /// アプリが `state.getMapViewHolder()?.map` でネイティブの地図を取れる形を保つための絞り込み。
    public override func getMapViewHolder() -> AnyMapViewHolder? {
        mapViewHolder.map { AnyMapViewHolder($0) }
    }

    func setController(_ controller: (any MapViewControllerProtocol)?) {
        attachController(controller)
    }

    func setMapViewHolder(_ holder: MapboxMapViewHolder?) {
        mapViewHolder = holder
    }

    func updateCameraPosition(_ cameraPosition: MapCameraPosition) {
        setCameraPositionInternal(cameraPosition)
    }
}
