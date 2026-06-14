import Foundation

/// Dynamic loading of MediaRemote private framework for media key control.
/// We intentionally avoid linking against private APIs at compile time; instead
/// we dlopen the framework and dlsym the function pointer at runtime.
/// If the framework is unavailable (newer macOS, M-series only, etc.), the
/// `send` call becomes a no-op and the caller falls back to NX system-defined
/// events.
public enum MediaRemote {
    public enum Command: UInt32 {
        case play = 0
        case pause = 1
        case togglePlayPause = 2
        case stop = 3
        case nextTrack = 4
        case previousTrack = 5
    }

    private typealias MRMediaRemoteSendCommand = @convention(c) (UInt32, AnyObject?) -> Void

    private static let sendCommandFn: MRMediaRemoteSendCommand? = {
        guard let handle = dlopen(
            "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote",
            RTLD_NOW
        ) else {
            return nil
        }
        guard let sym = dlsym(handle, "MRMediaRemoteSendCommand") else {
            return nil
        }
        return unsafeBitCast(sym, to: MRMediaRemoteSendCommand.self)
    }()

    /// Returns true if the underlying framework + symbol could be resolved.
    public static var isAvailable: Bool { sendCommandFn != nil }

    /// Send a media remote command. Returns false if the symbol is unavailable.
    @discardableResult
    public static func send(_ command: Command) -> Bool {
        guard let fn = sendCommandFn else { return false }
        fn(command.rawValue, nil)
        return true
    }
}
