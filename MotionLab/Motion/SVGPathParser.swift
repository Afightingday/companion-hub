import SwiftUI

/// 极简 SVG path 解析:仅支持绝对 M / L / C / Z(potrace 描摹输出)。
/// 「M x y」后的后续坐标对按 SVG 规范视为隐式 L;子路径由填充自动闭合。
enum SVGPathParser {
    static func parse(_ d: String) -> Path {
        var path = Path()
        let chars = Array(d)
        var i = 0
        var lastCmd: Character = " "

        func skipSeparators() {
            while i < chars.count, chars[i] == " " || chars[i] == "," || chars[i] == "\n" || chars[i] == "\t" || chars[i] == "\r" {
                i += 1
            }
        }

        func number() -> CGFloat? {
            skipSeparators()
            var s = ""
            while i < chars.count {
                let ch = chars[i]
                if ch.isNumber || ch == "." || ch == "-" || ch == "+" {
                    s.append(ch)
                    i += 1
                } else {
                    break
                }
            }
            guard !s.isEmpty, let v = Double(s) else { return nil }
            return CGFloat(v)
        }

        func point() -> CGPoint? {
            guard let x = number(), let y = number() else { return nil }
            return CGPoint(x: x, y: y)
        }

        while i < chars.count {
            skipSeparators()
            guard i < chars.count else { break }
            let ch = chars[i]
            let cmd: Character
            if ch.isLetter {
                cmd = ch
                i += 1
            } else {
                cmd = lastCmd    // 同一指令的连续坐标组
            }
            switch cmd {
            case "M":
                guard let p = point() else { return path }
                path.move(to: p)
                lastCmd = "L"    // M 之后的连续坐标对是隐式 L
            case "L":
                guard let p = point() else { return path }
                path.addLine(to: p)
                lastCmd = "L"
            case "C":
                guard let c1 = point(), let c2 = point(), let e = point() else { return path }
                path.addCurve(to: e, control1: c1, control2: c2)
                lastCmd = "C"
            case "Z", "z":
                path.closeSubpath()
                lastCmd = " "
            default:
                return path      // 不认识的指令:返回已解析部分
            }
        }
        return path
    }
}
