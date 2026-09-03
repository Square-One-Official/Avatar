# E24.36 / cutout dimension audit (Chesterton's fence)

Signed off before changing `ShellModel.storeEffectResult` resolution policy.

## Readers of cutout pixel dimensions

| Reader | Location | Risk if cutout grows | Mitigation |
|--------|----------|----------------------|------------|
| Canvas transform | `EditorCanvasView`, `CanvasTransformOverlay` | Position drift | `adjustedScaleForResolutionChange` when keeping higher-res |
| Export | `PortraitExporter` | May export more detail at 2048 preset | Accepted — positive |
| Undo/redo | `EditorView` `ImageEnhanceUndo`, `CutoutDataUndo` | Larger PNG in undo snapshots | Accepted — bounded ~1 MP |
| Board undo | `BoardView` node undo | Same | Accepted |
| Thumbnails | `ThumbnailStore`, `ThumbnailRenderer` | Downscales to max pixel size | Low risk |
| Gallery/board composite | `PortraitsGalleryView`, `BoardView` | `maxDimension` caps | Low risk |
| Alpha mask | `ShellModel.applyAlphaMask` | Dimensional lockstep | Upscale mask + harden alpha |
| Re-isolation | `ShellModel.reIsolateSubject` | Uses result pixels | Low risk |
| Persistence | `Portrait2.cutoutData` external storage | Larger autosave per portrait | Bounded ~1 MP from stylize |
| AutoFramer | `AutoFramer` | Uses cutout size for fit | Runs on ratio-drift reset only |

## Decision

Keeping higher-res generative output (when result > cutout) is **accepted** with transform scale adjustment. Export gains detail; undo payloads grow modestly. No export-size regression expected — export composites at user-chosen side (512/1024/2048).
