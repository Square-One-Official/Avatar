// Canvas-floating control-cluster (E22.2) — persistent verankerd rechtsboven
// óp het portret. Frame/positionering-acties die eerst in het Edit-paneel
// zaten: crop, auto-frame/center, fix camera angle, flip, restore body. Glas-
// knoppen (DSToolButton) met hun eigen hover-tooltip ("popover per knop").
// Crop + fix-angle zijn nog stubs (toekomstige stories); auto-frame en flip
// werken; restore-body loopt via de Pro-gate.

import AvatarUI
import SwiftUI

struct CanvasControlsCluster: View {
    var onCrop: (() -> Void)? = nil
    var onAutoFrame: () -> Void = {}
    var onFixAngle: (() -> Void)? = nil
    var onFlip: () -> Void = {}
    var onRestoreBody: () -> Void = {}

    var body: some View {
        VStack(spacing: DSSpacing.gap2) {
            DSToolButton(Image(systemName: "crop"), label: "Crop", tooltipEdge: .bottom) {
                onCrop?()
            }
            .disabled(onCrop == nil)
            .opacity(onCrop == nil ? 0.55 : 1)

            DSToolButton(Image(systemName: "viewfinder"), label: "Auto-frame & center", tooltipEdge: .bottom) {
                onAutoFrame()
            }

            DSToolButton(Image(systemName: "camera"), label: "Fix camera angle", tooltipEdge: .bottom) {
                onFixAngle?()
            }
            .disabled(onFixAngle == nil)
            .opacity(onFixAngle == nil ? 0.55 : 1)

            DSToolButton(Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right"), label: "Flip horizontal", tooltipEdge: .bottom) {
                onFlip()
            }

            DSToolButton(Image(systemName: "arrow.up.left.and.arrow.down.right"), label: "Restore body", tooltipEdge: .bottom) {
                onRestoreBody()
            }
        }
        .padding(DSSpacing.gap3)
    }
}
