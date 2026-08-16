Pod::Spec.new do |s|
  s.name = "MapConductorForMapbox"
  s.version = "1.2.0"
  s.summary = "MapConductor's Mapbox provider."
  s.license = { :type => "Apache-2.0" }
  s.author = "MapConductor"
  s.homepage = "https://github.com/MapConductor/ios-for-mapbox"
  s.source = { :path => __dir__ }
  # Package.swift の `.iOS(.v17)` に合わせる。下げると MapboxMaps 11 系の
  # API（`mapboxMap.style.uri` 周辺）でコンパイルが通らない。
  s.platform = :ios, "17.0"
  s.swift_version = "5.9"
  s.source_files = "Sources/MapConductorForMapbox/**/*.swift"
  s.dependency "MapConductorCore"
  # ベンダ SDK は **source pod ではなく本家の pod** から引く。
  # `MapboxMaps` は CocoaPods trunk にあり、その依存（`MapboxCoreMaps` /
  # `MapboxCommon`）は Mapbox の CDN から降りてくる。Maps SDK v11 は
  # ダウンロードトークン不要（実測: 認証なしで 200）。**実行時の公開アクセストークンは別途必要。**
  #
  # SPM 側（Package.swift）は `mapbox-maps-ios-binary` から 11.28.0 を引いている。
  # 同じ 11 系だが**解決経路が違う**ので、片方を上げたらもう片方も確認すること。
  s.dependency "MapboxMaps", "~> 11.26"
end
