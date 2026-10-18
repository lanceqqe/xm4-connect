import AppKit
import SceneKit
import simd

/// Owns the 3D scene: the headset, its "noise shield", the sound particles and rings, and the
/// spring physics that make it turn, wobble and float.
///
/// Everything animated is driven from one per-frame update on SceneKit's render thread, with
/// smoothed values easing toward a target the UI sets. The UI only ever writes that target
/// (under a lock), so a mode change is a gentle morph rather than a jump. This class touches no
/// AppKit views; `HeadphonesSceneController` owns the view and forwards gestures here.
final class SceneEngine: NSObject, SCNSceneRendererDelegate, @unchecked Sendable {
    struct Target: Equatable {
        var look: ListeningLook = .disconnected
        /// Ambient level, 0…1.
        var level: Float = 0.7
        var focusOnVoice = false
        var finish: HeadsetFinish = .black
        var reduceMotion = false
    }

    // MARK: Shared with the main thread (guarded by `lock`)

    private let lock = NSLock()
    private var target = Target()
    private var pendingSpins = 0
    private var pendingBounce = false
    private var dragging = false
    private var dragYaw: Float = 0
    private var dragPitch: Float = 0
    private var releaseVelocity: Float?
    private var publishedYaw: Float = 0
    private var publishedPitch: Float = 0
    private var dragStartYaw: Float = 0
    private var dragStartPitch: Float = 0

    // MARK: Scene graph

    let scene = SCNScene()
    private let rig = SCNNode()          // drag rotation
    private let floater = SCNNode()      // idle bobbing
    private let model = SCNNode()        // headset + per-cup effects
    private let headset: HeadsetGeometry
    private let shield: SCNNode
    private let shieldMaterial: SCNMaterial
    private let particleMaterial: SCNMaterial
    private let ringMaterial: SCNMaterial
    private let shadow: SCNNode
    private let rimLight = SCNLight()
    private var particles: [Particle] = []
    private var rings: [Ring] = []

    // MARK: Render-thread state

    static let restYaw: Float = -0.42
    static let restPitch: Float = 0.12
    private static let shieldRadius: Float = 2.08
    private static let particleStart: Float = 3.9

    private var lastTime: TimeInterval?
    private var clock: Float = 0
    private var yaw: Float = SceneEngine.restYaw
    private var yawVelocity: Float = 0
    private var targetYaw: Float = SceneEngine.restYaw
    private var pitch: Float = SceneEngine.restPitch
    private var pitchVelocity: Float = 0
    private var bounce: Float = 0
    private var bounceVelocity: Float = 0
    private var shieldAmount: Float = 0
    private var flowAmount: Float = 0
    private var flowEnd: Float = 2.08
    private var ringAmount: Float = 0
    private var presence: Float = 0.5
    private var glowIntensity: Float = 0.2
    private var glowColor = SIMD3<Float>(0.4, 0.4, 0.45)
    private var accentColor = SIMD3<Float>(0.4, 0.4, 0.45)
    private var appliedFinish: HeadsetFinish = .black
    private var lastAppliedGlow = SIMD4<Float>(-1, -1, -1, -1)

    private struct Particle {
        let node: SCNNode
        var direction = SIMD3<Float>(0, 1, 0)
        var age: Float = 0
        var speed: Float = 0.45
    }

    private struct Ring {
        let node: SCNNode
        let phase: Float
    }

    override init() {
        headset = HeadsetGeometry(finish: .black)

        shieldMaterial = SCNMaterial()
        shieldMaterial.lightingModel = .constant
        shieldMaterial.diffuse.contents = NSColor.cyan
        shieldMaterial.blendMode = .add
        shieldMaterial.writesToDepthBuffer = false
        shieldMaterial.isDoubleSided = false
        shieldMaterial.shaderModifiers = [.fragment: Self.fresnelShader]
        let shieldSphere = SCNSphere(radius: CGFloat(Self.shieldRadius))
        shieldSphere.segmentCount = 96
        shieldSphere.materials = [shieldMaterial]
        shield = SCNNode(geometry: shieldSphere)
        shield.renderingOrder = 10

        particleMaterial = Self.additiveMaterial()
        ringMaterial = Self.additiveMaterial()

        let shadowPlane = SCNPlane(width: 3.8, height: 1.3)
        let shadowMaterial = SCNMaterial()
        shadowMaterial.lightingModel = .constant
        shadowMaterial.diffuse.contents = Self.softShadowImage()
        shadowMaterial.writesToDepthBuffer = false
        shadowMaterial.isDoubleSided = true
        shadowPlane.materials = [shadowMaterial]
        shadow = SCNNode(geometry: shadowPlane)

        super.init()
        buildScene()
    }

