import SceneKit
import SwiftUI

/// SwiftUI wrapper around the SceneKit headset.
struct HeadphonesSceneView: NSViewRepresentable {
    var target: HeadphonesSceneController.Target
    var isActive: Bool
    /// Increment to make the headset hop (EQ preset change, etc.).
    var nudge: Int
    var onTap: () -> Void

    @MainActor
    final class Coordinator {
        let controller = HeadphonesSceneController()
        var lastNudge = 0
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> SCNView {
        let controller = context.coordinator.controller
        controller.onTap = onTap
        controller.update(target)
        context.coordinator.lastNudge = nudge
        return controller.view
    }

    func updateNSView(_ view: SCNView, context: Context) {
        let coordinator = context.coordinator
        coordinator.controller.onTap = onTap
        coordinator.controller.update(target)
        if view.isPlaying != isActive { coordinator.controller.setActive(isActive) }
        if nudge != coordinator.lastNudge {
            coordinator.lastNudge = nudge
            coordinator.controller.nudge()
        }
    }
}
