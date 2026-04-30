import SwiftUI

/// Official multicolor Google "G" mark, loaded from `Assets.xcassets` as a
/// vector SVG so it stays crisp at every size and exactly matches Google's
/// brand artwork (no hand-drawn approximation).
struct GoogleGMark: View {
    var size: CGFloat = 18

    var body: some View {
        Image("GoogleGLogo")
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

#Preview {
    HStack(spacing: 24) {
        GoogleGMark(size: 18)
        GoogleGMark(size: 32)
        GoogleGMark(size: 64)
    }
    .padding(40)
    .background(Color.black)
}
