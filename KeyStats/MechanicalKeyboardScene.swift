import Cocoa
import SceneKit
import MetalKit

enum MechanicalKeyboardError: Error { case invalidGeometry }
final class MechanicalKeyboardScene {
    static let size = CGSize(width:1280,height:720)
    let baseline: EditorialKeyboardSceneLayout
    let scene = SCNScene()
    private let renderer = SCNRenderer(device:MTLCreateSystemDefaultDevice(),options:nil)
    private let eye = SCNNode()
    private var layoutNodes: [String:SCNNode] = [:]
    private let floorMaterial = SCNMaterial()
    private(set) var growthHeights: [String: CGFloat] = [:]
    private(set) var isMacModel = false
    private(set) var keys: [EditorialKeyboardSceneKey] = []
    private let width: CGFloat
    private let depth: CGFloat
    static let canvas = NSColor(srgbRed:242/255,green:242/255,blue:238/255,alpha:1)

    init() throws {
        baseline = EditorialKeyboardRenderer(frame: .zero).sceneLayout
        width = baseline.boardSize.width/baseline.unit; depth = baseline.boardSize.height/baseline.unit
        renderer.scene = scene; renderer.isPlaying = false; renderer.autoenablesDefaultLighting = false
        scene.background.contents = Self.canvas
        eye.camera = SCNCamera(); let camera = eye.camera!
        camera.usesOrthographicProjection = false; camera.fieldOfView = 30
        camera.zNear = 0.1; camera.zFar = 150
        camera.wantsHDR = false; camera.wantsExposureAdaptation = false; camera.bloomIntensity = 0
        scene.rootNode.addChildNode(eye); renderer.pointOfView = eye
        let lamp = SCNNode(); lamp.light = SCNLight(); let light = lamp.light!
        light.type = .directional; light.color = NSColor.white; light.intensity = 600
        light.castsShadow = true; light.shadowMode = .deferred
        light.shadowMapSize = CGSize(width:2048,height:2048); light.shadowSampleCount = 8
        light.shadowRadius = 3; light.shadowBias = 0.015
        light.shadowColor = NSColor.black.withAlphaComponent(0.10)
        light.orthographicScale = width+2; light.zNear = 1; light.zFar = 45
        lamp.position = SCNVector3(-6,14,10); lamp.look(at:SCNVector3Zero); scene.rootNode.addChildNode(lamp)
        let fill = SCNNode(); fill.light = SCNLight(); fill.light!.type = .ambient
        fill.light!.color = NSColor.white; fill.light!.intensity = 420; scene.rootNode.addChildNode(fill)
        let path = NSBezierPath(roundedRect:CGRect(x:-(width+0.28)/2,y:-(depth+0.24)/2,width:width+0.28,height:depth+0.24),
            xRadius:19/baseline.unit,yRadius:19/baseline.unit); path.flatness = 0.003
        let deck = SCNShape(path:path,extrusionDepth:0.06); deck.chamferRadius = 0.01
        deck.firstMaterial = Self.material(NSColor(srgbRed:0.88,green:0.89,blue:0.88,alpha:1))
        let tray = SCNNode(geometry:deck); tray.position.y = 0.045; tray.eulerAngles.x = -.pi/2
        scene.rootNode.addChildNode(tray)
        let floor = SCNNode(geometry:SCNPlane(width:80,height:80)); floor.eulerAngles.x = -.pi/2
        floor.geometry!.firstMaterial = floorMaterial
        floor.geometry!.firstMaterial!.lightingModel = .constant
        floor.geometry!.firstMaterial!.diffuse.contents = Self.canvas; floor.castsShadow = false
        scene.rootNode.addChildNode(floor)
        for key in baseline.keys {
            let node = SCNNode(); node.name = key.id
            node.position = SCNVector3(key.rect.midX/baseline.unit-width/2,0.075,key.rect.midY/baseline.unit-depth/2)
            scene.rootNode.addChildNode(node)
            layoutNodes[key.id] = node
        }
    }
    private static func material(_ color:NSColor, shade:CGFloat = 1) -> SCNMaterial {
        let rgb = color.usingColorSpace(.sRGB)!
        let m = SCNMaterial(); m.lightingModel = .lambert
        let tinted = NSColor(srgbRed:rgb.redComponent*shade,green:rgb.greenComponent*shade,blue:rgb.blueComponent*shade,alpha:1)
        m.diffuse.contents = tinted; m.ambient.contents = tinted
        m.specular.contents = NSColor.black
        return m
    }
    static let millimetresPerUnit: CGFloat = 19.05
    static let modelWidthMM: CGFloat = 18.1
    static let modelHeightMM: CGFloat = 10.5
    static let macHeight: CGFloat = 0.30
    func configureFullModel() throws {
        guard baseline.keys.count == 77, layoutNodes.count == 77 else {
            print("FULL77 layout count:", baseline.keys.count, layoutNodes.count); throw MechanicalKeyboardError.invalidGeometry
        }
        keys = baseline.keys
        let clearance = (1 - Self.modelWidthMM / Self.millimetresPerUnit) / 2
        SCNTransaction.begin(); SCNTransaction.disableActions = true
        defer { SCNTransaction.commit() }
        for key in keys {
            let node = layoutNodes[key.id]!
            // rect includes Editorial's slight row projection; size is the
            // unprojected cap size used by the approved four-key model.
            let w = key.size.width / baseline.unit - 2 * clearance
            let d = key.size.height / baseline.unit - 2 * clearance
            guard w > 0.2, d > 0.2 else {
                print("FULL77 invalid dimensions:", key.id, w, d); throw MechanicalKeyboardError.invalidGeometry
            }
            let mesh = MechanicalKeycapMesh(width: w, depth: d,
                height: Self.modelHeightMM / Self.millimetresPerUnit, spacebar: key.id == "Space")
            mesh.geometry.materials = mesh.geometry.elements.map { _ in
                Self.material(NSColor(srgbRed: 0.82, green: 0.83, blue: 0.82, alpha: 1))
            }
            node.geometry = mesh.geometry; node.scale = SCNVector3(1, 1, 1)
            node.position.y = 0.075; node.isHidden = false
        }
        setFront72ModelView(castsShadows: false)
        // The four-key camera helper hides Space. Restore all actual models.
        for node in layoutNodes.values { node.isHidden = false }
    }

