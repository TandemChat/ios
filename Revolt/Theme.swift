//
//  Theme.swift
//  Revolt
//
//  Created by Angelo on 31/10/2023.
//

import Foundation
import SwiftUI
import CodableWrapper
import Parsing

func parseHex(hex: String) -> (Double, Double, Double, Double) {
    let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    var int: UInt64 = 0
    Scanner(string: hex).scanHexInt64(&int)
    let r, g, b, a: UInt64
    switch hex.count {
        case 3: // RGB (12-bit)
            (r, g, b, a) = ((int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17, 255)
        case 6: // RGB (24-bit)
            (r, g, b, a) = (int >> 16, int >> 8 & 0xFF, int & 0xFF, 255)
        case 8: // RGBA (32-bit)
            (r, g, b, a) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (r, g, b, a) = (1, 1, 1, 0)
    }
    
    return (
        Double(r) / 255,
        Double(g) / 255,
        Double(b) / 255,
        Double(a) / 255
    )
}

enum ConstantType {
    case deg, grad, rad, turn
}

let angleParser = Parse(input: Substring.self) {
    Double.parser()
    OneOf {
        "deg".map { ConstantType.deg }
        "grad".map { ConstantType.grad }
        "rad".map { ConstantType.rad }
        "turn".map { ConstantType.turn }
    }
}

enum DirectionType {
    case left, right, top, bottom
}

let directionParser = Parse(input: Substring.self) {
    OneOf {
        "left".map { DirectionType.left }
        "right".map { DirectionType.right }
        "top".map { DirectionType.top }
        "bottom".map { DirectionType.bottom }
    }
}

enum ColorType {
    case name(Substring)
    case hex(Substring)
    case rgba(Int, Int, Int, Int)
}

let colorParser = Parse(input: Substring.self) {
    OneOf {
        Parse {
            "#"
            CharacterSet(charactersIn: "ABCDEFabcdef1234567890")
        }.map(ColorType.hex)

        Parse {
            "rgb("
            Many(3) {
                Int.parser()
            } separator: {
                Many { " " }
                ","
                Many { " " }
            }
            ")"
        }.map { cs in ColorType.rgba(cs[0], cs[1], cs[2], 255) }
        
        CharacterSet.alphanumerics
            .map(ColorType.name)
    }
}

struct Length {
    enum LengthType {
        case px
    }
    
    var amount: Int
    var type: LengthType
}

let lengthParser = Parse(input: Substring.self) {
    Length(amount: $0, type: $1)
} with: {
    Digits()
    OneOf {
        "px".map { Length.LengthType.px }
    }
}

let percentageParser = Parse(input: Substring.self) {
    Digits()
    "%"
}

enum PercentageType {
    case length(Length)
    case percentage(Int)
}

struct ColorStop {
    var color: ColorType
    var percentage: PercentageType?
}

enum AngleType {
    case constant(Double, ConstantType)
    case direction(DirectionType, DirectionType?)
}

struct LinearGradiant {
    var angle: AngleType?
    var stops: [ColorStop]
}

let linearGradiantParser = Parse(input: Substring.self) { inp in
    LinearGradiant(angle: inp.0, stops: inp.1)
} with: {
    "linear-gradient("
    Optionally {
        OneOf {
            angleParser.map { AngleType.constant($0.0, $0.1) }
            Parse {
                "to"
                directionParser
                Optionally {
                    directionParser
                }
            }.map { AngleType.direction($0.0, $0.1) }
        }
    }
    
    Skip {
        Many { " " }
        ","
        Many { " " }
    }
    
    Many(2...) {
        Parse {
            colorParser
            Skip { Many { " " } }
            Optionally {
                OneOf {
                    lengthParser.map(PercentageType.length)
                    percentageParser.map(PercentageType.percentage)
                }
            }
        }.map { (c, p) in ColorStop(color: c, percentage: p) }
    } separator: {
        Many { " " }
        ","
        Many { " " }
    }
    ")"
}

enum CssColor {
    case linear_gradiant(LinearGradiant)
    case simple(ColorType)
    case variable(Substring)
}

let CSSColorParser = Parse(input: Substring.self) {
    OneOf {
        linearGradiantParser.map(CssColor.linear_gradiant)
        colorParser.map(CssColor.simple)
        Parse {
            "var("
            CharacterSet.alphanumerics
            ")"
        }.map(CssColor.variable)
    }
}

func resolveColor(color: ColorType) -> Color {
    switch color {
        case .name(let name):
            switch name {
                case "red":
                    return .red
                case "green":
                    return .green
                case "blue":
                    return .blue
                case "purple":
                    return Color(red: 128.0 / 255.0, green: 0, blue: 128.0 / 255.0)
                case "orange":
                    return Color(red: 1, green: 165.0 / 255, blue: 0)
                default:
                    return .black
            }
            
        case .hex(let hex):
            let (r, g, b, a) = parseHex(hex: String(hex))
            return Color(red: r, green: g, blue: b, opacity: a)
            
        case .rgba(let r, let g, let b, let a):
            return Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}

func resolveVariable(currentTheme: Theme, name: Substring) -> AnyShapeStyle {
    switch name {
        case "--accent":
            return AnyShapeStyle(currentTheme.accent)
        case "--foreground":
            return AnyShapeStyle(currentTheme.foreground)
        case "--background":
            return AnyShapeStyle(currentTheme.background)
        default:
            return AnyShapeStyle(.black)
    }
}

func unitSquareIntersectionPoint(angle: Double) -> UnitPoint {
    var angle = angle
    
    while angle > 360.0 {
        angle -= 360.0
    }
    
    while angle < 0.0 {
        angle += 360.0
    }
    
    if angle < 45.0 || angle >= 315 {
        var degreeToConsider = angle
        
        if degreeToConsider < 45.0 {
            degreeToConsider = angle +  360.0
        }
        
        let degreeProportion = (degreeToConsider - 315.0) / 90.0
        
        return UnitPoint(x: 1.0, y: 1.0 - degreeProportion)
    } else if angle < 135.0 {
        
        let degreeProportion = (angle - 45.0) / 90.0
        
        return UnitPoint(x: 1.0 - degreeProportion, y: 0.0)
    } else if angle < 225.0 {
        let degreeProportion = (angle - 135) / 90.0
        
        return UnitPoint(x: 0.0, y: degreeProportion)
    } else if angle < 315.0 {
        
        let degreeProportion = (angle - 225) / 90.0
        
        return UnitPoint(x: degreeProportion, y: 1.0)
    }
    
    return .zero
}

func directionToUnits(d1: DirectionType, d2: DirectionType?) -> (UnitPoint, UnitPoint) {
    switch (d1, d2) {
        case (.left, .top), (.top, .left):
            return (.topLeading, .bottomTrailing)
        case (.left, .bottom), (.bottom, .left):
            return (.bottomLeading, .topTrailing)
        case (.right, .top), (.top, .right):
            return (.topTrailing, .bottomLeading)
        case (.right, .bottom), (.bottom, .right):
            return (.bottomTrailing, .topLeading)
        case (.left, nil):
            return (.leading, .trailing)
        case (.right, nil):
            return (.trailing, .leading)
        case (.top, nil):
            return (.top, .bottom)
        case (.bottom, nil):
            return (.bottom, .top)
        default:
            return directionToUnits(d1: d1, d2: nil)
    }
}

func parseCSSColor(currentTheme: Theme, input: String) -> AnyShapeStyle {
    do {
        let output = try CSSColorParser.parse(input)
        
        switch output {
            case .simple(let color):
                return AnyShapeStyle(resolveColor(color: color))
                
            case .variable(let name):
                return resolveVariable(currentTheme: currentTheme, name: name)
                
            case .linear_gradiant(let grad):
                var start: UnitPoint
                var end: UnitPoint
                
                switch grad.angle {
                    case .direction(let d1, let d2):
                        (start, end) = directionToUnits(d1: d1, d2: d2)
                    
                    case .constant(let value, let ty):
                        switch ty {
                            case .deg:
                                start = unitSquareIntersectionPoint(angle: value + 90.0)
                                end = unitSquareIntersectionPoint(angle: value - 90.0)
                            case .grad:
                                start = unitSquareIntersectionPoint(angle: (value * 0.9) + 90.0)
                                end = unitSquareIntersectionPoint(angle: (value * 0.9) - 90.0)

                            case .rad:
                                start = unitSquareIntersectionPoint(angle: (value * (180/Double.pi)) + 90.0)
                                end = unitSquareIntersectionPoint(angle: (value * (180/Double.pi)) - 90.0)

                            case .turn:
                                start = unitSquareIntersectionPoint(angle: (value * 360.0) + 90.0)
                                end = unitSquareIntersectionPoint(angle: (value * 360.0) - 90.0)
                        }
                    case nil:
                        start = .top
                        end = .bottom
                }

                var colors = grad.stops.map { resolveColor(color: $0.color) }
                
                return AnyShapeStyle(LinearGradient(colors: colors, startPoint: start, endPoint: end))
        }
    } catch {
        return AnyShapeStyle(Color.black)
    }
}

@Codable
struct ThemeColor: Equatable, ShapeStyle, View {
    var r: Double
    var g: Double
    var b: Double
    var a: Double

    init(hex: String) {
        (r, g, b, a) = parseHex(hex: hex)
    }

    mutating func set(with: Color.Resolved) {
        self.r = Double(with.red)

        if self.r == Double.infinity {
            self.r = 1.0
        }

        self.g = Double(with.green)

        if self.g == Double.infinity {
            self.g = 1.0
        }

        self.b = Double(with.blue)

        if self.b == Double.infinity {
            self.b = 1.0
        }

        self.a = Double(with.opacity)

        if self.a == Double.infinity {
            self.a = 1.0
        }

    }

    func resolve(in environment: EnvironmentValues) -> Color.Resolved {
        color.resolve(in: environment)
    }

    var color: Color {
        Color(red: r, green: g, blue: b, opacity: a)
    }

    static var white: ThemeColor = ThemeColor(hex: "#FFFFFFFF")
    static var black: ThemeColor = ThemeColor(hex: "#000000FF")
}

@Codable
struct Theme: Codable, Equatable {
    var accent: ThemeColor = ThemeColor(hex: "#FD7771FF")
    var background: ThemeColor = ThemeColor.white
    var background2: ThemeColor = ThemeColor.white
    var foreground: ThemeColor = ThemeColor.black
    var foreground2: ThemeColor = ThemeColor(hex: "#3A3A3AFF")
    var foreground3: ThemeColor = ThemeColor(hex: "#1F1F1FFF")
    var messageBox: ThemeColor = ThemeColor.white
    var messageBoxBackground: ThemeColor = ThemeColor.white
    var topBar: ThemeColor = ThemeColor(hex: "#FFFFFFAA")
    var messageBoxBorder: ThemeColor = ThemeColor.black
    var shouldFollowiOSTheme: Bool = false

    static var light: Theme {
        Theme(
            accent: ThemeColor(hex: "#FD7771FF"),
            background: ThemeColor.white,
            background2: ThemeColor(hex: "#F5F5F5FF"),
            foreground: ThemeColor.black,
            foreground2: ThemeColor(hex: "#1F1F1FFF"),
            foreground3: ThemeColor(hex: "#3A3A3AFF"),
            messageBox: ThemeColor.white,
            messageBoxBackground: ThemeColor.white,
            topBar: ThemeColor(hex: "#FFFFFFEE"),
            messageBoxBorder: ThemeColor.black,
            shouldFollowiOSTheme: false
        )
    }

    static var dark: Theme {
        Theme(
            accent: ThemeColor(hex: "#FD7771FF"),
            background: ThemeColor(hex: "#191919FF"),
            background2: ThemeColor(hex:"#242424FF"),
            foreground: ThemeColor.white,
            foreground2: ThemeColor(hex: "#C8C8C8FF"),
            foreground3: ThemeColor(hex: "#848484FF"),
            messageBox: ThemeColor(hex:"#363636FF"),
            messageBoxBackground: ThemeColor(hex:"#363636FF"),
            topBar: ThemeColor(hex: "#191919EE"),
            messageBoxBorder: ThemeColor.white,
            shouldFollowiOSTheme: false
        )
    }
}
