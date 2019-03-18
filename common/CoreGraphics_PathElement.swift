/**
Swiftified version of CGPathElement. WIP.

This component is part of https://github.com/andreyvit/building-blocks-appleos.
To install these building blocks, copy some into your project and check back
for updates regularly. Each component follows semantic versioning. This may seem
like too much work, but we believe the manual approach is appropriately hands-on.

© 2018–2019 Andrey Tarantsov <andrey@tarantsov.com>, published under the terms of
the MIT license.

- v0.0.1 (2019-03-18): initial snippet
*/
public enum PathElement: CustomDebugStringConvertible {
    case moveTo(CGPoint)
    case lineTo(CGPoint)
    case quadCurveTo(QuadCurve)
    case curveTo(Curve)
    case closeSubpath

    public struct QuadCurve {
        var control: CGPoint
        var destination: CGPoint
    }
    
    public struct Curve {
        var control1, control2: CGPoint
        var destination: CGPoint
    }

    public init(_ element: CGPathElement) {
        switch element.type {
        case .moveToPoint:
            self = .moveTo(element.points.pointee)
        case .addLineToPoint:
            self = .lineTo(element.points.pointee)
        case .addQuadCurveToPoint:
            let points = UnsafeBufferPointer(start: element.points, count: 2)
            self = .quadCurveTo(QuadCurve(control: points[0], destination: points[1]))
        case .addCurveToPoint:
            let points = UnsafeBufferPointer(start: element.points, count: 3)
            self = .curveTo(Curve(control1: points[0], control2: points[1], destination: points[2]))
        case .closeSubpath:
            self = .closeSubpath
        }
    }
    
    public var debugDescription: String {
        switch self {
        case .moveTo(let point):
            return "moveto \(String(reflecting: point))"
        case .lineTo(let point):
            return "lineto \(String(reflecting: point))"
        case .quadCurveTo(let segment):
            return "quadcurveto \(String(reflecting: segment.destination)) c=\(String(reflecting: segment.control))"
        case .curveTo(let segment):
            return "curveto \(String(reflecting: segment.destination)) c1=\(String(reflecting: segment.control1)) c2=\(String(reflecting: segment.control2))"
        case .closeSubpath:
            return "close"
        }
    }
}