    var fullModelNodes: [SCNNode] { baseline.keys.compactMap { layoutNodes[$0.id] } }

    static func growthHeight(_ progress: Double) -> CGFloat {
        0.35 + 0.40 * CGFloat(min(1, max(0, progress)))
    }

    func applyGrowth(_ values: [GrowthKeyboardKeyUsage]) {
        let usages = Dictionary(uniqueKeysWithValues: values.map { ($0.id, $0) })
        let clearance = (1 - Self.modelWidthMM / Self.millimetresPerUnit) / 2
        SCNTransaction.begin(); SCNTransaction.disableActions = true
        defer { SCNTransaction.commit() }
        for key in keys {
            let usage = usages[key.id] ?? GrowthKeyboardKeyUsage(id: key.id, count: 0)
            let height = Self.growthHeight(usage.progress)
            let node = layoutNodes[key.id]!
            if growthHeights[key.id] != height {
                node.geometry = MechanicalKeycapMesh(width: key.size.width / baseline.unit - 2 * clearance,
                    depth: key.size.height / baseline.unit - 2 * clearance, height: height,
                    spacebar: key.id == "Space").geometry
                growthHeights[key.id] = height
            }
            let color = baseline.usageColor(usage.progress)
            node.geometry!.materials = node.geometry!.elements.map { _ in Self.material(color) }
            node.position.y = 0.075
        }
    }

