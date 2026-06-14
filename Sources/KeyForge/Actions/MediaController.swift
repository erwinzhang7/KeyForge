import Foundation
import AppKit
import CoreGraphics
import IOKit
import IOKit.hidsystem

/// Sends media-key commands via the MediaRemote private framework when available;
/// falls back to NX_SYSDEFINED key events (the same events the keyboard sends when
/// you press the play/pause key) otherwise.
public enum MediaController {

    public static func perform(_ action: MediaAction) {
        switch action {
        case .playPause:
            if MediaRemote.send(.togglePlayPause) { return }
            postSystemDefined(key: NX_KEYTYPE_PLAY)
        case .next:
            if MediaRemote.send(.nextTrack) { return }
            postSystemDefined(key: NX_KEYTYPE_NEXT)
        case .previous:
            if MediaRemote.send(.previousTrack) { return }
            postSystemDefined(key: NX_KEYTYPE_PREVIOUS)
        case .volumeUp:
            postSystemDefined(key: NX_KEYTYPE_SOUND_UP)
        case .volumeDown:
            postSystemDefined(key: NX_KEYTYPE_SOUND_DOWN)
        case .mute:
            postSystemDefined(key: NX_KEYTYPE_MUTE)
        }
    }

    /// Posts a system-defined NX event for a special key (volume, brightness, media).
    /// macOS handles these the same way it would a real hardware press.
    private static func postSystemDefined(key: Int32) {
        for isDown in [true, false] {
            let flags = NSEvent.ModifierFlags(rawValue: (isDown ? 0xA00 : 0xB00))
            let data1 = Int((Int(key) << 16) | ((isDown ? 0xA : 0xB) << 8))
            guard let event = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: flags,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 8,
                data1: data1,
                data2: -1
            ) else { continue }
            event.cgEvent?.post(tap: .cghidEventTap)
        }
    }
}
