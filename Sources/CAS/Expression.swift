import Foundation

// MARK: - Core Expression Type

public indirect enum Expr: Hashable, CustomStringConvertible {
    case integer(Int)
    case rational(Int, Int)
    case real(Double)
    case symbol(String)
    case constant(Constant)
    case add(Expr, Expr)
    case mul(Expr, Expr)
    case pow(Expr, Expr)
    case function(String, [Expr])
    case matrix(Matrix)

    public enum Constant: String, Hashable {
        case pi, e, infinity, negInfinity, i

        public var numericValue: Double {
            switch self {
            case .pi: return .pi
            case .e: return M_E
            case .infinity: return .infinity
            case .negInfinity: return -.infinity
            case .i: return .nan  // imaginary unit has no real value
            }
        }
    }

    public var description: String {
        return PrettyPrinter.format(self)
    }
}

// MARK: - Convenience Constructors

public let pi = Expr.constant(.pi)
public let e = Expr.constant(.e)
public let infinity = Expr.constant(.infinity)
public let imaginaryUnit = Expr.constant(.i)

public func sym(_ name: String) -> Expr { .symbol(name) }

public func syms(_ names: String) -> [Expr] {
    names.split(whereSeparator: { $0 == " " || $0 == "," })
        .map { Expr.symbol(String($0)) }
}

// MARK: - Arithmetic Operators

public func + (lhs: Expr, rhs: Expr) -> Expr { .add(lhs, rhs) }
public func + (lhs: Expr, rhs: Int) -> Expr { .add(lhs, .integer(rhs)) }
public func + (lhs: Int, rhs: Expr) -> Expr { .add(.integer(lhs), rhs) }

public func - (lhs: Expr, rhs: Expr) -> Expr { .add(lhs, .mul(.integer(-1), rhs)) }
public func - (lhs: Expr, rhs: Int) -> Expr { .add(lhs, .integer(-rhs)) }
public func - (lhs: Int, rhs: Expr) -> Expr { .add(.integer(lhs), .mul(.integer(-1), rhs)) }

public func * (lhs: Expr, rhs: Expr) -> Expr { .mul(lhs, rhs) }
public func * (lhs: Expr, rhs: Int) -> Expr { .mul(lhs, .integer(rhs)) }
public func * (lhs: Int, rhs: Expr) -> Expr { .mul(.integer(lhs), rhs) }

public func / (lhs: Expr, rhs: Expr) -> Expr { .mul(lhs, .pow(rhs, .integer(-1))) }
public func / (lhs: Expr, rhs: Int) -> Expr { .mul(lhs, .pow(.integer(rhs), .integer(-1))) }
public func / (lhs: Int, rhs: Expr) -> Expr { .mul(.integer(lhs), .pow(rhs, .integer(-1))) }

public func ** (lhs: Expr, rhs: Expr) -> Expr { .pow(lhs, rhs) }
public func ** (lhs: Expr, rhs: Int) -> Expr { .pow(lhs, .integer(rhs)) }

infix operator ** : BitwiseShiftPrecedence

public prefix func - (expr: Expr) -> Expr { .mul(.integer(-1), expr) }

// MARK: - Standard Functions

public func sin(_ x: Expr) -> Expr { .function("sin", [x]) }
public func cos(_ x: Expr) -> Expr { .function("cos", [x]) }
public func tan(_ x: Expr) -> Expr { .function("tan", [x]) }
public func exp(_ x: Expr) -> Expr { .function("exp", [x]) }
public func log(_ x: Expr) -> Expr { .function("log", [x]) }
public func ln(_ x: Expr) -> Expr { .function("log", [x]) }
public func sqrt(_ x: Expr) -> Expr { .pow(x, .rational(1, 2)) }
public func abs(_ x: Expr) -> Expr { .function("abs", [x]) }
public func asin(_ x: Expr) -> Expr { .function("asin", [x]) }
public func acos(_ x: Expr) -> Expr { .function("acos", [x]) }
public func atan(_ x: Expr) -> Expr { .function("atan", [x]) }
public func sinh(_ x: Expr) -> Expr { .function("sinh", [x]) }
public func cosh(_ x: Expr) -> Expr { .function("cosh", [x]) }
public func tanh(_ x: Expr) -> Expr { .function("tanh", [x]) }
public func factorial(_ n: Expr) -> Expr { .function("factorial", [n]) }

