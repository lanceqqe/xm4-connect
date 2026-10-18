import AppKit
import SceneKit

/// A stylised over-ear headset built from SceneKit primitives — no model files, no third-party
/// assets. Proportions are inspired by modern over-ear headphones: a thin band, slim sliders
/// and smooth oval cups.
struct HeadsetGeometry {
    let root = SCNNode()
    let bodyMaterial: SCNMaterial
    let bandMaterial: SCNMaterial
    let cushionMaterial: SCNMaterial
    /// Emissive parts (driver glow, light strips) — recoloured every frame by the scene.
    let glowMaterial: SCNMaterial
    /// Centres of the two cups in the headset's own space (left, right).
    let cupCentres: [SIMD3<Float>]
    /// The side each cup faces outward on (−1 left, +1 right), same order as `cupCentres`.
    let cupSides: [Float] = [-1, 1]

    init(finish: HeadsetFinish) {
        bodyMaterial = Self.pbr(finish.body, roughness: 0.42, metalness: 0.15)
        bandMaterial = Self.pbr(finish.body, roughness: 0.32, metalness: 0.25)
        cushionMaterial = Self.pbr(finish.cushion, roughness: 0.88, metalness: 0.0)

        glowMaterial = SCNMaterial()
        glowMaterial.lightingModel = .physicallyBased
        glowMaterial.diffuse.contents = NSColor.black
        glowMaterial.metalness.contents = NSNumber(value: 0.0)
        glowMaterial.roughness.contents = NSNumber(value: 1.0)
        glowMaterial.emission.contents = NSColor.white
        glowMaterial.emission.intensity = 2

        let cupX: CGFloat = 1.45
        let cupY: CGFloat = -0.86
        cupCentres = [SIMD3(Float(-cupX), Float(cupY), 0), SIMD3(Float(cupX), Float(cupY), 0)]

        root.addChildNode(makeHeadband())
        root.addChildNode(makeBandCushion())
        for side in [CGFloat(-1), CGFloat(1)] {
            root.addChildNode(makeSlider(side: side, cupX: cupX))
            root.addChildNode(makeCup(side: side, at: SCNVector3(side * cupX, cupY, 0)))
        }
    }

    func apply(_ finish: HeadsetFinish) {
        bodyMaterial.diffuse.contents = finish.body.nsColor
        bandMaterial.diffuse.contents = finish.body.nsColor
        cushionMaterial.diffuse.contents = finish.cushion.nsColor
    }

    // MARK: - Parts

    private func makeHeadband() -> SCNNode {
        let path = Self.arcBand(outer: 1.53, inner: 1.37, from: 11, to: 169)
        let shape = SCNShape(path: path, extrusionDepth: 0.40)
        shape.chamferRadius = 0.06
        shape.chamferMode = .both
        shape.materials = [bandMaterial]
        let node = SCNNode(geometry: shape)
        node.name = "headband"
        return node
    }

    /// The soft pad under the band.
    private func makeBandCushion() -> SCNNode {
        let path = Self.arcBand(outer: 1.38, inner: 1.27, from: 42, to: 138)
        let shape = SCNShape(path: path, extrusionDepth: 0.30)
        shape.chamferRadius = 0.045
        shape.chamferMode = .both
        shape.materials = [cushionMaterial]
        return SCNNode(geometry: shape)
    }

    private func makeSlider(side: CGFloat, cupX: CGFloat) -> SCNNode {
        let group = SCNNode()

        let wire = SCNCapsule(capRadius: 0.042, height: 0.62)
        wire.materials = [bandMaterial]
        let wireNode = SCNNode(geometry: wire)
        wireNode.position = SCNVector3(side * cupX, 0.02, 0)
        group.addChildNode(wireNode)

        // Small hinge block where the slider meets the cup.
        let hinge = SCNBox(width: 0.12, height: 0.14, length: 0.2, chamferRadius: 0.05)
        hinge.materials = [bodyMaterial]
        let hingeNode = SCNNode(geometry: hinge)
        hingeNode.position = SCNVector3(side * cupX, -0.24, 0)
        group.addChildNode(hingeNode)
        return group
    }

    private func makeCup(side: CGFloat, at position: SCNVector3) -> SCNNode {
        let cup = SCNNode()
        cup.position = position
        let ovalY: CGFloat = 1.22

        // Shell: a squashed sphere reads as a smooth, pebble-like cup.
        let shell = SCNSphere(radius: 0.6)
        shell.segmentCount = 72
        shell.materials = [bodyMaterial]
        let shellNode = SCNNode(geometry: shell)
        shellNode.scale = SCNVector3(0.38, ovalY, 0.98)
        shellNode.position = SCNVector3(side * 0.05, 0, 0)
        cup.addChildNode(shellNode)

        // Ear cushion on the inner side. Torus axis is local Y; rotating about Z by 90° points
        // it along X, after which local X is world Y — so local X carries the oval stretch.
        let cushion = SCNTorus(ringRadius: 0.42, pipeRadius: 0.135)
        cushion.ringSegmentCount = 72
        cushion.pipeSegmentCount = 24
        cushion.materials = [cushionMaterial]
        let cushionNode = SCNNode(geometry: cushion)
        cushionNode.eulerAngles = SCNVector3(0, 0, CGFloat.pi / 2)
        cushionNode.scale = SCNVector3(ovalY, 1.0, 0.98)
        cushionNode.position = SCNVector3(-side * 0.2, 0, 0)
        cup.addChildNode(cushionNode)

        // Driver glow, visible through the cushion opening.
        let disc = SCNCylinder(radius: 0.29, height: 0.01)
        disc.radialSegmentCount = 64
        disc.materials = [glowMaterial]
        let discNode = SCNNode(geometry: disc)
        discNode.eulerAngles = SCNVector3(0, 0, CGFloat.pi / 2)
        discNode.scale = SCNVector3(ovalY, 1.0, 0.98)
        discNode.position = SCNVector3(-side * 0.19, 0, 0)
        cup.addChildNode(discNode)

        // A thin light strip around the outer face.
        let strip = SCNTorus(ringRadius: 0.5, pipeRadius: 0.011)
        strip.ringSegmentCount = 96
        strip.pipeSegmentCount = 8
        strip.materials = [glowMaterial]
        let stripNode = SCNNode(geometry: strip)
        stripNode.eulerAngles = SCNVector3(0, 0, CGFloat.pi / 2)
        stripNode.scale = SCNVector3(ovalY, 1.0, 0.98)
        stripNode.position = SCNVector3(side * 0.17, 0, 0)
        cup.addChildNode(stripNode)

        return cup
    }

    // MARK: - Helpers

    /// A ring segment (annulus sector) in the XY plane, angles in degrees.
    private static func arcBand(outer: CGFloat, inner: CGFloat, from start: CGFloat, to end: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        let rad = start * .pi / 180
        path.move(to: NSPoint(x: outer * cos(rad), y: outer * sin(rad)))
        path.appendArc(withCenter: .zero, radius: outer, startAngle: start, endAngle: end, clockwise: false)
        path.appendArc(withCenter: .zero, radius: inner, startAngle: end, endAngle: start, clockwise: true)
        path.close()
        path.flatness = 0.004
        return path
    }

    static func pbr(_ color: RGB, roughness: Double, metalness: Double) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = color.nsColor
        material.roughness.contents = NSNumber(value: roughness)
        material.metalness.contents = NSNumber(value: metalness)
        return material
    }
}
