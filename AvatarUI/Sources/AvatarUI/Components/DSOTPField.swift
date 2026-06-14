// Figma "Components" → One-Time Password (OTP) (60:798), zoals in
// Onboarding / OTP (dark). Rij met gap-1.5 en in het midden een streepje
// (8×2, r-sm, divider). Cel: cijferkolom 20 breed (Content/Body/Small,
// gecentreerd), px gap-3.5, py gap-5, bg background/neutral, r-lg, rand
// b-thin — divider in rust, muted op de actieve cel (State=Active);
// placeholder-cijfer muted, ingevoerd cijfer primary. De invoer loopt via
// één verborgen tekstveld; tikken op de rij focust dat veld.

import SwiftUI

public struct DSOTPField: View {
    private let length: Int
    private let validation: DSValidationState
    @Binding private var code: String
    @FocusState private var isFocused: Bool

    public init(code: Binding<String>, length: Int = 6, validation: DSValidationState = .normal) {
        self._code = code
        self.length = length
        self.validation = validation
    }

    public var body: some View {
        HStack(spacing: DSSpacing.gap1_5) {
            ForEach(0..<length, id: \.self) { index in
                if index == length / 2 {
                    RoundedRectangle(cornerRadius: DSRadius.sm)
                        .fill(DSColor.Foreground.divider)
                        .frame(width: 8, height: 2)
                }
                cell(at: index)
            }
        }
        .background {
            TextField("", text: $code)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .opacity(DSOpacity.hidden)
                .onChange(of: code) { _, newValue in
                    code = String(newValue.filter(\.isNumber).prefix(length))
                }
        }
        .contentShape(Rectangle())
        .onTapGesture { isFocused = true }
        .accessibilityLabel(Text("One-time password"))
        .animation(.easeOut(duration: 0.15), value: validation)
    }

    private func cell(at index: Int) -> some View {
        let digits = Array(code)
        let isFilled = index < digits.count
        let isActive = isFocused && index == min(digits.count, length - 1)
        return Text(isFilled ? String(digits[index]) : String(index + 1))
            .dsTextStyle(.bodySmall)
            .foregroundStyle(isFilled ? DSColor.Foreground.primary : DSColor.Foreground.muted)
            .frame(width: 20)
            .padding(.horizontal, DSSpacing.gap3_5)
            .padding(.vertical, DSSpacing.gap5)
            .background(DSColor.Background.neutral, in: RoundedRectangle(cornerRadius: DSRadius.lg))
            .overlay {
                RoundedRectangle(cornerRadius: DSRadius.lg).strokeBorder(
                    cellBorderColor(isActive: isActive),
                    lineWidth: validation == .normal ? DSBorderWidth.thin : DSBorderWidth.medium
                )
            }
    }

    private func cellBorderColor(isActive: Bool) -> Color {
        switch validation {
        case .error: return DSColor.Signal.error
        case .success: return DSColor.Signal.success
        case .normal: return isActive ? DSColor.Foreground.muted : DSColor.Foreground.divider
        }
    }
}
