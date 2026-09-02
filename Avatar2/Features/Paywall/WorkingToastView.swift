// Lopende-actie-toast met cycling copy per feature. Repliceert de DSToast-
// kaartchrome handmatig zodat uitsluitend de description-Text een
// ticker-tape-transitie krijgt (het kaartframe blijft stabiel).
// Patroon overgenomen uit v1 ProcessingStatusView: index-gebaseerd,
// variabele dwell-tijden zodat punchlines langer hangen.

import AvatarUI
import SwiftUI

struct WorkingToastView: View {
    let context: EntitlementModel.WorkingContext
    /// E55.9: optionele Cancel-actie (Effects detacht de generatie — resultaat
    /// landt stil in de kaart-cache). nil = geen knop (korte acties).
    var onCancel: (() -> Void)? = nil
    var onClose: (() -> Void)? = nil

    @State private var index = 0

    // Variabele dwell — punchlines (hogere waarden) en korte berichten
    // wisselen af zodat de lus niet mechanisch aanvoelt.
    private static let dwellTimes: [TimeInterval] = [
        2.4, 2.2, 3.0, 2.6, 3.4, 2.4, 2.8, 3.2,
    ]

    private var currentDwell: TimeInterval {
        Self.dwellTimes[index % Self.dwellTimes.count]
    }

    private var currentMessage: String {
        let msgs = context.messages
        guard !msgs.isEmpty else { return "" }
        return msgs[index % msgs.count]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: DSSpacing.gap1) {
                // Titel-rij: spinner + statische titel + sluitknop.
                HStack(alignment: .top, spacing: 0) {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.trailing, DSSpacing.gap2)
                        .padding(.top, 1)
                    Text(context.title)
                        .dsTextStyle(.labelLarge)
                        .foregroundStyle(DSColor.Foreground.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let onClose {
                        DSIconButton(
                            Image(systemName: "xmark"),
                            label: "Dismiss",
                            style: .ghostNeutral,
                            size: .small,
                            action: onClose
                        )
                    }
                }

                // Cycling description: .id(index) laat SwiftUI de Text als
                // een nieuw view zien → de transitie vuurt. Kale crossfade i.p.v.
                // offset(y:±5): die liet de tekst elke cyclus verticaal schuifelen
                // (de "stagger" die buggy oogde). Eén opacity-fade leest rustig.
                Text(currentMessage)
                    .dsTextStyle(.bodySmall)
                    .foregroundStyle(DSColor.Foreground.subtle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .id(index)
                    .transition(.opacity)

                // E55.9: bij lange generaties (expectedSeconds gezet) een
                // eerlijke tijdsindicatie — verstreken tijd + een balk richting
                // de verwachte duur (cap 92%: nooit "vol" beloven terwijl het
                // model nog rekent) — plus optioneel Cancel. Besluit Thierry
                // 2026-08-03: kwaliteit blijft high; de wachttijd wordt
                // draaglijk via feedback, niet via een lager kwaliteitstier.
                if context.expectedSeconds != nil || onCancel != nil {
                    TimelineView(.periodic(from: context.startedAt, by: 1)) { timeline in
                        let elapsed = max(0, Int(timeline.date.timeIntervalSince(context.startedAt)))
                        VStack(alignment: .leading, spacing: DSSpacing.gap2) {
                            if let expected = context.expectedSeconds {
                                ProgressView(value: min(Double(elapsed) / Double(expected), 0.92))
                                    .progressViewStyle(.linear)
                                    .controlSize(.small)
                                    .tint(DSColor.Foreground.subtle)
                            }
                            HStack(spacing: DSSpacing.gap2) {
                                Text(Self.elapsedLabel(elapsed, expected: context.expectedSeconds))
                                    .dsTextStyle(.labelSmall)
                                    .foregroundStyle(DSColor.Foreground.muted)
                                    .monospacedDigit()
                                Spacer(minLength: 0)
                                if let onCancel {
                                    DSGhostButton("Cancel", size: .small, action: onCancel)
                                        .help(context.cancelHint ?? "Cancel")
                                }
                            }
                        }
                        .padding(.top, DSSpacing.gap2)
                    }
                }
            }
            .padding(DSSpacing.gap4)
        }
        .frame(width: 360)
        .background(DSColor.Background.card)
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: DSRadius.lg)
                .strokeBorder(DSColor.Foreground.divider, lineWidth: DSBorderWidth.thin)
        )
        .shadow(
            color: DSShadow.default.color,
            radius: DSShadow.default.radius / 2,
            x: DSShadow.default.offset.width,
            y: DSShadow.default.offset.height / 2
        )
        .task(id: index) {
            let nanos = UInt64(currentDwell * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
            guard !Task.isCancelled else { return }
            DSMotion.animate(DSMotion.base) { index += 1 }
        }
    }

    /// "0:12" en, mét verwachting, "0:12 · usually ~1 min". Intern (geen
    /// private) zodat de unit test de randen (0s, >expected, minuut-afronding)
    /// kan dekken zonder de view te hosten.
    static func elapsedLabel(_ elapsed: Int, expected: Int?) -> String {
        let stamp = String(format: "%d:%02d", elapsed / 60, elapsed % 60)
        guard let expected else { return stamp }
        let hint: String
        if expected >= 60 {
            let minutes = Int((Double(expected) / 60).rounded())
            hint = minutes <= 1 ? "usually ~1 min" : "usually ~\(minutes) min"
        } else {
            hint = "usually ~\(expected)s"
        }
        // Voorbij de verwachting geen "usually" meer beloven — dan is
        // "nog bezig" het eerlijke verhaal.
        return elapsed <= expected ? "\(stamp) · \(hint)" : "\(stamp) · still working…"
    }
}
