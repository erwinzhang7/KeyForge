import SwiftUI

/// Curated SF Symbol grid for picking a macro icon.
public struct IconPickerView: View {
    @Binding public var selection: String
    @Environment(\.dismiss) private var dismiss
    @State private var search: String = ""

    public init(selection: Binding<String>) { self._selection = selection }

    private let symbols: [String] = [
        "bolt.fill", "bolt", "wand.and.stars", "sparkles",
        "command", "keyboard", "keyboard.fill",
        "terminal", "terminal.fill", "applescript",
        "app.badge", "app.fill", "rectangle.stack", "rectangle.stack.fill",
        "doc", "doc.fill", "folder", "folder.fill", "tray", "tray.full",
        "link", "globe", "safari", "envelope", "envelope.fill",
        "text.cursor", "text.bubble", "quote.bubble", "character.cursor.ibeam",
        "play.fill", "pause.fill", "forward.fill", "backward.fill",
        "speaker.wave.2.fill", "speaker.slash.fill", "music.note",
        "bell", "bell.fill", "exclamationmark.triangle",
        "clock", "clock.fill", "timer", "hourglass",
        "gear", "gearshape", "wrench.and.screwdriver",
        "questionmark.diamond", "checkmark.circle", "xmark.circle",
        "star", "star.fill", "heart", "heart.fill", "flag", "flag.fill",
        "lock", "lock.open", "key", "key.fill",
        "moon", "moon.fill", "sun.max", "cloud", "cloud.bolt",
        "laptopcomputer", "desktopcomputer", "iphone", "ipad",
        "hammer", "screwdriver", "paintbrush", "paintpalette",
        "magnifyingglass", "scope", "eye", "eye.slash",
        "arrow.up", "arrow.down", "arrow.left", "arrow.right",
        "arrow.up.right.square", "arrow.uturn.backward", "arrow.uturn.forward",
        "camera", "photo", "video", "mic", "mic.slash",
        "person", "person.fill", "person.2.fill", "person.crop.circle"
    ]

    private var filtered: [String] {
        guard !search.isEmpty else { return symbols }
        return symbols.filter { $0.localizedCaseInsensitiveContains(search) }
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search symbols", text: $search)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            Divider()
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(36), spacing: 4), count: 7), spacing: 4) {
                    ForEach(filtered, id: \.self) { sym in
                        Button {
                            selection = sym
                            dismiss()
                        } label: {
                            Image(systemName: sym)
                                .font(.system(size: 16))
                                .frame(width: 32, height: 32)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(sym == selection ? Color.accentColor.opacity(0.25) : Color.clear)
                                )
                                .foregroundStyle(sym == selection ? Color.accentColor : Color.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
            }
        }
        .frame(width: 296, height: 320)
    }
}
