// Vector-catalogus van alle DS-componenten (Figma-sync via SVG). Rendert elk
// component in z'n representatieve states naar een vector-PDF via
// ImageRenderer → CGContext-PDF; `AvatarUI/scripts/export-vectors.sh` zet die
// om naar SVG (pdftocairo) en importeert ze in Figma. Geen assert — alleen
// bestanden. Draait uitsluitend met DS_VECTOR_DUMP_DIR=<map>.
//
// Naamgeving: "<Component>__<state>-<dark|light>.pdf". Tekst en SF Symbols
// komen als paden mee (exact SF Pro), dus geen font-substitutie in Figma.

import AppKit
import SwiftUI
import XCTest
@testable import AvatarUI

final class DSVectorCatalogExportTests: XCTestCase {

    private struct Sample {
        let name: String
        let view: AnyView
        init(_ name: String, _ view: some View) {
            self.name = name
            self.view = AnyView(view)
        }
    }

    @MainActor
    func testDumpVectorCatalog() throws {
        guard let dir = ProcessInfo.processInfo.environment["DS_VECTOR_DUMP_DIR"] else {
            throw XCTSkip("DS_VECTOR_DUMP_DIR niet gezet")
        }
        let base = URL(fileURLWithPath: dir)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

        var written = 0
        for sample in Self.samples() {
            for scheme in [ColorScheme.dark, .light] {
                let content = sample.view
                    .fixedSize()
                    .dsVectorExport()
                    .environment(\.colorScheme, scheme)
                let renderer = ImageRenderer(content: content)
                let url = base.appendingPathComponent(
                    "\(sample.name)-\(scheme == .dark ? "dark" : "light").pdf"
                )
                renderer.render { size, draw in
                    var box = CGRect(origin: .zero, size: size)
                    guard let consumer = CGDataConsumer(url: url as CFURL),
                          let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else { return }
                    ctx.beginPDFPage(nil)
                    draw(ctx)
                    ctx.endPDFPage()
                    ctx.closePDF()
                }
                written += 1
            }
        }
        print("DS_VECTOR_DUMP: \(written) bestanden in \(base.path)")
    }

    // MARK: - Catalogus

    private static let sparkle = Image(systemName: "sparkles")
    private static let symbols: [(String, DSIcon.Symbol)] = [
        ("edit", .edit), ("adjust", .adjust), ("effects", .effects), ("face", .face),
        ("clothing", .clothing), ("hair", .hair), ("background", .background), ("images", .images),
        ("share", .share), ("settings", .settings), ("undo", .undo), ("redo", .redo),
        ("add", .add), ("close", .close), ("crop", .crop), ("autoFrame", .autoFrame),
        ("flip", .flip), ("restoreBody", .restoreBody), ("frame", .frame), ("grid", .grid),
        ("shapeCircle", .shapeCircle), ("shapeSquare", .shapeSquare), ("whitenTeeth", .whitenTeeth),
        ("applyMakeup", .applyMakeup), ("reduceWrinkles", .reduceWrinkles), ("check", .check),
        ("sparkle", .sparkle), ("colorize", .colorize), ("boost", .boost),
        ("privacyOnDevice", .privacyOnDevice), ("privacyAppleCloud", .privacyAppleCloud),
        ("privacyAdvanced", .privacyAdvanced)
    ]

    private static func toolbarItems() -> [DSToolbarItem<Int>] {
        [
            DSToolbarItem(id: 0, icon: DSIcon.image(.sparkle), label: "Enhance"),
            DSToolbarItem(id: 1, icon: DSIcon.image(.effects), label: "Effects"),
            DSToolbarItem(id: 2, icon: DSIcon.image(.hair), label: "Hair"),
            DSToolbarItem(id: 3, icon: DSIcon.image(.clothing), label: "Shirt")
        ]
    }

    private static func overflowItems() -> [DSToolbarItem<Int>] {
        [
            DSToolbarItem(id: 10, icon: DSIcon.image(.face), label: "Face"),
            DSToolbarItem(id: 11, icon: DSIcon.image(.background), label: "Background")
        ]
    }

    private static func avatarCircle() -> some View {
        Circle().fill(DSColor.Background.neutralStrongest)
    }

