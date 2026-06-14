import SwiftUI

/// Drop-in replacement for EmptyStateView (macOS 14+) that works on macOS 13.
/// Use it everywhere instead of the stdlib type so the app builds against the deployment target.
public struct EmptyStateView: View {
    let title: String
    let systemImage: String
    let description: String?

    public init(_ title: String, systemImage: String, description: String? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.description = description
    }

    public var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title3)
                .foregroundStyle(.secondary)
            if let description = description {
                Text(description)
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
