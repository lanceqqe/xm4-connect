import Foundation

/// Pauses and resumes whatever is playing on the Mac (Music, Spotify, a browser…).
///
/// Uses MediaRemote's `MRMediaRemoteSendCommand`, the same entry point as the media keys.
/// Unlike the play/pause key it sends an explicit pause or play, so it never starts
/// playback by accident. MediaRemote is a private framework, so it is loaded at runtime and
/// everything degrades to a no-op if it is unavailable.
enum MediaControl {
    private typealias SendCommand = @convention(c) (UInt32, CFDictionary?) -> Bool

    private static let kMRPlay: UInt32 = 0
    private static let kMRPause: UInt32 = 1

    nonisolated(unsafe) private static let sendCommand: SendCommand? = {
        let path = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
        guard let handle = dlopen(path, RTLD_LAZY),
              let symbol = dlsym(handle, "MRMediaRemoteSendCommand") else {
            Log.info("MediaRemote unavailable; pause on removal will rely on the headset alone")
            return nil
        }
        return unsafeBitCast(symbol, to: SendCommand.self)
    }()

    @discardableResult
    static func pause() -> Bool {
        let ok = sendCommand?(kMRPause, nil) ?? false
        Log.info("Media pause sent (\(ok))")
        return ok
    }

    @discardableResult
    static func play() -> Bool {
        let ok = sendCommand?(kMRPlay, nil) ?? false
        Log.info("Media play sent (\(ok))")
        return ok
    }
}