    func renderGrowth(_ values: [GrowthKeyboardKeyUsage], background: NSColor) -> GrowthKeyboard3DFrame {
        applyGrowth(values)
        scene.background.contents = background
        floorMaterial.diffuse.contents = background
        let image = snapshot()
        let legends = KeyboardLegendOverlay(model: self)
        legends.pixelScale = 3
        image.lockFocusFlipped(true)
        legends.draw(CGRect(origin: .zero, size: Self.size))
        image.unlockFocus()
        let rects = Dictionary(uniqueKeysWithValues: keys.map { key in
            let node = layoutNodes[key.id]!
            let (low, high) = node.geometry!.boundingBox
            let points = [low.x, high.x].flatMap { x in [low.y, high.y].flatMap { y in
                [low.z, high.z].map { z -> CGPoint in
                    let point = renderer.projectPoint(node.convertPosition(SCNVector3(x, y, z), to: nil))
                    return CGPoint(x: point.x / 3, y: Self.size.height - point.y / 3)
                }
            } }
            return (key.id, points.reduce(CGRect.null) { $0.union(CGRect(origin: $1, size: .zero)) })
        })
        return GrowthKeyboard3DFrame(image: image, rects: rects)
    }

    // The demo drives the same renderer only during finite click impulses.
    var metalDevice: MTLDevice { renderer.device! }
    var legendScale: CGFloat {
        Self.size.height / (2 * CGFloat(eye.camera!.orthographicScale) * baseline.unit)
    }
    func drawFullModel(in view: MTKView, queue: MTLCommandQueue) {
        guard let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
              let command = queue.makeCommandBuffer() else { return }
        SCNTransaction.flush()
        renderer.render(atTime: 0, viewport: CGRect(origin: .zero, size: view.drawableSize), commandBuffer: command, passDescriptor: pass)
        command.present(drawable); command.commit()
    }
    func applyFullPress(_ offsets: [String: CGFloat]) {
        SCNTransaction.begin(); SCNTransaction.disableActions = true
        for (id, node) in layoutNodes {
            let offset = min(isMacModel ? 0.10 : 0.18, max(0, offsets[id] ?? 0))
            node.position.y = isMacModel ? 0.075 + Self.macHeight / 2 - offset * 0.45 : 0.075 - offset
        }
        SCNTransaction.commit()
    }
    func fullKey(at point: CGPoint, pixelScale: CGFloat) -> String? {
        let x = point.x * pixelScale, y = (Self.size.height - point.y) * pixelScale
        let near = renderer.unprojectPoint(SCNVector3(x, y, 0))
        let far = renderer.unprojectPoint(SCNVector3(x, y, 1))
        let hits = scene.rootNode.hitTestWithSegment(from: near, to: far,
            options: [SCNHitTestOption.searchMode.rawValue: SCNHitTestSearchMode.closest.rawValue,
                SCNHitTestOption.ignoreHiddenNodes.rawValue: true,
                SCNHitTestOption.clipToZRange.rawValue: false])
        guard let id = hits.first?.node.name, layoutNodes[id] != nil else { return nil }
        return id
    }
    func fullKeyCenter(_ id: String, pixelScale: CGFloat) -> CGPoint {
        let node = layoutNodes[id]!
        let crown: CGFloat = id == "Space" ? 0.022 : -0.060
        let p = renderer.projectPoint(SCNVector3(node.position.x,
            isMacModel ? node.position.y + Self.macHeight / 2 : node.position.y + (growthHeights[id] ?? Self.modelHeightMM / Self.millimetresPerUnit) + crown, node.position.z))
        return CGPoint(x: p.x / pixelScale, y: Self.size.height - p.y / pixelScale)
    }