    // MARK: - Main-thread API

    func update(_ newTarget: Target) {
        lock.lock()
        let old = target
        target = newTarget
        let modeChanged = old.look != newTarget.look
            && old.look != .disconnected && newTarget.look != .disconnected
        if modeChanged && !newTarget.reduceMotion { pendingSpins += 1 }
        if old.look != newTarget.look { pendingBounce = true }
        lock.unlock()
    }

    /// A little hop, e.g. when an EQ preset changes.
    func nudge() {
        lock.lock()
        pendingBounce = true
        lock.unlock()
    }

    /// Drag input from the view (main thread).
    func beginDrag() {
        lock.lock()
        dragging = true
        dragStartYaw = publishedYaw
        dragStartPitch = publishedPitch
        dragYaw = publishedYaw
        dragPitch = publishedPitch
        lock.unlock()
    }

    func moveDrag(dx: CGFloat, dy: CGFloat) {
        lock.lock()
        dragYaw = dragStartYaw + Float(dx) * 0.012
        dragPitch = min(max(dragStartPitch - Float(dy) * 0.008, -0.55), 0.7)
        lock.unlock()
    }

    func endDrag(velocityX: CGFloat) {
        lock.lock()
        dragging = false
        releaseVelocity = Float(velocityX) * 0.012
        lock.unlock()
    }

    // MARK: - Scene construction

    private func buildScene() {
        scene.background.contents = NSColor.clear
        scene.lightingEnvironment.contents = Self.environmentImage()
        scene.lightingEnvironment.intensity = 1.25

        let cameraNode = SCNNode()
        let camera = SCNCamera()
        camera.fieldOfView = 30
        camera.zNear = 0.1
        camera.zFar = 50
        camera.wantsHDR = true
        camera.wantsExposureAdaptation = false
        camera.bloomIntensity = 1.15
        camera.bloomThreshold = 0.72
        camera.bloomBlurRadius = 9
        camera.screenSpaceAmbientOcclusionIntensity = 0.5
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0.15, 8.4)
        scene.rootNode.addChildNode(cameraNode)

        let key = SCNLight()
        key.type = .directional
        key.intensity = 950
        key.color = NSColor(white: 1.0, alpha: 1)
        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.eulerAngles = SCNVector3(-0.75, -0.55, 0)
        scene.rootNode.addChildNode(keyNode)

        let fill = SCNLight()
        fill.type = .ambient
        fill.intensity = 180
        fill.color = NSColor(calibratedRed: 0.55, green: 0.6, blue: 0.75, alpha: 1)
        let fillNode = SCNNode()
        fillNode.light = fill
        scene.rootNode.addChildNode(fillNode)

        // Coloured rim light behind the headset, tinted with the mode.
        rimLight.type = .omni
        rimLight.intensity = 1600
        rimLight.attenuationStartDistance = 2
        rimLight.attenuationEndDistance = 9
        let rimNode = SCNNode()
        rimNode.light = rimLight
        rimNode.position = SCNVector3(0.6, 1.4, -3.2)
        scene.rootNode.addChildNode(rimNode)

        scene.rootNode.addChildNode(rig)
        rig.addChildNode(floater)
        floater.addChildNode(model)
        model.scale = SCNVector3(0.85, 0.85, 0.85)
        model.addChildNode(headset.root)

