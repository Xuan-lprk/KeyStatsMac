import Cocoa
import SceneKit
import Metal

struct GrowthKeyboard3DVisualState {
    let progress: Double
    let height: CGFloat
    let bevel: CGFloat
    let color: NSColor
}

struct GrowthKeyboard3DFrame {
    let image: NSImage
    let rects: [String: CGRect]
}

/// On-demand real geometry. There is intentionally no SCNView or rendering callback.
final class GrowthKeyboard3DScene {
    static let size = CGSize(width: 1280, height: 600)
    let baseline: EditorialKeyboardSceneLayout
    let imageSize: CGSize
    let maximumHeight: CGFloat
    private let scene = SCNScene()
    private let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
    private var caps: [String: SCNNode] = [:]
    private let groundMaterial = SCNMaterial()
    private(set) var canvasColor = NSColor(srgbRed: 242/255, green: 242/255, blue: 238/255, alpha: 1)
    private(set) var renderCount = 0
    private(set) var lastRenderMilliseconds: Double = 0
    var meshIDs: [ObjectIdentifier] { baseline.keys.map { ObjectIdentifier(caps[$0.id]!.geometry!) } }

    init(_ baseline: EditorialKeyboardSceneLayout, maximumHeight: CGFloat = GrowthKeyboard3DGeometry.maximumHeight, imageSize: CGSize = GrowthKeyboard3DScene.size) {
        self.baseline = baseline
        self.maximumHeight = maximumHeight
        self.imageSize = imageSize
        renderer.scene = scene
        renderer.isPlaying = false
        renderer.autoenablesDefaultLighting = false
        scene.background.contents = NSColor(srgbRed: 242/255, green: 242/255, blue: 238/255, alpha: 1)
        let width = baseline.boardSize.width / baseline.unit
        let length = baseline.boardSize.height / baseline.unit
        let camera = SCNCamera()
        camera.usesOrthographicProjection = true
        camera.orthographicScale = max((length + 0.45) / 2, (width + 0.7) / (2 * imageSize.width / imageSize.height))
        camera.zNear = 0.1; camera.zFar = 100
        camera.wantsHDR = false; camera.wantsExposureAdaptation = false; camera.bloomIntensity = 0
        let eye = SCNNode(); eye.camera = camera
        eye.position = SCNVector3(0, 30, 8)
        eye.look(at: SCNVector3(0, 0.09, 0))
        scene.rootNode.addChildNode(eye); renderer.pointOfView = eye
        let light = SCNLight()
        light.type = .directional; light.intensity = 720; light.color = NSColor.white
        light.castsShadow = false; light.shadowMode = .deferred
        light.shadowMapSize = NSSize(width: 2048, height: 2048)
        light.shadowSampleCount = 8; light.shadowRadius = 2
        light.shadowBias = 0.025; light.shadowColor = NSColor.black.withAlphaComponent(0.16)
        light.orthographicScale = width + 1
        light.zNear = 1; light.zFar = 35; light.maximumShadowDistance = 35
        light.forcesBackFaceCasters = true
        let keyLight = SCNNode(); keyLight.light = light
        keyLight.position = SCNVector3(-7, 14, -8); keyLight.look(at: SCNVector3Zero)
        scene.rootNode.addChildNode(keyLight)
        let fill = SCNNode(); fill.light = SCNLight()
        fill.light!.type = .ambient; fill.light!.intensity = 350; fill.light!.color = NSColor.white
        scene.rootNode.addChildNode(fill)
        let deckPath = NSBezierPath(roundedRect: CGRect(x: -(width + 0.28) / 2, y: -(length + 0.24) / 2,
            width: width + 0.28, height: length + 0.24), xRadius: 19 / baseline.unit, yRadius: 19 / baseline.unit)
        deckPath.flatness = 0.003
        let deck = SCNShape(path: deckPath, extrusionDepth: 0.06)
        deck.chamferRadius = 0.01
        deck.firstMaterial = Self.material(baseline.deckColor)
        let tray = SCNNode(geometry: deck); tray.position.y = 0.045
        tray.eulerAngles.x = -.pi / 2
        scene.rootNode.addChildNode(tray)
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
            let shape = SCNShape(path: path, extrusionDepth: GrowthKeyboard3DGeometry.minimumHeight)
            shape.chamferRadius = GrowthKeyboard3DGeometry.bevel(0); shape.chamferMode = .both
            shape.firstMaterial = Self.material(baseline.usageColor(0))
            let node = SCNNode(geometry: shape)
            node.scale = SCNVector3(item.rect.width / item.size.width, item.rect.height / item.size.height, CGFloat(1))
            node.name = item.id; node.eulerAngles.x = -.pi / 2
            node.position = SCNVector3(item.rect.midX / baseline.unit - width / 2, CGFloat(0.075) + GrowthKeyboard3DGeometry.minimumHeight / 2,
                                      item.rect.midY / baseline.unit - length / 2)
            scene.rootNode.addChildNode(node); caps[item.id] = node
        }
        let ground = SCNPlane(width: 60, height: 60)
        ground.firstMaterial = groundMaterial
        groundMaterial.diffuse.contents = canvasColor
        // A neutral studio sweep: lighting/shadows affect the object, not a visible rectangular backdrop.
        ground.firstMaterial?.lightingModel = .constant
        let floor = SCNNode(geometry: ground); floor.eulerAngles.x = -.pi / 2; floor.castsShadow = false
        scene.rootNode.addChildNode(floor)
    }

    private static func material(_ color: NSColor) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .blinn
        m.diffuse.contents = color; m.ambient.contents = color
        m.specular.contents = NSColor(white: 0.12, alpha: 1); m.shininess = 0.15
        return m
    }

    /// One explicit snapshot per cache miss, only requested by the visible production view.
    func render(values: [GrowthKeyboardKeyUsage], backgroundColor: NSColor) -> GrowthKeyboard3DFrame {
        let states = Dictionary(uniqueKeysWithValues: values.map {
            ($0.id, GrowthKeyboard3DVisualState(progress: $0.progress,
                height: GrowthKeyboard3DGeometry.height($0.progress),
                bevel: GrowthKeyboard3DGeometry.bevel($0.progress), color: baseline.usageColor($0.progress)))
        })
        let pixelScale: CGFloat = 2
        canvasColor = backgroundColor
        scene.background.contents = backgroundColor
        groundMaterial.diffuse.contents = backgroundColor
        SCNTransaction.begin(); SCNTransaction.disableActions = true
        for key in baseline.keys {
            let state = states[key.id]!
            let node = caps[key.id]!, shape = node.geometry as! SCNShape
            if shape.extrusionDepth != state.height { shape.extrusionDepth = state.height }
            if shape.chamferRadius != state.bevel { shape.chamferRadius = state.bevel }
            node.position.y = CGFloat(0.075) + state.height / 2
            let color = state.color
            let material = shape.firstMaterial!
            material.diffuse.contents = color; material.ambient.contents = color
            let p = state.progress
            material.shininess = CGFloat(0.10 + 0.12 * p)
            material.specular.contents = NSColor(white: 0.09 + 0.07 * p, alpha: 1)
        }
        SCNTransaction.commit()
        let start = ProcessInfo.processInfo.systemUptime
        let image = renderer.snapshot(atTime: 0, with: CGSize(width: imageSize.width * pixelScale, height: imageSize.height * pixelScale),
                                      antialiasingMode: .multisampling4X)
        image.size = imageSize
        lastRenderMilliseconds = (ProcessInfo.processInfo.systemUptime - start) * 1000
        renderCount += 1
        var rects: [String: CGRect] = [:]
        let width = baseline.boardSize.width / baseline.unit, length = baseline.boardSize.height / baseline.unit
        for key in baseline.keys {
            let points = [CGPoint(x: key.rect.minX, y: key.rect.minY), CGPoint(x: key.rect.maxX, y: key.rect.minY),
                          CGPoint(x: key.rect.maxX, y: key.rect.maxY), CGPoint(x: key.rect.minX, y: key.rect.maxY)].map { point in
                let p = renderer.projectPoint(SCNVector3(point.x / baseline.unit - width / 2,
                    CGFloat(0.075) + states[key.id]!.height, point.y / baseline.unit - length / 2))
                return CGPoint(x: p.x / pixelScale, y: imageSize.height - p.y / pixelScale)
            }
            rects[key.id] = points.reduce(CGRect.null) { $0.union(CGRect(origin: $1, size: .zero)) }
        }
        return GrowthKeyboard3DFrame(image: image, rects: rects)
    }

    /// Actual screen-space lift divided by one ordinary-key width; independent of viewport scale.
    func projectedLiftRatio() -> Double {
        let base = renderer.projectPoint(SCNVector3(0, CGFloat(0.075) + GrowthKeyboard3DGeometry.minimumHeight, 0))
        let top = renderer.projectPoint(SCNVector3(0, CGFloat(0.075) + maximumHeight, 0))
        let edge = renderer.projectPoint(SCNVector3(1, CGFloat(0.075) + GrowthKeyboard3DGeometry.minimumHeight, 0))
        return Double(abs(top.y - base.y) / abs(edge.x - base.x))
    }
}
