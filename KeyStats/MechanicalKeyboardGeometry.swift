import Cocoa
import SceneKit
import simd

struct MechanicalKeycapMesh {
    let geometry: SCNGeometry
    let height: CGFloat
    let dish: CGFloat
    let width: CGFloat
    let depth: CGFloat
    let vertexCount: Int
    let triangleCount: Int
    let minimumY: Float
    let maximumY: Float
    static let segments = 64

    init(width: CGFloat, depth: CGFloat, height: CGFloat, spacebar: Bool) {
        self.width = width; self.depth = depth; self.height = height
        let topW = width - min(0.25, width * 0.25), topD = depth - min(0.25, depth * 0.25)
        let dish = min(spacebar ? 0.022 : 0.060, height * 0.22)
        self.dish = dish
        let roll = min(0.042, height * 0.13), tilt = min(0.036, height * 0.10)
        func top(_ z: CGFloat) -> CGFloat {
            let q = min(1, abs(z / (topD / 2)))
            // A/Return/arrows use a cylindrical scoop. The wide spacebar has a
            // restrained convex crown, rather than an implausible deep basin.
            return height + tilt * z + (spacebar ? dish : -dish) * (1 - q * q)
        }
        func outline(_ w: CGFloat, _ d: CGFloat, _ radius: CGFloat) -> [CGPoint] {
            let r = min(radius, w / 2, d / 2)
            let corners: [(CGFloat, CGFloat)] = [(w/2-r,d/2-r),(-w/2+r,d/2-r),(-w/2+r,-d/2+r),(w/2-r,-d/2+r)]
            return corners.enumerated().flatMap { c, center -> [CGPoint] in
                let curve = (0..<8).map { j -> CGPoint in
                    let a = CGFloat(c) * .pi / 2 + CGFloat(j) / 8 * .pi / 2
                    return CGPoint(x: center.0 + r * cos(a), y: center.1 + r * sin(a))
                }
                let angle = CGFloat(c+1) * .pi/2, next = corners[(c+1)%4]
                let start = CGPoint(x:center.0+r*cos(angle),y:center.1+r*sin(angle))
                let end = CGPoint(x:next.0+r*cos(angle),y:next.1+r*sin(angle))
                return curve + (0..<8).map { j in
                    let t = CGFloat(j)/8
                    return CGPoint(x:start.x+(end.x-start.x)*t,y:start.y+(end.y-start.y)*t)
                }
            }
        }
        var vertices: [SCNVector3] = [], uv: [CGPoint] = [], regions = [[UInt32]](repeating: [], count: 4)
        func ring(w: CGFloat, d: CGFloat, radius: CGFloat, y: (CGFloat) -> CGFloat) {
            for p in outline(w, d, radius) {
                vertices.append(SCNVector3(p.x, y(p.y), p.y))
                uv.append(CGPoint(x: p.x / topW + 0.5, y: 0.5 + p.y / topD))
            }
        }
        ring(w: width-0.025, d: depth-0.025, radius: 0.07) { _ in 0 }
        ring(w: width, d: depth, radius: 0.085) { _ in min(0.018, height * 0.07) }
        ring(w: width-0.012, d: depth-0.012, radius: 0.08) { _ in height * 0.12 }
        ring(w: topW+0.055, d: topD+0.055, radius: 0.075) { top($0) - roll * 0.90 }
        ring(w: topW+0.032, d: topD+0.032, radius: 0.072) { top($0) - roll * 0.30 }
        ring(w: topW, d: topD, radius: 0.065) { top($0) }
        for scale: CGFloat in [0.90, 0.80, 0.65, 0.50, 0.35, 0.20, 0.08] {
            ring(w: topW * scale, d: topD * scale, radius: 0.065 * scale) { top($0) }
        }
        func vector(_ index: Int) -> SIMD3<Float> { let p = vertices[index]; return SIMD3(Float(p.x), Float(p.y), Float(p.z)) }
        func triangle(_ a: Int, _ b: Int, _ c: Int, region: Int) {
            let n = simd_cross(vector(b)-vector(a), vector(c)-vector(a))
            let center = (vector(a)+vector(b)+vector(c)) / 3
            let flip: Bool = region <= 1 ? n.y < 0 : region == 2 ? n.x * center.x + n.z * center.z < 0 : n.y > 0
            regions[region] += [UInt32(a), UInt32(flip ? c : b), UInt32(flip ? b : c)]
        }
        let rings = vertices.count / Self.segments
        for ringIndex in 0..<(rings - 1) {
            let region = ringIndex == 0 ? 3 : ringIndex < 3 ? 2 : ringIndex < 5 ? 1 : 0
            for j in 0..<Self.segments {
                let a = ringIndex * Self.segments + j, b = ringIndex * Self.segments + (j+1) % Self.segments
                let c = a + Self.segments, d = b + Self.segments
                triangle(a, c, b, region: region); triangle(b, c, d, region: region)
            }
        }
        let topCenter = vertices.count; vertices.append(SCNVector3(0, top(0), 0)); uv.append(CGPoint(x: 0.5, y: 0.5))
        let bottomCenter = vertices.count; vertices.append(SCNVector3Zero); uv.append(.zero)
        for j in 0..<Self.segments {
            triangle((rings-1)*Self.segments+j, topCenter, (rings-1)*Self.segments+(j+1)%Self.segments, region: 0)
            triangle(j, bottomCenter, (j+1)%Self.segments, region: 3)
        }
        var normals = [SIMD3<Float>](repeating: .zero, count: vertices.count)
        for indices in regions {
            for i in stride(from: 0, to: indices.count, by: 3) {
                let a = Int(indices[i]), b = Int(indices[i+1]), c = Int(indices[i+2])
                let n = simd_cross(vector(b)-vector(a), vector(c)-vector(a))
                normals[a] += n; normals[b] += n; normals[c] += n
            }
        }
        let ns = normals.enumerated().map { index,n -> SCNVector3 in
            let v: SIMD3<Float>
            if index >= 5*Self.segments && index != bottomCenter {
                // Analytic cylindrical normals avoid radial triangle-fan facets.
                let z = CGFloat(vertices[index].z)
                let derivative = tilt + (spacebar ? -1 : 1)*2*dish*z/pow(topD/2,2)
                v = simd_normalize(SIMD3<Float>(0,1,-Float(derivative)))
            } else { v = simd_length_squared(n) > 1e-16 ? simd_normalize(n) : SIMD3<Float>(0,1,0) }
            return SCNVector3(v.x,v.y,v.z)
        }
        geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: ns), SCNGeometrySource(textureCoordinates: uv)],
            elements: regions.map { SCNGeometryElement(indices: $0, primitiveType: .triangles) })
        vertexCount = vertices.count; triangleCount = regions.reduce(0) { $0 + $1.count / 3 }
        minimumY = vertices.map { Float($0.y) }.min()!; maximumY = vertices.map { Float($0.y) }.max()!
    }
}

struct MechanicalPressProfile {
    let travel: CGFloat
    let down: Double
    let hold: Double
    let duration: Double
    static let light = MechanicalPressProfile(travel: 0.10, down: 0.035, hold: 0.010, duration: 0.160)
    static let balanced = MechanicalPressProfile(travel: 0.16, down: 0.045, hold: 0.015, duration: 0.190)
    static let deep = MechanicalPressProfile(travel: 0.18, down: 0.055, hold: 0.020, duration: 0.220)
    static let all = [light, balanced, deep]
    func weight(_ elapsed: Double, initial: Double = 0) -> Double {
        guard elapsed >= 0, elapsed < duration else { return 0 }
        func smooth(_ t: Double) -> Double { t * t * (3 - 2 * t) }
        if elapsed < down { return initial + (1 - initial) * smooth(elapsed / down) }
        if elapsed < down + hold { return 1 }
        return 1 - smooth((elapsed - down - hold) / (duration - down - hold))
    }
}
