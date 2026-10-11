import Cocoa
import SceneKit
import Metal

/// Prototype-only studio scene. SceneKit renders a still on demand; no SCNView,
/// display link, animation, run loop or continuously-rendering Metal surface.
final class PorcelainSceneRenderer {
    static let canvasSize = NSSize(width: 2464, height: 1096)
    private static let bottomLiftAngle = 5.0 * Double.pi / 180
    private let renderer: SCNRenderer
    private let scene = SCNScene()
    private let keyboard = SCNNode()
    private var capNodes: [String: SCNNode] = [:]
    private var keyCenters: [String: SCNVector3] = [:]
    private var cachedCounts: [String: Int]?
    private var cachedNeutral = false
    private(set) var image: NSImage?
    private(set) var background = rgb(0xEAE9E5)
    private(set) var renderCount = 0

    init() {
        renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
        renderer.scene = scene
        renderer.isPlaying = false
        renderer.autoenablesDefaultLighting = false
        scene.background.contents = background
        scene.rootNode.addChildNode(keyboard)
        makeStudio()
        makeKeyboard()
    }

    private func material(_ color: NSColor, roughness: Double = 0.76,
                          metalness: Double = 0) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = color
        m.roughness.contents = roughness
        m.metalness.contents = metalness
        return m
    }

    private func makeStudio() {
        let camera = SCNCamera()
        camera.usesOrthographicProjection = true
        camera.orthographicScale = 4.7
        camera.zNear = 0.1
        camera.zFar = 150
        camera.wantsHDR = false
        camera.wantsExposureAdaptation = false
        camera.bloomIntensity = 0
        let eye = SCNNode()
        eye.camera = camera
        // Centered, shallow overhead view: parallel rows and equal-size legends.
        // Cap thickness comes from geometry/light, not dramatic camera distortion.
        eye.position = SCNVector3(0, 24, 7.3)
        eye.look(at: SCNVector3(0, 0.35, 0.3))
        scene.rootNode.addChildNode(eye)
        renderer.pointOfView = eye

        // One key light defines all highlights and cast shadows.
        let light = SCNLight()
        light.type = .directional
        light.intensity = 650
        light.color = NSColor.white
        light.castsShadow = true
        light.shadowMode = .forward
        light.shadowMapSize = NSSize(width: 4096, height: 4096)
        light.shadowSampleCount = 32
        light.shadowRadius = 2.5
        light.shadowBias = 0.08
        light.shadowColor = NSColor.black.withAlphaComponent(0.35)
        light.orthographicScale = 23
        light.maximumShadowDistance = 45
        let keyLight = SCNNode()
        keyLight.light = light
        keyLight.position = SCNVector3(-9, 16, -8)
        keyLight.look(at: SCNVector3Zero)
        scene.rootNode.addChildNode(keyLight)

        // Non-directional studio fill keeps unlit side walls legible.
        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light!.type = .ambient
        fill.light!.intensity = 230
        fill.light!.color = rgb(0xF0F1F2)
        scene.rootNode.addChildNode(fill)

        let floor = SCNPlane(width: 180, height: 180)
        floor.firstMaterial = material(rgb(0xEAE9E5), roughness: 1)
        let ground = SCNNode(geometry: floor)
        ground.eulerAngles.x = -.pi / 2
        ground.castsShadow = false
        scene.rootNode.addChildNode(ground)
    }

    private func makeKeyboard() {
        // Tilt the physical assembly, not the camera/image. Positive local Z is
        // the spacebar edge; a negative X pitch lifts it around the rear feet.
        keyboard.eulerAngles.x = -CGFloat(Self.bottomLiftAngle)
        keyboard.position = SCNVector3(0, 3.19 * sin(Self.bottomLiftAngle), 0)
        let chassis = SCNBox(width: 18.08, height: 0.27, length: 7.65, chamferRadius: 0.085)
        chassis.widthSegmentCount = 1
        chassis.chamferSegmentCount = 4
        chassis.firstMaterial = material(rgb(0xC9CBC9), roughness: 0.62, metalness: 0.22)
        let base = SCNNode(geometry: chassis)
        base.position.y = 0.225
        keyboard.addChildNode(base)

        // Rear foot rims touch the floor after pitching; the front pair lifts
        // with the chassis. All cast shadows come from the same scene light.
        for x in [-7.7, 7.7] {
            for z in [-2.95, 2.95] {
                let foot = SCNCylinder(radius: 0.24, height: 0.10)
                foot.firstMaterial = material(rgb(0x555650), roughness: 1)
                let node = SCNNode(geometry: foot)
                node.position = SCNVector3(x, 0.05, z)
                keyboard.addChildNode(node)
            }
        }

        for row in KeyboardLayout.macStyle.rows {
            var cursor = row.startXUnits
            for key in row.keys {
                let x = key.xUnits.map { row.startXUnits + $0 } ?? cursor
                let z = row.yUnits + key.yOffsetUnits
                let cap = SCNNode(geometry: Self.keycap(width: key.widthUnits, depth: key.heightUnits))
                cap.name = key.id
                cap.position = SCNVector3(x + key.widthUnits / 2 - 17.18 / 2,
                                         0.385, z + key.heightUnits / 2 - 6.75 / 2)
                keyboard.addChildNode(cap)
                capNodes[key.id] = cap
                keyCenters[key.id] = SCNVector3(cap.position.x, 0.805, cap.position.z)
                cursor = x + key.widthUnits + KeyboardLayout.macStyle.keySpacingUnits
            }
        }
    }

    /// Four rounded rings create a closed, tapered solid: skirt, wall, shoulder,
    /// flat crown. Triangle normals—not painted bands—define all side lighting.
    private static func keycap(width: Double, depth: Double) -> SCNGeometry {
        func ring(inset: Double, y: Double, radius: Double) -> [SCNVector3] {
            let w = width / 2 - inset, d = depth / 2 - inset
            let corners = [(w - radius, d - radius), (-w + radius, d - radius),
                           (-w + radius, -d + radius), (w - radius, -d + radius)]
            return corners.enumerated().flatMap { corner, center in
                (0...6).map { step in
                    let angle = Double(corner) * .pi / 2 + Double(step) * .pi / 12
                    return SCNVector3(center.0 + radius * cos(angle), y,
                                      center.1 + radius * sin(angle))
                }
            }
        }
        let rings = [ring(inset: 0.015, y: 0, radius: 0.065),
                     ring(inset: 0.015, y: 0.08, radius: 0.065),
                     ring(inset: 0.075, y: 0.355, radius: 0.055),
                     ring(inset: 0.10, y: 0.415, radius: 0.045)]
        var vertices: [SCNVector3] = [], normals: [SCNVector3] = []
        func triangle(_ a: SCNVector3, _ b: SCNVector3, _ c: SCNVector3) {
            let u = SCNVector3(b.x - a.x, b.y - a.y, b.z - a.z)
            let v = SCNVector3(c.x - a.x, c.y - a.y, c.z - a.z)
            let n = SCNVector3(u.y * v.z - u.z * v.y, u.z * v.x - u.x * v.z, u.x * v.y - u.y * v.x)
            let length = sqrt(n.x * n.x + n.y * n.y + n.z * n.z)
            let normal = SCNVector3(n.x / length, n.y / length, n.z / length)
            vertices += [a, b, c]
            normals += [normal, normal, normal]
        }
        for layer in 0..<(rings.count - 1) {
            for i in rings[layer].indices {
                let j = (i + 1) % rings[layer].count
                let a = rings[layer][i], b = rings[layer + 1][i]
                let c = rings[layer + 1][j], d = rings[layer][j]
                triangle(a, b, c); triangle(a, c, d)
            }
        }
        let top = rings.last!, bottom = rings.first!
        for i in top.indices {
            let j = (i + 1) % top.count
            triangle(SCNVector3(0, 0.415, 0), top[j], top[i])
            triangle(SCNVector3Zero, bottom[i], bottom[j])
        }
        let indices = (0..<vertices.count).map { UInt32($0) }
        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices),
                                             SCNGeometrySource(normals: normals)],
            elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
        return geometry
    }

    func render(dataset: AtelierDataset, neutral: Bool) -> NSImage {
        let counts = Dictionary(uniqueKeysWithValues: KeyboardLayout.macStyle.keys.map { ($0.id, dataset.count(for: $0)) })
        if cachedCounts == counts, cachedNeutral == neutral, let image { return image }
        SCNTransaction.begin()
        SCNTransaction.disableActions = true
        for key in KeyboardLayout.macStyle.keys {
            let count = counts[key.id]!
            let progress = KeyboardUsageProgress.progress(for: count)
            let color = neutral ? rgb(0xECECE6) : mix(AtelierFinish.porcelain.color(progress), rgb(0xECECE6), 0.16)
            let cap = capNodes[key.id]!
            cap.geometry!.firstMaterial = material(color)
            for child in cap.childNodes { child.removeFromParentNode() }
            let face = SCNPlane(width: key.widthUnits - 0.215, height: key.heightUnits - 0.215)
            let ink = SCNMaterial()
            ink.lightingModel = .constant
            ink.diffuse.contents = Self.legendTexture(key: key, count: count,
                lightInk: !neutral && progress > 0.26 && progress < 0.46)
            ink.transparencyMode = .aOne
            ink.isDoubleSided = false
            ink.writesToDepthBuffer = false
            face.firstMaterial = ink
            let print = SCNNode(geometry: face)
            print.position.y = 0.416
            print.eulerAngles.x = -.pi / 2
            print.castsShadow = false
            cap.addChildNode(print)
        }
        SCNTransaction.commit()
        let result = renderer.snapshot(atTime: 0, with: Self.canvasSize, antialiasingMode: .multisampling4X)
        cachedCounts = counts
        cachedNeutral = neutral
        image = result
        renderCount += 1
        // Match the surrounding paper to the actual lit ground, not a fake vignette.
        if let bytes = result.tiffRepresentation, let bitmap = NSBitmapImageRep(data: bytes),
           let edge = bitmap.colorAt(x: 3, y: 3) { background = edge }
        return result
    }

    private static func legendTexture(key: KeyboardKey, count: Int, lightInk: Bool) -> NSImage {
        let size = NSSize(width: max(128, key.widthUnits * 192), height: max(96, key.heightUnits * 192))
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill(using: .copy)
        let ink = lightInk ? rgb(0xF1F2EF) : rgb(0x333C40)
        let label: String
        switch key.symbolName {
        case "command": label = "⌘"
        case "option": label = "⌥"
        case "shift": label = "⇧"
        case "control": label = "⌃"
        case "globe": label = "fn"
        default: label = key.id == "Space" ? "space" : key.label.components(separatedBy: "\n").last ?? key.label
        }
        let halfArrow = key.heightUnits < 0.6
        let labelSize: CGFloat = label.count > 6 ? 35 : 43
        (label as NSString).draw(at: CGPoint(x: 12, y: size.height - (halfArrow ? 37 : 58)),
            withAttributes: [.font: NSFont.systemFont(ofSize: halfArrow ? 29 : labelSize, weight: .regular),
                             .foregroundColor: ink])
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .right
        (compact(count) as NSString).draw(in: CGRect(x: halfArrow ? 44 : 10, y: 8,
                width: size.width - (halfArrow ? 50 : 20), height: 38),
            withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: halfArrow ? 24 : 31, weight: .regular),
                             .foregroundColor: ink.withAlphaComponent(0.7), .paragraphStyle: paragraph])
        image.unlockFocus()
        return image
    }

    /// Hit testing uses the same camera and geometry as the still image.
    func keyID(at point: CGPoint) -> String? {
        let hits = renderer.hitTest(point, options: [.searchMode: SCNHitTestSearchMode.closest.rawValue])
        guard var node = hits.first?.node else { return nil }
        while node !== scene.rootNode {
            if let name = node.name, capNodes[name] === node { return name }
            guard let parent = node.parent else { return nil }
            node = parent
        }
        return nil
    }

    /// No real input or UI automation: deterministic geometry/picking/cache smoke test.
    func validateGeometry(dataset: AtelierDataset) throws {
        _ = render(dataset: dataset, neutral: true)
        let before = renderCount
        _ = render(dataset: dataset, neutral: true)
        guard before == renderCount, capNodes.count == KeyboardLayout.macStyle.keys.count else {
            throw CocoaError(.coderInvalidValue)
        }
        for (id, center) in keyCenters {
            let projected = renderer.projectPoint(keyboard.convertPosition(center, to: nil))
            guard projected.x.isFinite, projected.y.isFinite, projected.z.isFinite,
                  projected.x > 0, projected.x < Self.canvasSize.width,
                  projected.y > 0, projected.y < Self.canvasSize.height,
                  keyID(at: CGPoint(x: projected.x, y: projected.y)) == id else {
                fputs("Geometry picking mismatch: \(id) at \(projected)\n", stderr)
                throw CocoaError(.coderInvalidValue)
            }
        }
        for x in [-9.04, 9.04] {
            for z in [-3.825, 3.825] {
                let corner = renderer.projectPoint(keyboard.convertPosition(SCNVector3(x, 0.09, z), to: nil))
                guard corner.x > 0, corner.x < Self.canvasSize.width,
                      corner.y > 0, corner.y < Self.canvasSize.height else {
                    throw CocoaError(.coderInvalidValue)
                }
            }
        }
        let rearContact = keyboard.convertPosition(SCNVector3(0, 0, -3.19), to: nil)
        let backEdge = keyboard.convertPosition(SCNVector3(0, 0.09, -3.825), to: nil)
        let frontEdge = keyboard.convertPosition(SCNVector3(0, 0.09, 3.825), to: nil)
        guard abs(rearContact.y) < 0.0001, backEdge.y >= 0,
              frontEdge.y > backEdge.y, abs(keyboard.eulerAngles.z) < 0.0001 else {
            throw CocoaError(.coderInvalidValue)
        }
        print("Geometry smoke passed: \(capNodes.count) caps, transformed center hit tests, bottom lifted, rear contact, neutral image, cache reuse.")
    }
}
