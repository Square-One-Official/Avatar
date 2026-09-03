import Foundation

extension Double {
    /// Klem naar het gesloten interval [0, 1]. Gedeeld door DSToast (progress)
    /// en DSColorPicker (sat/val/hue/alpha).
    var clamped01: Double { Swift.min(1, Swift.max(0, self)) }
}
