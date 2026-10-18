import AppKit
import SceneKit

/// Main-thread side of the 3D headset: owns the SCNView and its gestures, and forwards
/// everything to the `SceneEngine`, which renders on SceneKit's thread.
@MainActor
final class HeadphonesSceneController: NSObject {
    typealias Target = SceneEngine.Target

    let view: SCNView
    var onTap: (() -> Void)?
    private let engine = SceneEngine()

    override init() {
        view = SCNView(frame: NSRect(x: 0, y: 0, width: 372, height: 214), options: nil)
        super.init()

        view.scene = engine.scene
        view.delegate = engine
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 60
        view.autoenablesDefaultLighting = false
        view.allowsCameraControl = false
        view.isPlaying = true
        view.rendersContinuously = true

        view.addGestureRecognizer(NSPanGestureRecognizer(target: self, action: #selector(handlePan(_:))))
        view.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(handleClick(_:))))
    }

    func update(_ target: Target) { engine.update(target) }
    func nudge() { engine.nudge() }

    /// Stop rendering while the panel is hidden, to save battery.
    func setActive(_ active: Bool) {
        view.isPlaying = active
        view.rendersContinuously = active
    }

    @objc private func handlePan(_ gesture: NSPanGestureRecognizer) {
        let translation = gesture.translation(in: view)
        switch gesture.state {
        case .began:
            engine.beginDrag()
        case .changed:
            engine.moveDrag(dx: translation.x, dy: translation.y)
        case .ended, .cancelled, .failed:
            engine.endDrag(velocityX: gesture.velocity(in: view).x)
        default:
            break
        }
    }

    @objc private func handleClick(_ gesture: NSClickGestureRecognizer) {
        engine.nudge()
        onTap?()
    }
}
