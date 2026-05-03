import SwiftUI

/// Sidebar banner shown after a pre-auth checkout: this Mac is Pro because
/// of a `device_grants` row, but no Supabase session is signed in yet. Tap
/// the CTA to send a Supabase magic-link to the email Stripe captured. The
/// link deep-links back to the app and signs the user in — at which point
/// Pro is account-scoped and syncs to other Macs that share the same
/// auth user.
///
/// Visibility: only shown when `proEntitlement.needsAccountLink == true`.
/// Hidden once `auth.isSignedIn` flips, since the user has done the link
/// step (the device-grant row is harmless residue at that point).
struct SyncAcrossDevicesBanner: View {
    @Environment(AppState.self) private var appState

    @State private var sending: Bool = false
    @State private var feedback: Feedback?

    private enum Feedback: Equatable {
        case success(email: String)
        case failure
    }

    private var brand: Color { .appBrand }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(brand)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(brand.opacity(0.14)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(Loc.syncBannerTitle)
                        .font(.system(size: 12, weight: .semibold))
                    if let email = appState.proEntitlement.linkEmail {
                        Text(Loc.syncBannerBody(email: email))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }

            Button {
                Task { await sendLink() }
            } label: {
                HStack(spacing: 6) {
                    if sending {
                        ProgressView().controlSize(.mini)
                    }
                    Text(Loc.syncBannerSendLink)
                        .font(.system(size: 12, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(brand.opacity(0.16))
                )
                .contentShape(Capsule())
            }
            .buttonStyle(PressableButtonStyle(pressedScale: 0.97))
            .disabled(sending)
            .foregroundStyle(brand)

            if let feedback {
                feedbackChip(feedback)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(brand.opacity(0.18))
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
        .animation(.easeOut(duration: 0.18), value: feedback)
    }

    @ViewBuilder
    private func feedbackChip(_ feedback: Feedback) -> some View {
        switch feedback {
        case .success(let email):
            Text(Loc.syncBannerLinkSent(email: email))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        case .failure:
            Text(Loc.syncBannerSendFailed)
                .font(.system(size: 11))
                .foregroundStyle(Color.appDangerInk)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func sendLink() async {
        if sending { return }
        sending = true
        defer { sending = false }
        do {
            let email = try await appState.backend.resendMagicLink()
            feedback = .success(email: email ?? appState.proEntitlement.linkEmail ?? "")
        } catch {
            feedback = .failure
        }
    }
}
