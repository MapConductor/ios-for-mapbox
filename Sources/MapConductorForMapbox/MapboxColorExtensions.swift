import UIKit

internal extension UIColor {
    /// Encode as CSS `rgba(r,g,b,a)` string, usable with Mapbox `to-color` expression.
    func toMapboxColorString() -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        let ri = Int((r * 255).rounded())
        let gi = Int((g * 255).rounded())
        let bi = Int((b * 255).rounded())
        return "rgba(\(ri),\(gi),\(bi),\(a))"
    }
}