    func setFront72ModelView(castsShadows: Bool = true) {
        SCNTransaction.begin(); SCNTransaction.disableActions = true
        defer { SCNTransaction.commit() }
        eye.camera!.usesOrthographicProjection = true
        let angle: CGFloat = 72 * .pi / 180
        let target = SCNVector3(0, 0.09, 0)
        eye.position = SCNVector3(0, 0.09 + 30 * sin(angle), 30 * cos(angle))
        eye.look(at: target, up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
        let scale = max((depth + 0.45) / 2, (width + 0.7) / (2 * Self.size.width / Self.size.height))
        eye.camera!.orthographicScale = scale
        for node in scene.rootNode.childNodes where node.light?.type == .directional {
            node.light?.castsShadow = castsShadows
        }
    }
    func legendRect(for key: EditorialKeyboardSceneKey, pixelScale: CGFloat) -> CGRect {
        let center = fullKeyCenter(key.id, pixelScale: pixelScale)
        let inset: CGFloat = isMacModel ? 0.15 : 0.34
        let usableWidth = key.size.width / baseline.unit - inset
        let capDepth = key.size.height / baseline.unit
        let depthInset = capDepth < 0.7 ? min(inset, capDepth * 0.30) : inset
        let usableDepth = max(0.18, capDepth - depthInset)
        let scale = Self.size.height / (2 * CGFloat(eye.camera!.orthographicScale))
        let elevation: CGFloat = 72 * .pi / 180
        let size = CGSize(width: usableWidth * scale, height: usableDepth * scale * sin(elevation))
        return CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
    }
    func snapshot() -> NSImage {
        SCNTransaction.flush()
        let image = renderer.snapshot(atTime:0,with:CGSize(width:Self.size.width*3,height:Self.size.height*3),antialiasingMode:.multisampling4X)
        image.size = Self.size; return image
    }
    func configureMacModel() throws {
        isMacModel = true
        keys = baseline.keys
        for node in layoutNodes.values { node.removeFromParentNode() }
        layoutNodes.removeAll()
        let length = depth
        for item in baseline.keys {
            let path = NSBezierPath()
            var transform = CGAffineTransform(a: 1 / baseline.unit, b: 0, c: 0, d: -1 / baseline.unit,
                tx: -item.size.width / (2 * baseline.unit), ty: item.size.height / (2 * baseline.unit))
            let top = item.topPath.copy(using: &transform)!
            top.applyWithBlock { element in
                let e = element.pointee
                switch e.type {
                case .moveToPoint: path.move(to: e.points[0])
                case .addLineToPoint: path.line(to: e.points[0])
                case .addQuadCurveToPoint:
                    let start = path.currentPoint
                    path.curve(to: e.points[1], controlPoint1: CGPoint(x: start.x + (e.points[0].x - start.x) * 2/3,
                        y: start.y + (e.points[0].y - start.y) * 2/3),
                        controlPoint2: CGPoint(x: e.points[1].x + (e.points[0].x - e.points[1].x) * 2/3,
                            y: e.points[1].y + (e.points[0].y - e.points[1].y) * 2/3))
                case .addCurveToPoint: path.curve(to: e.points[2], controlPoint1: e.points[0], controlPoint2: e.points[1])
                case .closeSubpath: path.close()
                @unknown default: break
                }
            }
            path.flatness = 0.006
            let shape = SCNShape(path: path, extrusionDepth: Self.macHeight)
            shape.chamferRadius = CGFloat(0.018); shape.chamferMode = .both
            shape.materials = [Self.material(NSColor(srgbRed: 0.96, green: 0.96, blue: 0.94, alpha: 1)),
                Self.material(NSColor(srgbRed: 0.74, green: 0.76, blue: 0.75, alpha: 1)),
                Self.material(NSColor(srgbRed: 0.74, green: 0.76, blue: 0.75, alpha: 1))]
            let node = SCNNode(geometry: shape)
            node.scale = SCNVector3(item.rect.width / item.size.width, item.rect.height / item.size.height, CGFloat(1))
            node.name = item.id; node.eulerAngles.x = -.pi / 2
            node.position = SCNVector3(item.rect.midX / baseline.unit - width / 2, CGFloat(0.075) + Self.macHeight / 2,
                                      item.rect.midY / baseline.unit - length / 2)
            scene.rootNode.addChildNode(node); layoutNodes[item.id] = node

        }
        setFront72ModelView(castsShadows: false)
    }
}
