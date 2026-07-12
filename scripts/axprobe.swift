// AX-probe voor E53.3: walk de AX-boom van de smoke-instance en rapporteer
// of de portret-kaarten als button-elementen met naam+rol-label bestaan,
// inclusief hun custom actions. Geen screenshots — puur de AX-API.
import AppKit
import ApplicationServices

guard CommandLine.arguments.count > 1, let pidArg = Int32(CommandLine.arguments[1]) else {
    print("usage: axprobe <pid>"); exit(2)
}
guard AXIsProcessTrusted() else {
    print("AX-NOT-TRUSTED"); exit(3)
}

let appEl = AXUIElementCreateApplication(pidArg)

func attr(_ el: AXUIElement, _ name: String) -> CFTypeRef? {
    var v: CFTypeRef?
    return AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success ? v : nil
}

func children(_ el: AXUIElement) -> [AXUIElement] {
    (attr(el, kAXChildrenAttribute) as? [AXUIElement]) ?? []
}

var hits: [String] = []
var visited = 0

func walk(_ el: AXUIElement, depth: Int) {
    if depth > 40 || visited > 20000 { return }
    visited += 1
    let role = (attr(el, kAXRoleAttribute) as? String) ?? ""
    let title = (attr(el, kAXTitleAttribute) as? String) ?? ""
    let desc = (attr(el, kAXDescriptionAttribute) as? String) ?? ""
    let label = title.isEmpty ? desc : title
    if !label.isEmpty && (label.contains("Bennett") || label.contains("Carter") ||
        label.contains("Diaz") || label.contains("Previous portrait") ||
        label.contains("Next portrait")) {
        var actionNames: CFArray?
        AXUIElementCopyActionNames(el, &actionNames)
        let actions = (actionNames as? [String]) ?? []
        hits.append("\(role) | \(label) | actions: \(actions.joined(separator: ","))")
    }
    for c in children(el) { walk(c, depth: depth + 1) }
}

walk(appEl, depth: 0)
print("visited=\(visited)")
if hits.isEmpty {
    print("NO-CARD-AX-ELEMENTS-FOUND")
    exit(1)
}
for h in Set(hits).sorted() { print(h) }
