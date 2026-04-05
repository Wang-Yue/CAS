import Foundation

// MARK: - Pretty Printer

public struct PrettyPrinter {
    public static func format(_ expr: Expr) -> String {
        formatExpr(expr, parentPrecedence: 0)
    }

    private static func formatExpr(_ expr: Expr, parentPrecedence: Int) -> String {
        switch expr {
        case .integer(let n):
            return "\(n)"

        case .rational(let p, let q):
            return "\(p)/\(q)"

        case .real(let v):
            if v == v.rounded() && Swift.abs(v) < 1e15 {
                return "\(Int(v))"
            }
            return String(format: "%.6g", v)

        case .symbol(let name):
            return name

        case .constant(let c):
            switch c {
            case .pi: return "pi"
            case .e: return "e"
            case .infinity: return "oo"
            case .negInfinity: return "-oo"
            case .i: return "i"
            }

        case .add(let a, let b):
            let prec = 1
            let left = formatExpr(a, parentPrecedence: prec)
            let right: String

            // Handle subtraction display: a + (-1 * b) => a - b
            if case .mul(.integer(let c), let inner) = b, c < 0 {
                if c == -1 {
                    right = "- " + formatExpr(inner, parentPrecedence: prec)
                } else {
                    right = "- " + formatExpr(Expr.mul(.integer(-c), inner), parentPrecedence: prec)
                }
                let result = "\(left) \(right)"
                return parentPrecedence > prec ? "(\(result))" : result
            }

            // Handle negative integer addition: a + (-n)
            if case .integer(let n) = b, n < 0 {
                let result = "\(left) - \(-n)"
                return parentPrecedence > prec ? "(\(result))" : result
            }

            let result = "\(left) + \(formatExpr(b, parentPrecedence: prec))"
            return parentPrecedence > prec ? "(\(result))" : result

        case .mul(let a, let b):
            let prec = 2

            // Handle -1 * x => -x
            if case .integer(-1) = a {
                let inner = formatExpr(b, parentPrecedence: prec)
                let result = "-\(inner)"
                return parentPrecedence > prec ? "(\(result))" : result
            }

            // Handle division display: a * b^(-1) => a/b
            if case .pow(let base, .integer(-1)) = b {
                let left = formatExpr(a, parentPrecedence: 3)
                let right = formatExpr(base, parentPrecedence: 3)
                let result = "\(left)/\(right)"
                return parentPrecedence > prec ? "(\(result))" : result
            }

            // Handle a * (1/n) => a/n  and  a * (p/q) => p*a/q
            if case .rational(let p, let q) = b, q != 1 {
                if p == 1 {
                    let left = formatExpr(a, parentPrecedence: 3)
                    let result = "\(left)/\(q)"
                    return parentPrecedence > prec ? "(\(result))" : result
                }
                if p == -1 {
                    let left = formatExpr(a, parentPrecedence: 3)
                    let result = "-\(left)/\(q)"
                    return parentPrecedence > prec ? "(\(result))" : result
                }
            }
            if case .rational(let p, let q) = a, q != 1 {
                if p == 1 {
                    let right = formatExpr(b, parentPrecedence: 3)
                    let result = "\(right)/\(q)"
                    return parentPrecedence > prec ? "(\(result))" : result
                }
                if p == -1 {
                    let right = formatExpr(b, parentPrecedence: 3)
                    let result = "-\(right)/\(q)"
                    return parentPrecedence > prec ? "(\(result))" : result
                }
            }

            // Handle a * b^(-n) => a/b^n
            if case .pow(let base, .mul(.integer(-1), let exp)) = b {
                let left = formatExpr(a, parentPrecedence: 3)
                let right = formatExpr(Expr.pow(base, exp), parentPrecedence: 3)
                let result = "\(left)/\(right)"
                return parentPrecedence > prec ? "(\(result))" : result
            }
            if case .pow(let base, .integer(let n)) = b, n < 0 {
                let left = formatExpr(a, parentPrecedence: 3)
                let right = formatExpr(Expr.pow(base, .integer(-n)), parentPrecedence: 3)
                let result = "\(left)/\(right)"
                return parentPrecedence > prec ? "(\(result))" : result
            }

            let left = formatExpr(a, parentPrecedence: prec)
            let right = formatExpr(b, parentPrecedence: prec)
            let result = "\(left)*\(right)"
            return parentPrecedence > prec ? "(\(result))" : result

        case .pow(let base, let exp):
            let prec = 4
            // sqrt display
            if case .rational(1, 2) = exp {
                return "sqrt(\(formatExpr(base, parentPrecedence: 0)))"
            }
            let left = formatExpr(base, parentPrecedence: prec + 1)
            let right = formatExpr(exp, parentPrecedence: 0)
            let result = "\(left)^\(right)"
            return parentPrecedence > prec ? "(\(result))" : result

        case .function(let name, let args):
            let argStrs = args.map { formatExpr($0, parentPrecedence: 0) }
            return "\(name)(\(argStrs.joined(separator: ", ")))"

        case .matrix(let m):
            return m.description
        }
    }
}

