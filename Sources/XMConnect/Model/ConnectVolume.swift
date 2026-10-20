import CoreAudio
import Foundation

/// Sets the Mac's output volume for the headphones each time they connect, because macOS often
/// brings them back far too quiet.
///
/// The trigger is the headset's Bluetooth audio output appearing in CoreAudio, not the MDR control
/// channel, so it works even before (or without) the control session. A device that is already
/// there at launch is left alone: only a fresh connection is a "connect".
@MainActor
final class ConnectVolume {
    private let settings: AppSettings
    private var present: Set<String> = []
    private var pending: [String: Task<Void, Never>] = [:]
    private var listener: AudioObjectPropertyListenerBlock?

    private static var devicesAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)

    init(settings: AppSettings) {
        self.settings = settings
    }

    func start() {
        guard listener == nil else { return }
        present = Set(Self.headsetOutputs().map(\.uid))
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in self?.devicesChanged() }
        }
        listener = block
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &Self.devicesAddress, .main, block)
        if status != noErr { Log.info("Volume on connect: listener failed (\(status))") }
    }

    /// Applies the chosen level to every connected Sony headset output right now.
    func applyNow() {
        for device in Self.headsetOutputs() {
            Self.setVolume(Float(settings.connectVolume), on: device.id)
        }
    }

    private func devicesChanged() {
        let outputs = Self.headsetOutputs()
        let uids = Set(outputs.map(\.uid))
        for device in outputs where !present.contains(device.uid) {
            Log.info("Headset audio output appeared: \(device.name)")
            if settings.volumeOnConnect { schedule(device) }
        }
        for gone in present.subtracting(uids) {
            pending[gone]?.cancel()
            pending[gone] = nil
        }
        present = uids
    }

    /// macOS restores its own remembered volume a while after the link comes up (sometimes
    /// several seconds later), so set the level once the output settles and again at about 3,
    /// 6 and 10 seconds. The sleeps are cumulative.
    private func schedule(_ device: (id: AudioObjectID, uid: String, name: String)) {
        pending[device.uid]?.cancel()
        pending[device.uid] = Task { [weak self] in
            for delay in [700_000_000, 2_500_000_000, 3_000_000_000, 4_000_000_000] as [UInt64] {
                try? await Task.sleep(nanoseconds: delay)
                guard let self, !Task.isCancelled, self.settings.volumeOnConnect else { return }
                // The device id can change while the route settles; look it up again by UID.
                guard let current = Self.headsetOutputs().first(where: { $0.uid == device.uid }) else { return }
                let target = Float(self.settings.connectVolume)
                if let before = Self.volume(of: current.id), abs(before - target) < 0.01 { continue }
                Self.setVolume(target, on: current.id)
            }
            self?.pending[device.uid] = nil
        }
    }

    // MARK: - CoreAudio

    /// Bluetooth output devices that belong to a Sony headset.
    private static func headsetOutputs() -> [(id: AudioObjectID, uid: String, name: String)] {
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &devicesAddress, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &devicesAddress, 0, nil, &size, &ids) == noErr else { return [] }

        return ids.compactMap { id in
            guard transportType(id) == kAudioDeviceTransportTypeBluetooth, hasOutput(id),
                  let uid = string(id, kAudioDevicePropertyDeviceUID) else { return nil }
            let name = string(id, kAudioObjectPropertyName) ?? ""
            // Bluetooth UIDs look like "88-C9-E8-DD-47-9F:output".
            let address = String(uid.prefix { $0 != ":" })
            guard DeviceSelection.mayBeSony(name) || RFCOMMClient.isSonyHeadset(address: address) else { return nil }
            return (id, uid, name)
        }
    }

    /// The first readable volume (main element, else channel 1).
    private static func volume(of device: AudioObjectID) -> Float? {
        for element in [kAudioObjectPropertyElementMain, 1] as [UInt32] {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: element)
            var value: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectHasProperty(device, &address),
               AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr {
                return value
            }
        }
        return nil
    }

    private static func setVolume(_ level: Float, on device: AudioObjectID) {
        let value = min(max(level, 0), 1)
        let before = volume(of: device).map { "\(Int(($0 * 100).rounded())) % → " } ?? ""
        // Some devices expose one main volume, others (the XM4 among them) one per channel.
        var applied = false
        for element in [kAudioObjectPropertyElementMain, 1, 2] as [UInt32] {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: element)
            var settable: DarwinBoolean = false
            guard AudioObjectHasProperty(device, &address),
                  AudioObjectIsPropertySettable(device, &address, &settable) == noErr, settable.boolValue
            else { continue }
            var v = value
            if AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &v) == noErr {
                applied = true
                if element == kAudioObjectPropertyElementMain { break }
            }
        }
        Log.info("Volume on connect: \(before)\(Int((value * 100).rounded())) %\(applied ? "" : " (not settable)")")
    }

    private static func transportType(_ id: AudioObjectID) -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr ? value : 0
    }

    private static func hasOutput(_ id: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr && size > 0
    }

    private static func string(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr,
              let value else { return nil }
        return value.takeRetainedValue() as String
    }
}
