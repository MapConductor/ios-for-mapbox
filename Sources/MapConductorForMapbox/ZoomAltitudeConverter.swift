import Foundation
import MapConductorCore

/// Zoom offset: GoogleZoom ≈ MapboxSDK.zoom + 1.0 (same as MapLibre)
let mapboxToGoogleZoomOffset = 1.0

extension ZoomAltitudeConverterProtocol where Self == MapboxZoomAltitudeConverter {
    public static var mapbox: MapboxZoomAltitudeConverter { MapboxZoomAltitudeConverter() }
}

/// 統一ズーム（Google Maps 基準・256px タイル）⇄ 高度の変換。
///
/// Mapbox は 512px タイルのベクタエンジンなので、統一ズームはネイティブズーム + 1。
/// 換算式はコアの ``WebMercatorZoomAltitudeConverter`` にある。
///
/// ## ★ 移行時に直した不具合
///
/// 移行前の実装は `mapboxZoomToGoogleZoom` / `googleZoomToMapboxZoom` を**宣言しながら
/// `zoomLevelToAltitude` / `altitudeToZoomLevel` の中で一度も使っていなかった**。
/// 呼び出し側（`MapCameraPositionExtensions`）はネイティブズームを渡しているので、
/// オフセット +1 が抜けたぶん**高度が 2 倍**になっていた。
///
/// これが見えるのは `tilt < 0`（見上げ）の疑似表現だけで、そこでは
/// `distanceForward = altitude * tan(tilt)` が 2 倍遠くへ寄る。
/// android-for-mapbox と ios-for-maplibre はどちらも +1 を当てているので、
/// **iOS の Mapbox だけが 2 倍ずれていた**ことになる。android に合わせて直した。
///
/// 移行前の値は `ios-sdk-core` の `zoom-golden.txt` に残してあり、
/// `ZoomAltitudeConverterGoldenTests` が「旧＝オフセット 0 / 新＝オフセット 1」の
/// 両方を固定している。
public class MapboxZoomAltitudeConverter: WebMercatorZoomAltitudeConverter {
    public init(zoom0Altitude: Double = AbstractZoomAltitudeConverter.defaultZoom0Altitude) {
        super.init(zoom0Altitude: zoom0Altitude, zoomOffset: mapboxToGoogleZoomOffset)
    }

    public static func mapboxZoomToGoogleZoom(_ zoom: Double) -> Double {
        (zoom + mapboxToGoogleZoomOffset).clamped(to: 0 ... 22)
    }

    public static func googleZoomToMapboxZoom(_ zoom: Double) -> Double {
        (zoom - mapboxToGoogleZoomOffset).clamped(to: 0 ... 22)
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