// MARK: - Substitution

extension Expr {
    public func substitute(_ mapping: [Expr: Expr]) -> Expr {
        if let replacement = mapping[self] {
            return replacement
        }
        switch self {
        case .integer, .real, .rational, .constant:
            return self
        case .symbol:
            return self
        case .add(let a, let b):
            return .add(a.substitute(mapping), b.substitute(mapping))
        case .mul(let a, let b):
            return .mul(a.substitute(mapping), b.substitute(mapping))
        case .pow(let base, let exp):
            return .pow(base.substitute(mapping), exp.substitute(mapping))
        case .function(let name, let args):
            return .function(name, args.map { $0.substitute(mapping) })
        case .matrix(let m):
            let newElements = m.elements.map { row in
                row.map { $0.substitute(mapping) }
            }
            return .matrix(Matrix(newElements))
        }
    }

    public func substitute(_ symbol: Expr, with value: Expr) -> Expr {
        substitute([symbol: value])
    }
}

// MARK: - Numeric Evaluation

extension Expr {
    public func eval(_ mapping: [Expr: Double] = [:]) -> Double {
        switch self {
        case .integer(let n):
            return Double(n)
        case .rational(let p, let q):
            return Double(p) / Double(q)
        case .real(let v):
            return v
        case .symbol:
            guard let val = mapping[self] else {
                fatalError("No value provided for \(self)")
            }
            return val
        case .constant(let c):
            return c.numericValue
        case .add(let a, let b):
            return a.eval(mapping) + b.eval(mapping)
        case .mul(let a, let b):
            return a.eval(mapping) * b.eval(mapping)
        case .pow(let base, let exp):
            return Foundation.pow(base.eval(mapping), exp.eval(mapping))
        case .function(let name, let args):
            let vals = args.map { $0.eval(mapping) }
            return evalFunction(name, vals)
        case .matrix:
            fatalError("Cannot evaluate a matrix to a single Double")
        }
    }

    private func evalFunction(_ name: String, _ args: [Double]) -> Double {
        switch name {
        case "sin": return Foundation.sin(args[0])
        case "cos": return Foundation.cos(args[0])
        case "tan": return Foundation.tan(args[0])
        case "exp": return Foundation.exp(args[0])
        case "log": return Foundation.log(args[0])
        case "abs": return Swift.abs(args[0])
        case "asin": return Foundation.asin(args[0])
        case "acos": return Foundation.acos(args[0])
        case "atan": return Foundation.atan(args[0])
        case "sinh": return Foundation.sinh(args[0])
        case "cosh": return Foundation.cosh(args[0])
        case "tanh": return Foundation.tanh(args[0])
        case "factorial":
            let n = Int(args[0])
            return Double((1...max(1, n)).reduce(1, *))
        default:
            fatalError("Unknown function: \(name)")
        }
    }
}

// MARK: - Free Symbols

extension Expr {
    public var freeSymbols: Set<Expr> {
        switch self {
        case .symbol: return [self]
        case .integer, .rational, .real, .constant: return []
        case .add(let a, let b): return a.freeSymbols.union(b.freeSymbols)
        case .mul(let a, let b): return a.freeSymbols.union(b.freeSymbols)
        case .pow(let base, let exp): return base.freeSymbols.union(exp.freeSymbols)
        case .function(_, let args):
            return args.reduce(into: Set<Expr>()) { $0.formUnion($1.freeSymbols) }
        case .matrix(let m):
            return m.elements.flatMap { $0 }.reduce(into: Set<Expr>()) { $0.formUnion($1.freeSymbols) }
        }
    }
}

// MARK: - Helpers

extension Expr {
    var isZero: Bool {
        if case .integer(0) = self { return true }
        return false
    }

    var isOne: Bool {
        if case .integer(1) = self { return true }
        return false
    }

    public var numericValue: Double? {
        switch self {
        case .integer(let n): return Double(n)
        case .rational(let p, let q): return Double(p) / Double(q)
        case .real(let v): return v
        case .constant(let c): return c.numericValue
        default: return nil
        }
    }

    var isNumeric: Bool { numericValue != nil }
}
