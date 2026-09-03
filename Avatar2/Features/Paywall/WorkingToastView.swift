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
                    DSProgressView()
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
                // eerlijke tijdsindicatie — resterende tijd in gewone taal
                // ("About 30 seconds left") + een balk richting de verwachte
                // duur (cap 92%: nooit "vol" beloven terwijl het model nog
                // rekent) — plus optioneel Cancel. Besluit Thierry 2026-08-03:
                // kwaliteit blijft high; de wachttijd wordt draaglijk via
                // feedback, niet via een lager kwaliteitstier. Besluit Thierry
                // 2026-09-03: geen "0:53 · usually ~1 min" meer — de klok
                // blijft alleen zonder verwachting (Cancel-only acties).
                if context.expectedSeconds != nil || onCancel != nil {
                    TimelineView(.periodic(from: context.startedAt, by: 1)) { timeline in
                        let elapsed = max(0, Int(timeline.date.timeIntervalSince(context.startedAt)))
                        VStack(alignment: .leading, spacing: DSSpacing.gap2) {
                            if let expected = context.expectedSeconds {
                                DSProgressView(value: min(Double(elapsed) / Double(expected), 0.92))
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
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.xl2))
        .overlay(
            RoundedRectangle(cornerRadius: DSRadius.xl2)
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

    /// Zonder verwachting een kale klok ("0:12"); mét verwachting de
    /// resterende tijd in gewone taal ("About 30 seconds left", "About 1
    /// minute left") en voorbij de verwachting "Taking a bit longer than
    /// usual…". Seconden ronden op 5 af (omhoog) zodat het niet zenuwachtig
    /// aftelt; vanaf een minuut op hele minuten. Intern (geen private) zodat
    /// de unit test de randen (0s, >expected, afronding) kan dekken zonder
    /// de view te hosten.
    static func elapsedLabel(_ elapsed: Int, expected: Int?) -> String {
        guard let expected else {
            return String(format: "%d:%02d", elapsed / 60, elapsed % 60)
        }
        let remaining = expected - elapsed
        guard remaining > 0 else { return "Taking a bit longer than usual…" }
        let seconds = Int((Double(remaining) / 5).rounded(.up)) * 5
        if seconds >= 60 {
            let minutes = max(1, Int((Double(seconds) / 60).rounded()))
            return minutes == 1 ? "About 1 minute left" : "About \(minutes) minutes left"
        }
        return "About \(seconds) seconds left"
    }
}