    // swiftlint:disable:next function_body_length
    @MainActor
    private static func samples() -> [Sample] {
        var s: [Sample] = []

        // Buttons
        s.append(Sample("DSPrimaryButton__default", DSPrimaryButton("Whiten teeth") {}))
        s.append(Sample("DSPrimaryButton__icon", DSPrimaryButton("Whiten teeth", icon: sparkle) {}))
        s.append(Sample("DSPrimaryButton__small", DSPrimaryButton("Apply", size: .small) {}))
        s.append(Sample("DSPrimaryButton__disabled", DSPrimaryButton("Whiten teeth") {}.disabled(true)))
        s.append(Sample("DSPrimaryButton__fullWidth", DSPrimaryButton("Continue", fullWidth: true) {}.frame(width: 320)))
        s.append(Sample("DSGhostButton__default", DSGhostButton("Cancel") {}))
        s.append(Sample("DSGhostButton__icon", DSGhostButton("Retry", icon: sparkle) {}))
        s.append(Sample("DSGhostButton__small", DSGhostButton("Cancel", size: .small) {}))
        s.append(Sample("DSNeutralButton__default", DSNeutralButton("Manage") {}))
        s.append(Sample("DSNeutralButton__icon", DSNeutralButton("Manage", icon: sparkle) {}))
        s.append(Sample("DSNeutralButton__small", DSNeutralButton("Manage", size: .small) {}))
        s.append(Sample("DSAddButton__default", DSAddButton("Add photo") {}))
        s.append(Sample("DSIconButton__ghostNeutral", DSIconButton(sparkle, label: "Enhance") {}))
        s.append(Sample("DSIconButton__ghostNeutral-active", DSIconButton(sparkle, label: "Enhance", isActive: true) {}))
        s.append(Sample("DSIconButton__fillBrand", DSIconButton(sparkle, label: "Enhance", style: .fillBrand) {}))
        s.append(Sample("DSIconButton__small", DSIconButton(sparkle, label: "Enhance", size: .small) {}))
        s.append(Sample("DSToolButton__filled", DSToolButton(sparkle, label: "Enhance") {}))
        s.append(Sample("DSToolButton__filled-active", DSToolButton(sparkle, label: "Enhance", isActive: true) {}))
        s.append(Sample("DSToolButton__ghost", DSToolButton(sparkle, label: "Enhance", surface: .ghost) {}))
        s.append(Sample("DSCapsuleToolButton__ghost", DSCapsuleToolButton(label: "Effects", action: {}) { DSIcon(.effects) }))
        s.append(Sample("DSCapsuleToolButton__active", DSCapsuleToolButton(label: "Effects", isActive: true, action: {}) { DSIcon(.effects) }))
        s.append(Sample("DSCapsuleToolButton__chevron", DSCapsuleToolButton(label: "Background", showChevron: true, action: {}) { DSIcon(.background) }))
        s.append(Sample("DSCapsuleToolButton__secondary", DSCapsuleToolButton(label: "Effects", surface: .secondary, action: {}) { DSIcon(.effects) }))
        s.append(Sample("DSCapsuleToolButton__compact", DSCapsuleToolButton(label: "Effects", size: .compact, action: {}) { DSIcon(.effects) }))
        s.append(Sample("DSCapsuleToolButton__chip", DSCapsuleToolButton(label: "Effects", size: .chip, action: {}) { DSIcon(.effects) }))
        s.append(Sample("DSCapsuleToolButton__iconOnly", DSCapsuleToolButton(action: {}) { DSIcon(.undo) }))

        // Controls
        s.append(Sample("DSToggle__on", DSToggle(isOn: .constant(true))))
        s.append(Sample("DSToggle__off", DSToggle(isOn: .constant(false))))
        s.append(Sample("DSSegmentedControl__default", DSSegmentedControl(
            selection: .constant(1),
            segments: [.init(tag: 0, label: "Light"), .init(tag: 1, label: "Dark")]
        )))
        s.append(Sample("DSSegmentedControl__three-equalWidth", DSSegmentedControl(
            selection: .constant(0),
            segments: [.init(tag: 0, label: "Regular"), .init(tag: 1, label: "High"), .init(tag: 2, label: "Cloud")],
            equalWidth: true
        ).frame(width: 300)))
        s.append(Sample("DSSlider__fill", DSSlider(value: .constant(0.6), in: 0...1).frame(width: 240)))
        s.append(Sample("DSSlider__fill-steps", DSSlider(value: .constant(0.5), in: 0...1, step: 0.25).frame(width: 240)))
        s.append(Sample("DSSlider__gradient", DSSlider(
            value: .constant(0.35), in: 0...1,
            track: .gradient([Color(red: 0.3, green: 0.5, blue: 1), Color.white, Color(red: 1, green: 0.7, blue: 0.3)])
        ).frame(width: 240)))
        s.append(Sample("DSTextField__default", DSTextField(placeholder: "you@example.com", text: .constant("")).frame(width: 280)))
        s.append(Sample("DSTextField__label-filled", DSTextField(label: "E-mail", placeholder: "you@example.com", text: .constant("thierry@squareone.nl")).frame(width: 280)))
        s.append(Sample("DSTextField__icon", DSTextField(placeholder: "Search styles", icon: Image(systemName: "magnifyingglass"), text: .constant("")).frame(width: 280)))
        s.append(Sample("DSTextField__error", DSTextField(label: "E-mail", placeholder: "you@example.com", validation: .error, text: .constant("nope")).frame(width: 280)))
        s.append(Sample("DSTextField__success", DSTextField(label: "E-mail", placeholder: "you@example.com", validation: .success, text: .constant("thierry@squareone.nl")).frame(width: 280)))
        s.append(Sample("DSTextField__disabled", DSTextField(label: "E-mail", placeholder: "you@example.com", text: .constant("")).frame(width: 280).disabled(true)))
        s.append(Sample("DSSearchField__default", DSSearchField(text: .constant("")).frame(width: 224)))
        s.append(Sample("DSSearchField__filled", DSSearchField(text: .constant("Fren")).frame(width: 224)))
        s.append(Sample("DSOTPField__empty", DSOTPField(code: .constant(""))))
        s.append(Sample("DSOTPField__partial", DSOTPField(code: .constant("482"))))
        s.append(Sample("DSOTPField__error", DSOTPField(code: .constant("482910"), validation: .error)))
        s.append(Sample("DSColorPicker__default", DSColorPicker(color: .constant(Color(red: 0.84, green: 0.96, blue: 0.4)))))
        s.append(Sample("DSColorPicker__commit", DSColorPicker(
            color: .constant(Color(red: 0.2, green: 0.5, blue: 1)), commitTitle: "Apply", onCommit: {}
        )))
        s.append(Sample("DSInlineEditLabel__heading", DSInlineEditLabel("Untitled", text: .constant("Fren"))))
        s.append(Sample("DSInlineEditLabel__heading-placeholder", DSInlineEditLabel("Untitled", text: .constant(""))))
        s.append(Sample("DSInlineEditLabel__subtitle", DSInlineEditLabel("Role", text: .constant("Designer"), variant: .subtitle)))

        // Badges & chips
        s.append(Sample("DSBadge__neutral", DSBadge("Beta")))
        s.append(Sample("DSBadge__brand", DSBadge("New", type: .brand)))
        s.append(Sample("DSBadge__icon", DSBadge("Pro", icon: sparkle, type: .brand)))
        s.append(Sample("DSBadge__compact", DSBadge("2", compact: true)))
        s.append(Sample("DSChip__neutral", DSChip("Portrait", action: {})))
        s.append(Sample("DSChip__brand-icon", DSChip("Effects", icon: sparkle, type: .brand, action: {})))
        s.append(Sample("DSCreditBadge__default", DSCreditBadge("2")))
        s.append(Sample("DSQuotaBadge__default", DSQuotaBadge("3 left")))
        s.append(Sample("DSProChip__default", DSProChip()))
        s.append(Sample("DSProChip__credits", DSProChip("2 credits")))
        s.append(Sample("DSFeatureIndicator__pro", DSFeatureIndicator(.pro) {}))
        s.append(Sample("DSFeatureIndicator__cloudOff", DSFeatureIndicator(.cloudOff) {}))
        s.append(Sample("DSGated__locked", DSGated(isLocked: true, onUpgradeRequested: {}) { DSPrimaryButton("Whiten teeth") {} }))
        s.append(Sample("DSGated__unlocked", DSGated(isLocked: false, onUpgradeRequested: {}) { DSPrimaryButton("Whiten teeth") {} }))
        s.append(Sample("DSPrivacyBadge__onDevice", DSPrivacyBadge(tier: .onDevice)))
        s.append(Sample("DSPrivacyBadge__appleCloud", DSPrivacyBadge(tier: .appleCloud)))
        s.append(Sample("DSPrivacyBadge__thirdParty", DSPrivacyBadge(tier: .thirdParty)))
        s.append(Sample("DSSelectionCheckBadge__default", DSSelectionCheckBadge()))
        s.append(Sample("DSTooltip__bottom", DSTooltip("Zoom to Fit (⌘0)")))
        s.append(Sample("DSTooltip__top", DSTooltip("Undo", caretEdge: .top)))
        s.append(Sample("DSCanvasZoomChip__default", DSCanvasZoomChip(scale: 0.5, fitScale: 0.5, action: {})))
        s.append(Sample("DSCanvasZoomChip__zoomed", DSCanvasZoomChip(scale: 1.25, fitScale: 0.5, action: {})))

        // Icons
        for (name, symbol) in symbols {
            s.append(Sample("DSIcon__\(name)", DSIcon(symbol)))
        }
        s.append(Sample("DSIcon__sheet", VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(stride(from: 0, to: symbols.count, by: 8)), id: \.self) { start in
                HStack(spacing: 12) {
                    ForEach(symbols[start..<min(start + 8, symbols.count)], id: \.0) { _, sym in
                        DSIcon(sym).frame(width: 24, height: 24)
                    }
                }
            }
        }.padding(12)))

        // Lists, rows & cards
        s.append(Sample("DSSidebarRow__default", DSSidebarRow(name: "Fren", role: "Designer", action: {}) { avatarCircle() }.frame(width: 240)))
        s.append(Sample("DSSidebarRow__selected", DSSidebarRow(name: "Fren", role: "Designer", isSelected: true, action: {}) { avatarCircle() }.frame(width: 240)))
        s.append(Sample("DSSidebarRow__multiSelected", DSSidebarRow(name: "Fren", role: "Designer", isSelected: true, isMultiSelected: true, action: {}) { avatarCircle() }.frame(width: 240)))
        s.append(Sample("DSSidebarRow__noRole", DSSidebarRow(name: "Fren", action: {}) { avatarCircle() }.frame(width: 240)))
        s.append(Sample("DSThumbnailCard__default", DSThumbnailCard(label: "Watercolor") { DSIcon(.effects, size: 28) }))
        s.append(Sample("DSThumbnailCard__selected", DSThumbnailCard(label: "Watercolor", isSelected: true) { DSIcon(.effects, size: 28) }))
        s.append(Sample("DSThumbnailCard__pro", DSThumbnailCard(label: "Watercolor", isPro: true) { DSIcon(.effects, size: 28) }))
        s.append(Sample("DSThumbnailCard__working", DSThumbnailCard(label: "Watercolor", isWorking: true) { DSIcon(.effects, size: 28) }))
        s.append(Sample("DSThumbnailCard__refresh", DSThumbnailCard(label: "Watercolor", isSelected: true, onRefresh: {}) { DSIcon(.effects, size: 28) }))
        s.append(Sample("DSCanvasCard__plain", DSCanvasCard { Color.clear }.frame(width: 320, height: 200)))
        s.append(Sample("DSCanvasCard__dotGrid", DSCanvasCard(showsDotGrid: true) { Color.clear }.frame(width: 320, height: 200)))
        s.append(Sample("DSCanvasCard__dotGrid-dimmed", DSCanvasCard(showsDotGrid: true, dotGridDimmed: true) { Color.clear }.frame(width: 320, height: 200)))
        s.append(Sample("DSDotGrid__default", DSDotGrid().frame(width: 160, height: 100)))
        s.append(Sample("DSCardLabelScrim__default", ZStack(alignment: .bottomLeading) {
            DSColor.Background.neutralStrongest
            DSCardLabelScrim()
            Text("Fren").dsTextStyle(.labelBase).foregroundStyle(.white).padding(12)
        }.frame(width: 160, height: 200).clipShape(RoundedRectangle(cornerRadius: DSRadius.xl4))))
        s.append(Sample("DSPanelHeader__title", DSPanelHeader("Effects").frame(width: 320)))
        s.append(Sample("DSPanelHeader__subtitle", DSPanelHeader("Effects", subtitle: "Pick a style").frame(width: 320)))
        s.append(Sample("DSPanelHeader__leading", DSPanelHeader("Account", subtitle: "thierry@squareone.nl", alignment: .leading).frame(width: 320)))

        // Menus
        s.append(Sample("DSMenuRow__default", DSContextMenuPanel { DSMenuRow("Rename", icon: "pencil") {} }))
        s.append(Sample("DSMenuRow__shortcut", DSContextMenuPanel { DSMenuRow("Duplicate", icon: "plus.square.on.square", shortcut: "⌘D") {} }))
        s.append(Sample("DSMenuRow__chevron", DSContextMenuPanel { DSMenuRow("Apply effect", icon: "sparkles", showsChevron: true) {} }))
        s.append(Sample("DSMenuRow__destructive", DSContextMenuPanel { DSMenuRow("Delete", icon: "trash", destructive: true, shortcut: "⌫") {} }))
        s.append(Sample("DSMenuRow__disabled", DSContextMenuPanel { DSMenuRow("Paste", icon: "doc.on.clipboard", disabled: true) {} }))
        s.append(Sample("DSContextMenuPanel__menu", DSContextMenuPanel {
            DSMenuRow("Rename", icon: "pencil", shortcut: "↩") {}
            DSMenuRow("Duplicate", icon: "plus.square.on.square", shortcut: "⌘D") {}
            DSMenuRow("Apply effect", icon: "sparkles", showsChevron: true) {}
            DSMenuRow("Delete", icon: "trash", destructive: true, shortcut: "⌫") {}
        }))
        s.append(Sample("DSDropdownButton__closed", DSDropdownButton(isPresented: .constant(false)) {
            DSCapsuleToolButton(label: "Background", showChevron: true, action: {}) { DSIcon(.background) }
        } menu: { EmptyView() }))

        // Toolbars & panels
        s.append(Sample("DSBottomToolbar__regular", DSBottomToolbar(items: toolbarItems(), selection: .constant(1), overflow: overflowItems())))
        s.append(Sample("DSBottomToolbar__noSelection", DSBottomToolbar(items: toolbarItems(), selection: .constant(nil), overflow: overflowItems())))
        s.append(Sample("DSBottomToolbar__disabled", DSBottomToolbar(items: toolbarItems(), selection: .constant(nil), overflow: overflowItems(), toolsEnabled: false)))
        s.append(Sample("DSBottomToolbar__accessory", DSBottomToolbar(items: toolbarItems(), selection: .constant(0), overflow: overflowItems()) {
            DSCapsuleToolButton(action: {}) { DSIcon(.undo) }
            DSCapsuleToolButton(action: {}) { DSIcon(.redo) }
        }))
        s.append(Sample("DSEditPanel__default", DSEditPanel(title: "Effects", subtitle: "Pick a style") {
            HStack(spacing: 12) {
                DSThumbnailCard(label: "Watercolor", isSelected: true) { DSIcon(.effects, size: 28) }
                DSThumbnailCard(label: "Pixel", isPro: true) { DSIcon(.grid, size: 28) }
                DSThumbnailCard(label: "Sketch") { DSIcon(.edit, size: 28) }
            }
        }))
        s.append(Sample("DSEditPanel__credits-accessory", DSEditPanel(title: "Face", credits: "2", headerAccessory: { DSProChip() }) {
            HStack(spacing: 12) {
                DSPrimaryButton("Whiten teeth", icon: sparkle) {}
                DSNeutralButton("Makeup") {}
            }
        }))
        s.append(Sample("DSDialog__default", DSDialog(title: "Delete portrait?", confirmLabel: "Delete", onConfirm: {}, onDismiss: {}) {
            Text("This can't be undone.").dsTextStyle(.bodySmall).foregroundStyle(DSColor.Foreground.muted)
        }))
        s.append(Sample("DSDialog__confirmDisabled", DSDialog(title: "Rename", confirmLabel: "Save", confirmEnabled: false, onConfirm: {}, onDismiss: {}) {
            DSTextField(placeholder: "Name", text: .constant("")).frame(width: 280)
        }))
        s.append(Sample("DSMessageSheet__default", DSMessageSheet(title: "Welcome to Aaavatar 2.0", body: "Effects 2.0 is here: pick any style and we'll keep your face intact.", ctaLabel: "Try it")))
        s.append(Sample("DSMessageSheet__noCTA", DSMessageSheet(title: "Maintenance", body: "Cloud effects are paused for an hour.")))
        s.append(Sample("DSMessageBanner__default", DSMessageBanner(title: "New effects", body: "Three new styles landed this week.", hasCTA: true).frame(width: 360)))
        s.append(Sample("DSMessageBanner__noCTA", DSMessageBanner(title: "Heads up", body: "Cloud effects are paused.").frame(width: 360)))

        // Toasts
        s.append(Sample("DSToast__title", DSToast(title: "Exported")))
        s.append(Sample("DSToast__description", DSToast(title: "Exported", description: "Saved to Desktop", onClose: {})))
        s.append(Sample("DSToast__progress", DSToast(title: "Removing background", progress: 0.4)))
        s.append(Sample("DSToast__loading", DSToast(title: "Applying effect", isLoading: true)))
        s.append(Sample("DSToast__action", DSToast(title: "Portrait deleted", onClose: {}, action: DSToastAction("Undo") {})))

        return s
    }
}