// MARK: - LaTeX Output

extension Expr {
    public var latex: String {
        LaTeXPrinter.format(self)
    }
}

public struct LaTeXPrinter {
    public static func format(_ expr: Expr) -> String {
        formatExpr(expr, parentPrecedence: 0)
    }

    private static func formatExpr(_ expr: Expr, parentPrecedence: Int) -> String {
        switch expr {
        case .integer(let n): return "\(n)"
        case .rational(let p, let q): return "\\frac{\(p)}{\(q)}"
        case .real(let v): return String(format: "%.6g", v)
        case .symbol(let name):
            if name.count == 1 { return name }
            return "\\text{\(name)}"
        case .constant(let c):
            switch c {
            case .pi: return "\\pi"
            case .e: return "e"
            case .infinity: return "\\infty"
            case .negInfinity: return "-\\infty"
            case .i: return "i"
            }
        case .add(let a, let b):
            if case .mul(.integer(let c), let inner) = b, c < 0 {
                if c == -1 {
                    return "\(formatExpr(a, parentPrecedence: 1)) - \(formatExpr(inner, parentPrecedence: 1))"
                }
                return "\(formatExpr(a, parentPrecedence: 1)) - \(formatExpr(Expr.mul(.integer(-c), inner), parentPrecedence: 1))"
            }
            return "\(formatExpr(a, parentPrecedence: 1)) + \(formatExpr(b, parentPrecedence: 1))"
        case .mul(let a, let b):
            if case .integer(-1) = a {
                return "-\(formatExpr(b, parentPrecedence: 2))"
            }
            if case .pow(let base, .integer(-1)) = b {
                return "\\frac{\(formatExpr(a, parentPrecedence: 0))}{\(formatExpr(base, parentPrecedence: 0))}"
            }
            if case .pow(let base, .integer(let n)) = b, n < 0 {
                return "\\frac{\(formatExpr(a, parentPrecedence: 0))}{\(formatExpr(Expr.pow(base, .integer(-n)), parentPrecedence: 0))}"
            }
            return "\(formatExpr(a, parentPrecedence: 2)) \\cdot \(formatExpr(b, parentPrecedence: 2))"
        case .pow(let base, let exp):
            if case .rational(1, 2) = exp {
                return "\\sqrt{\(formatExpr(base, parentPrecedence: 0))}"
            }
            return "\(formatExpr(base, parentPrecedence: 4))^{\(formatExpr(exp, parentPrecedence: 0))}"
        case .function(let name, let args):
            let argStr = args.map { formatExpr($0, parentPrecedence: 0) }.joined(separator: ", ")
            let latexName: String
            switch name {
            case "sin", "cos", "tan", "log", "exp", "sinh", "cosh", "tanh":
                latexName = "\\\(name)"
            case "asin": latexName = "\\arcsin"
            case "acos": latexName = "\\arccos"
            case "atan": latexName = "\\arctan"
            case "factorial": return "\(formatExpr(args[0], parentPrecedence: 5))!"
            case "binomial": return "\\binom{\(formatExpr(args[0], parentPrecedence: 0))}{\(formatExpr(args[1], parentPrecedence: 0))}"
            case "abs": return "\\left| \(argStr) \\right|"
            default: latexName = "\\operatorname{\(name)}"
            }
            return "\(latexName)\\left(\(argStr)\\right)"
        case .matrix(let m):
            let rows = m.elements.map { row in
                row.map { formatExpr($0, parentPrecedence: 0) }.joined(separator: " & ")
            }
            return "\\begin{pmatrix}\n" + rows.joined(separator: " \\\\\n") + "\n\\end{pmatrix}"
        }
    }
}