        // Sound rings travelling into each cup (ambient mode).
        let ringGeometry = SCNTorus(ringRadius: 0.55, pipeRadius: 0.007)
        ringGeometry.ringSegmentCount = 96
        ringGeometry.pipeSegmentCount = 6
        ringGeometry.materials = [ringMaterial]
        for (index, centre) in headset.cupCentres.enumerated() {
            let side = headset.cupSides[index]
            for k in 0..<3 {
                let node = SCNNode(geometry: ringGeometry)
                node.eulerAngles = SCNVector3(0, 0, CGFloat.pi / 2)
                node.simdPosition = centre + SIMD3(side * 0.28, 0, 0)
                node.opacity = 0
                node.renderingOrder = 5
                model.addChildNode(node)
                rings.append(Ring(node: node, phase: Float(k) / 3))
            }
        }

        // The shield and particles live outside the model so dragging spins only the headset.
        floater.addChildNode(shield)
        shield.opacity = 0

        let dot = SCNSphere(radius: 0.026)
        dot.segmentCount = 8
        dot.materials = [particleMaterial]
        for i in 0..<64 {
            let node = SCNNode(geometry: dot)
            node.opacity = 0
            node.renderingOrder = 6
            scene.rootNode.addChildNode(node)
            var particle = Particle(node: node)
            respawn(&particle)
            particle.age = Float(i) / 64 // stagger so the field starts full
            particles.append(particle)
        }

