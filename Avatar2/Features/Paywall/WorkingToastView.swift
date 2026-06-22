// Lopende-actie-toast met cycling copy per feature. Repliceert de DSToast-
// kaartchrome handmatig zodat uitsluitend de description-Text een
// ticker-tape-transitie krijgt (het kaartframe blijft stabiel).
// Patroon overgenomen uit v1 ProcessingStatusView: index-gebaseerd,
// variabele dwell-tijden zodat punchlines langer hangen.

import AvatarUI
import SwiftUI

struct WorkingToastView: View {
    let context: EntitlementModel.WorkingContext
    let onClose: () -> Void

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
                    DSIconButton(
                        Image(systemName: "xmark"),
                        style: .ghostNeutral,
                        size: .small,
                        action: onClose
                    )
                }

                // Cycling description: .id(index) laat SwiftUI de Text als
                // een nieuw view zien → de asymmetrische transitie vurt.
                // Oud bericht schuift omhoog weg, nieuw schuift van onder in.
                Text(currentMessage)
                    .dsTextStyle(.bodySmall)
                    .foregroundStyle(DSColor.Foreground.subtle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .id(index)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(y: 5)),
                        removal:   .opacity.combined(with: .offset(y: -5))
                    ))
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
            withAnimation(.easeOut(duration: 0.25)) { index += 1 }
        }
    }
}