        shadow.eulerAngles = SCNVector3(-CGFloat.pi / 2, 0, 0)
        shadow.position = SCNVector3(0, -1.72, 0)
        shadow.renderingOrder = -1
        scene.rootNode.addChildNode(shadow)
    }

    // MARK: - Per-frame update (render thread)

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        let dt = Float(min(max(time - (lastTime ?? time), 0), 1.0 / 20.0))
        lastTime = time
        clock += dt

        lock.lock()
        let target = self.target
        let spins = pendingSpins
        pendingSpins = 0
        let wantsBounce = pendingBounce
        pendingBounce = false
        let isDragging = dragging
        let dYaw = dragYaw
        let dPitch = dragPitch
        let release = releaseVelocity
        releaseVelocity = nil
        lock.unlock()

        let motion: Float = target.reduceMotion ? 0 : 1
        let (accentA, accentB) = target.look.accent

        // 1. Where each effect is heading for this mode.
        var wantShield: Float = 0, wantFlow: Float = 0, wantEnd = Self.shieldRadius
        var wantRings: Float = 0, wantPresence: Float = 1, wantGlow: Float = 0.5
        var wantGlowColor = accentB.simd
        switch target.look {
        case .noiseCancelling:
            wantShield = 1; wantFlow = 1; wantEnd = Self.shieldRadius; wantGlow = 2.4
        case .ambient:
            wantFlow = 0.45 + 0.55 * target.level; wantEnd = 0.45
            wantRings = 0.35 + 0.65 * target.level; wantGlow = 2.0
            wantGlowColor = target.focusOnVoice ? SIMD3<Float>(1.0, 0.86, 0.62) : accentA.simd
        case .off:
            wantGlow = 0.55
        case .disconnected:
            wantPresence = 0.42; wantGlow = 0.0
        }
        wantFlow *= motion == 0 ? 0.35 : 1

        shieldAmount = ease(shieldAmount, wantShield, rate: 3.5, dt)
        flowAmount = ease(flowAmount, wantFlow, rate: 2.5, dt)
        flowEnd = ease(flowEnd, wantEnd, rate: 2.0, dt)
        ringAmount = ease(ringAmount, wantRings, rate: 3.0, dt)
        presence = ease(presence, wantPresence, rate: 3.0, dt)
        glowIntensity = ease(glowIntensity, wantGlow, rate: 3.0, dt)
        glowColor = ease(glowColor, wantGlowColor, rate: 4.0, dt)
        accentColor = ease(accentColor, accentB.simd, rate: 4.0, dt)

        // 2. Rotation: drag, release with inertia, then spring back to the resting angle.
        if spins > 0 { targetYaw += Float(spins) * 2 * .pi }
        if isDragging {
            yaw = dYaw
            pitch = dPitch
            yawVelocity = 0
            pitchVelocity = 0
            targetYaw = yaw
        } else {
            if let release {
                yawVelocity = release
                let turns = ((yaw - Self.restYaw) / (2 * .pi)).rounded()
                targetYaw = Self.restYaw + turns * 2 * .pi
            }
            if target.look == .disconnected && motion > 0 {
                targetYaw += dt * 0.45 // slow turntable while searching
            }
            spring(&yaw, &yawVelocity, toward: targetYaw, stiffness: 9, damping: 4.2, dt)
            spring(&pitch, &pitchVelocity, toward: Self.restPitch, stiffness: 12, damping: 5, dt)
        }
        if wantsBounce && motion > 0 { bounceVelocity -= 1.6 }
        spring(&bounce, &bounceVelocity, toward: 0, stiffness: 140, damping: 9, dt)

        lock.lock()
        publishedYaw = yaw
        publishedPitch = pitch
        lock.unlock()

        let bob = sin(clock * 1.25) * 0.07 * motion
        let sway = sin(clock * 0.7) * 0.035 * motion
        rig.simdEulerAngles = SIMD3(pitch, yaw, sway)
        floater.simdPosition = SIMD3(0, bob, 0)
        let squash = 1 + bounce * 0.18
        model.simdScale = SIMD3(0.85 / squash.squareRoot(), 0.85 * squash, 0.85 / squash.squareRoot())
        model.opacity = CGFloat(presence)
        shadow.simdScale = SIMD3(repeating: 1 - bob * 0.9)
        shadow.opacity = CGFloat(0.85 - bob * 2.5) * CGFloat(0.5 + 0.5 * presence)

        // 3. Materials.
        if target.finish != appliedFinish {
            headset.apply(target.finish)
            appliedFinish = target.finish
        }
        let breathing = 1 + 0.12 * sin(clock * 2.1) * motion
        let glow = SIMD4(glowColor, glowIntensity * breathing)
        if simd_distance(glow, lastAppliedGlow) > 0.004 {
            headset.glowMaterial.emission.contents = nsColor(glowColor)
            headset.glowMaterial.emission.intensity = CGFloat(glowIntensity * breathing)
            lastAppliedGlow = glow
        }
        shieldMaterial.diffuse.contents = nsColor(accentColor * 0.9)
        particleMaterial.diffuse.contents = nsColor(target.look == .ambient ? glowColor : accentColor)
        ringMaterial.diffuse.contents = nsColor(glowColor)
        rimLight.color = nsColor(accentA.simd * presence)

        // 4. Shield: fades in, breathes, and slowly turns.
        shield.isHidden = shieldAmount < 0.01
        if !shield.isHidden {
            shield.opacity = CGFloat(shieldAmount * 0.85)
            let pulse = 1 + 0.018 * sin(clock * 2.3) * motion
            shield.simdScale = SIMD3(repeating: pulse * (0.92 + 0.08 * shieldAmount))
            shield.simdEulerAngles = SIMD3(0, clock * 0.15, 0)
        }

        // 5. Particles: drift in from far away; in noise cancelling they stop and flash on the
        //    shield, in ambient mode they flow through to the ears.
        let flowVisible = flowAmount > 0.01
        for i in particles.indices {
            var p = particles[i]
            p.node.isHidden = !flowVisible
            if flowVisible {
                p.age += dt * p.speed * (0.6 + 0.4 * flowAmount)
                if p.age >= 1 { respawn(&p) }
                let t = p.age
                let travel = t * t * (3 - 2 * t) // smoothstep
                let radius = Self.particleStart + (flowEnd - Self.particleStart) * travel
                var opacity = pow(sin(.pi * t), 0.7) * flowAmount
                var size: Float = 1
                if t > 0.86 && shieldAmount > 0.5 {
                    let k = (t - 0.86) / 0.14
                    size = 1 + k * 2.6
                    opacity *= 1 - k * 0.6
                }
                p.node.simdPosition = p.direction * radius + SIMD3(0, bob, 0)
                p.node.simdScale = SIMD3(repeating: size)
                p.node.opacity = CGFloat(opacity)
            }
            particles[i] = p
        }

        // 6. Rings shrinking into the cups.
        let ringsVisible = ringAmount > 0.01
        let ringSpeed: Float = 0.35 + 0.4 * target.level
        for ring in rings {
            ring.node.isHidden = !ringsVisible
            guard ringsVisible else { continue }
            let t = (clock * ringSpeed * motion + ring.phase).truncatingRemainder(dividingBy: 1)
            let scale = 2.1 - 1.5 * t
            ring.node.simdScale = SIMD3(scale * 1.22, 1, scale)
            ring.node.opacity = CGFloat(sin(.pi * t) * 0.9 * ringAmount)
        }
    }

    // MARK: - Helpers

    private func respawn(_ p: inout Particle) {
        let z = Float.random(in: -1...1)
        let theta = Float.random(in: 0..<(2 * .pi))
        let r = (1 - z * z).squareRoot()
        // Flatten toward the camera plane so fewer particles hide behind the headset.
        p.direction = simd_normalize(SIMD3(r * cos(theta), r * sin(theta) * 0.8, z * 0.6))
        p.age = 0
        p.speed = Float.random(in: 0.32...0.6)
    }

    private func ease(_ value: Float, _ target: Float, rate: Float, _ dt: Float) -> Float {
        value + (target - value) * (1 - exp(-rate * dt))
    }

    private func ease(_ value: SIMD3<Float>, _ target: SIMD3<Float>, rate: Float, _ dt: Float) -> SIMD3<Float> {
        value + (target - value) * (1 - exp(-rate * dt))
    }

    private func spring(_ x: inout Float, _ v: inout Float, toward target: Float,
                        stiffness: Float, damping: Float, _ dt: Float) {
        // Two half steps keep the stiffer springs stable at low frame rates.
        let h = dt / 2
        for _ in 0..<2 {
            let a = stiffness * (target - x) - damping * v
            v += a * h
            x += v * h
        }
    }

    private func nsColor(_ c: SIMD3<Float>) -> NSColor {
        NSColor(srgbRed: CGFloat(max(0, min(1, c.x))), green: CGFloat(max(0, min(1, c.y))),
                blue: CGFloat(max(0, min(1, c.z))), alpha: 1)
    }

    private static func additiveMaterial() -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = NSColor.white
        m.blendMode = .add
        m.writesToDepthBuffer = false
        return m
    }

    /// Bright at grazing angles, almost invisible face-on: reads as an energy bubble.
    private static let fresnelShader = """
    #pragma transparent
    #pragma body
    float ndv = abs(dot(normalize(_surface.normal), normalize(_surface.view)));
    float rim = pow(1.0 - ndv, 2.4);
    _output.color.rgb = _output.color.rgb * (0.06 + rim * 1.8);
    _output.color.a = _output.color.a * (0.04 + rim);
    """

    /// A soft studio environment for reflections: bright top, two softboxes, dark floor.
    private static func environmentImage() -> NSImage {
        let size = NSSize(width: 512, height: 256)
        return NSImage(size: size, flipped: false) { rect in
            let sky = NSGradient(colors: [
                NSColor(calibratedWhite: 0.05, alpha: 1),
                NSColor(calibratedRed: 0.30, green: 0.32, blue: 0.38, alpha: 1),
                NSColor(calibratedRed: 0.82, green: 0.84, blue: 0.9, alpha: 1),
            ], atLocations: [0, 0.48, 1], colorSpace: .sRGB)
            sky?.draw(in: rect, angle: 90)
            let softboxes: [(CGFloat, CGFloat)] = [(0.18, 0.16), (0.68, 0.22)]
            for (x, w) in softboxes {
                let box = NSRect(x: rect.width * x, y: rect.height * 0.62,
                                 width: rect.width * w, height: rect.height * 0.22)
                let glow = NSGradient(starting: NSColor(white: 1, alpha: 0.95),
                                      ending: NSColor(white: 1, alpha: 0))
                glow?.draw(in: NSBezierPath(ovalIn: box), relativeCenterPosition: .zero)
            }
            return true
        }
    }

    private static func softShadowImage() -> NSImage {
        NSImage(size: NSSize(width: 256, height: 128), flipped: false) { rect in
            let gradient = NSGradient(colors: [
                NSColor(white: 0, alpha: 0.55),
                NSColor(white: 0, alpha: 0.18),
                NSColor(white: 0, alpha: 0),
            ], atLocations: [0, 0.45, 1], colorSpace: .sRGB)
            gradient?.draw(in: NSBezierPath(ovalIn: rect), relativeCenterPosition: .zero)
            return true
        }
    }
}
