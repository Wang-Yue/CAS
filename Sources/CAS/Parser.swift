import Foundation

// MARK: - Parse Result

public enum TopLevelResult {
    case expr(Expr)
    case assignment(String, Expr)
    case distribution(Distribution)
}

// MARK: - Parse Error

public enum ParseError: Error, CustomStringConvertible {
    case expected(String, got: String)
    case unexpected(String)
    case unexpectedEOF

    public var description: String {
        switch self {
        case .expected(let exp, let got): return "Expected \(exp), got \(got)"
        case .unexpected(let s): return "Unexpected: \(s)"
        case .unexpectedEOF: return "Unexpected end of input"
        }
    }
}

// MARK: - Parser

public class Parser {
    var tokens: [Token]
    var pos: Int = 0
    var userVars: [String: Expr]
    var distributions: [String: Distribution]
    var lastResult: Expr?

    public init(_ tokens: [Token], vars: [String: Expr] = [:], dists: [String: Distribution] = [:], lastResult: Expr? = nil) {
        self.tokens = tokens
        self.userVars = vars
        self.distributions = dists
        self.lastResult = lastResult
    }

    var current: Token? { pos < tokens.count ? tokens[pos] : nil }

    func peek(_ offset: Int = 0) -> Token? {
        let idx = pos + offset
        return idx < tokens.count ? tokens[idx] : nil
    }

    @discardableResult
    func advance() -> Token? {
        let t = current
        pos += 1
        return t
    }

    func expect(_ token: Token) throws {
        guard current == token else {
            throw ParseError.expected("\(token)", got: current.map { "\($0)" } ?? "EOF")
        }
        advance()
    }

    // MARK: Top-level

    public func parseTopLevel() throws -> TopLevelResult {
        // let <name> = <expr>
        if case .keyword("let") = current {
            advance()
            guard case .ident(let name) = current else {
                throw ParseError.expected("identifier", got: current.map { "\($0)" } ?? "EOF")
            }
            advance()
            try expect(.eq)
            let expr = try parseExpr()
            return .assignment(name, expr)
        }

        // Distribution construction: normal(...), binomial(...), etc.
        if let distResult = try tryParseDistribution() {
            // Check for .ev, .var, .std, .pdf(...), .mgf(...)
            if case .dot = current {
                advance()
                guard case .ident(let prop) = current else {
                    throw ParseError.expected("property name", got: current.map { "\($0)" } ?? "EOF")
                }
                advance()
                return try handleDistProperty(distResult, prop)
            }
            return .distribution(distResult)
        }

        let expr = try parseExpr()

        // Handle "where" substitution
        if case .keyword("where") = current {
            advance()
            var mapping: [Expr: Expr] = [:]
            while true {
                guard case .ident(let name) = current else { break }
                advance()
                try expect(.eq)
                let val = try parseExpr()
                mapping[sym(name)] = val
                if case .comma = current { advance() } else { break }
            }
            return .expr(simplify(expr.substitute(mapping)))
        }

        return .expr(expr)
    }

    // MARK: Expression parsing (precedence climbing)

    public func parseExpr() throws -> Expr {
        try parseAdd()
    }

    func parseAdd() throws -> Expr {
        var left = try parseMul()
        while let t = current {
            if case .op("+") = t {
                advance(); left = left + (try parseMul())
            } else if case .op("-") = t {
                advance(); left = left - (try parseMul())
            } else {
                break
            }
        }
        return left
    }

    func parseMul() throws -> Expr {
        var left = try parsePow()
        while let t = current {
            if case .op("*") = t {
                advance(); left = left * (try parsePow())
            } else if case .op("/") = t {
                advance(); left = left / (try parsePow())
            } else {
                break
            }
        }
        return left
    }

    func parsePow() throws -> Expr {
        var base = try parseUnary()
        if case .caret = current {
            advance()
            let exp = try parseUnary()  // right-associative
            base = .pow(base, exp)
        }
        return base
    }

    func parseUnary() throws -> Expr {
        if case .op("-") = current {
            advance()
            let expr = try parseUnary()
            return .mul(.integer(-1), expr)
        }
        return try parsePostfix()
    }

    func parsePostfix() throws -> Expr {
        let expr = try parsePrimary()
        return expr
    }

    func parsePrimary() throws -> Expr {
        guard let token = current else {
            throw ParseError.unexpectedEOF
        }

        switch token {

        // Number literal
        case .number(let s):
            advance()
            if case .op("/") = current, case .number(let d) = peek(1) {
                if !s.contains(".") && !d.contains(".") {
                    advance()
                    advance()
                    return .rational(Int(s)!, Int(d)!)
                }
            }
            if s.contains(".") {
                return .real(Double(s)!)
            }
            return .integer(Int(s)!)

        // Identifier: variable, constant, or function call
        case .ident(let name):
            advance()

            if case .lparen = current {
                return try parseFunctionCall(name)
            }

            switch name {
            case "pi": return CAS.pi
            case "e": return CAS.e
            case "i": return CAS.imaginaryUnit
            case "oo", "inf", "infinity": return CAS.infinity
            case "_", "last", "ans":
                guard let prev = lastResult else {
                    throw ParseError.expected("previous result", got: "no previous result")
                }
                return prev
            default: break
            }

            if let val = userVars[name] {
                return val
            }

            return .symbol(name)

        case .lparen:
            advance()
            let expr = try parseExpr()
            try expect(.rparen)
            return expr

        case .lbracket:
            return try parseMatrixOrVector()

        case .pipe:
            advance()
            let expr = try parseExpr()
            try expect(.pipe)
            return CAS.abs(expr)

        default:
            throw ParseError.unexpected("\(token)")
        }
    }

    // MARK: Function calls

    func parseFunctionCall(_ name: String) throws -> Expr {
        try expect(.lparen)
        var args: [Expr] = []
        if current != .rparen {
            args.append(try parseExpr())
            while case .comma = current {
                advance()
                args.append(try parseExpr())
            }
        }
        try expect(.rparen)

        if args.isEmpty {
            throw ParseError.expected("\(name)(args...)", got: "no arguments")
        }

        switch name {
        // Standard math functions (1 argument)
        case "sin", "cos", "tan", "exp", "log", "ln", "sqrt", "abs",
             "asin", "acos", "atan", "sinh", "cosh", "tanh", "factorial":
            guard args.count == 1 else {
                throw ParseError.expected("\(name)(expr)", got: "\(args.count) args")
            }
            switch name {
            case "sin":   return CAS.sin(args[0])
            case "cos":   return CAS.cos(args[0])
            case "tan":   return CAS.tan(args[0])
            case "exp":   return CAS.exp(args[0])
            case "log":   return CAS.log(args[0])
            case "ln":    return CAS.ln(args[0])
            case "sqrt":  return CAS.sqrt(args[0])
            case "abs":   return CAS.abs(args[0])
            case "asin":  return CAS.asin(args[0])
            case "acos":  return CAS.acos(args[0])
            case "atan":  return CAS.atan(args[0])
            case "sinh":  return CAS.sinh(args[0])
            case "cosh":  return CAS.cosh(args[0])
            case "tanh":  return CAS.tanh(args[0])
            case "factorial": return CAS.factorial(args[0])
            default: fatalError()
            }

        // Calculus
        case "diff":
            guard args.count >= 2 else {
                throw ParseError.expected("diff(expr, var) or diff(expr, var, n)", got: "\(args.count) args")
            }
            if args.count == 3, case .integer(let n) = args[2] {
                return CAS.diff(args[0], args[1], order: n)
            }
            return CAS.diff(args[0], args[1])

        case "integrate":
            guard args.count >= 2 else {
                throw ParseError.expected("integrate(expr, var) or integrate(expr, var, lo, hi)", got: "\(args.count) args")
            }
            if args.count == 4 {
                return CAS.integrate(args[0], args[1], from: args[2], to: args[3])
            }
            return CAS.integrate(args[0], args[1])

        case "limit":
            guard args.count >= 3 else {
                throw ParseError.expected("limit(expr, var, point)", got: "\(args.count) args")
            }
            return CAS.limit(args[0], args[1], to: args[2])

        case "taylor":
            guard args.count >= 2 else {
                throw ParseError.expected("taylor(expr, var) or taylor(expr, var, n)", got: "\(args.count) args")
            }
            let terms = args.count >= 3 ? (args[2].numericValue.map { Int($0) } ?? 6) : 6
            return CAS.taylor(args[0], args[1], terms: terms)

        case "gradient":
            guard args.count >= 2 else { throw ParseError.expected("gradient(expr, [vars])", got: "too few args") }
            let vars = extractVarList(args, from: 1)
            let result = CAS.gradient(args[0], vars)
            return .function("vector", result)

        case "hessian":
            guard args.count >= 2 else { throw ParseError.expected("hessian(expr, [vars])", got: "too few args") }
            let vars = extractVarList(args, from: 1)
            return .matrix(CAS.hessian(args[0], vars))

        case "jacobian":
            throw ParseError.expected("Use hessian or gradient", got: "jacobian not yet supported")

        // Linear algebra
        case "matrix":
            if args.count == 1, case .matrix(let m) = args[0] {
                return .matrix(m)
            }
            throw ParseError.expected("matrix([[...],[...]])", got: "invalid matrix syntax")

        case "det":
            let m = try requireMatrix(CAS.simplify(args[0]), for: "det")
            return m.determinant()

        case "inv":
            let m = try requireMatrix(CAS.simplify(args[0]), for: "inv")
            return .matrix(m.inverse())

        case "transpose":
            let m = try requireMatrix(CAS.simplify(args[0]), for: "transpose")
            return .matrix(m.transposed())

        case "trace":
            let m = try requireMatrix(CAS.simplify(args[0]), for: "trace")
            return m.trace()

        case "rref":
            let m = try requireMatrix(CAS.simplify(args[0]), for: "rref")
            return .matrix(m.rref())

        case "rank":
            let m = try requireMatrix(CAS.simplify(args[0]), for: "rank")
            return .integer(m.rank)

        case "solve":
            guard args.count == 2 else {
                throw ParseError.expected("solve(expr, var) or solve(matrix, vector)", got: "\(args.count) args")
            }
            let first = CAS.simplify(args[0])
            if case .matrix(let A) = first {
                let b = try requireMatrix(CAS.simplify(args[1]), for: "solve")
                return .matrix(A.solve(b))
            }
            let roots = try CAS.solve(args[0], args[1])
            if roots.count == 1 {
                return roots[0]
            }
            return .function("roots", roots)

        case "charpoly":
            guard args.count == 2 else {
                throw ParseError.expected("charpoly(matrix, var)", got: "\(args.count) args")
            }
            let m = try requireMatrix(CAS.simplify(args[0]), for: "charpoly")
            return m.characteristicPolynomial(args[1])

        case "eigen":
            let m = try requireMatrix(CAS.simplify(args[0]), for: "eigen")
            guard m.rows == 2, m.cols == 2 else {
                throw ParseError.expected("2x2 matrix for eigen", got: "\(m.rows)x\(m.cols)")
            }
            return computeEigenvalues2x2(m)

        case "dot":
            guard args.count == 2 else { throw ParseError.expected("dot(vec, vec)", got: "wrong arg count") }
            let a = extractVector(args[0])
            let b = extractVector(args[1])
            return Matrix.dot(a, b)

        case "cross":
            guard args.count == 2 else { throw ParseError.expected("cross(vec, vec)", got: "wrong arg count") }
            let a = extractVector(args[0])
            let b = extractVector(args[1])
            let result = Matrix.cross(a, b)
            return .function("vector", result)

        // ODE solver
        case "ode":
            guard args.count >= 2 else {
                throw ParseError.expected("ode(expr, x)", got: "\(args.count) args")
            }
            return try CAS.solveODE(args[0], y: .symbol("y"), x: args[1])

        // Evaluation / output
        case "eval":
            return .real(args[0].eval())

        case "latex":
            return .function("latex", [args[0]])

        case "simplify":
            return CAS.simplify(args[0])

        // Combinatorics
        case "nCr", "C", "choose", "binomial":
            guard args.count == 2 else { throw ParseError.expected("nCr(n,k)", got: "wrong arg count") }
            return CAS.nCr(args[0], args[1])

        case "nPr", "P":
            guard args.count == 2 else { throw ParseError.expected("nPr(n,k)", got: "wrong arg count") }
            return CAS.nPr(args[0], args[1])

        default:
            return .function(name, args)
        }
    }

    // MARK: Matrix/vector parsing

    func parseMatrixOrVector() throws -> Expr {
        try expect(.lbracket)
        var rows: [[Expr]] = []

        if case .lbracket = current {
            while case .lbracket = current {
                advance()
                var row: [Expr] = []
                row.append(try parseExpr())
                while case .comma = current {
                    advance()
                    row.append(try parseExpr())
                }
                try expect(.rbracket)
                rows.append(row)
                if case .comma = current { advance() }
            }
            try expect(.rbracket)
            return .matrix(Matrix(rows))
        } else {
            var elems: [Expr] = []
            elems.append(try parseExpr())
            while case .comma = current {
                advance()
                elems.append(try parseExpr())
            }
            try expect(.rbracket)
            return .matrix(Matrix(elems.map { [$0] }))
        }
    }

    // MARK: Distribution parsing

    func tryParseDistribution() throws -> Distribution? {
        guard case .ident(let name) = current else { return nil }

        let distNames = ["normal", "binomial", "poisson", "exponential", "uniform", "bernoulli", "geometric"]
        guard distNames.contains(name) else {
            if let dist = distributions[name] {
                advance()
                return dist
            }
            return nil
        }

        guard case .lparen = peek(1) else { return nil }

        advance()
        try expect(.lparen)
        var args: [Expr] = []
        if current != .rparen {
            args.append(try parseExpr())
            while case .comma = current { advance(); args.append(try parseExpr()) }
        }
        try expect(.rparen)

        switch name {
        case "normal":
            guard args.count == 2 else { throw ParseError.expected("normal(mean, variance)", got: "\(args.count) args") }
            return .normal(mean: args[0], variance: args[1])
        case "binomial":
            guard args.count == 2 else { throw ParseError.expected("binomial(n, p)", got: "\(args.count) args") }
            return .binomial(n: args[0], p: args[1])
        case "poisson":
            guard args.count == 1 else { throw ParseError.expected("poisson(lambda)", got: "\(args.count) args") }
            return .poisson(lambda: args[0])
        case "exponential":
            guard args.count == 1 else { throw ParseError.expected("exponential(lambda)", got: "\(args.count) args") }
            return .exponential(lambda: args[0])
        case "uniform":
            guard args.count == 2 else { throw ParseError.expected("uniform(a, b)", got: "\(args.count) args") }
            return .uniform(a: args[0], b: args[1])
        case "bernoulli":
            guard args.count == 1 else { throw ParseError.expected("bernoulli(p)", got: "\(args.count) args") }
            return .bernoulli(p: args[0])
        case "geometric":
            guard args.count == 1 else { throw ParseError.expected("geometric(p)", got: "\(args.count) args") }
            return .geometric(p: args[0])
        default:
            return nil
        }
    }

    func handleDistProperty(_ dist: Distribution, _ prop: String) throws -> TopLevelResult {
        switch prop {
        case "ev", "mean", "E", "expectedValue":
            return .expr(CAS.simplify(dist.expectedValue))
        case "var", "variance", "Var":
            return .expr(CAS.simplify(dist.variance))
        case "std", "stddev", "sigma":
            return .expr(CAS.simplify(dist.standardDeviation))
        case "pdf", "pmf":
            try expect(.lparen)
            let arg = try parseExpr()
            try expect(.rparen)
            return .expr(CAS.simplify(dist.pdf(arg)))
        case "mgf":
            try expect(.lparen)
            let arg = try parseExpr()
            try expect(.rparen)
            return .expr(CAS.simplify(dist.mgf(arg)))
        default:
            throw ParseError.expected("ev, var, std, pdf, or mgf", got: prop)
        }
    }

    // MARK: Helpers

    func requireMatrix(_ expr: Expr, for funcName: String) throws -> Matrix {
        if case .matrix(let m) = expr { return m }
        throw ParseError.expected("matrix argument for \(funcName)", got: "\(expr)")
    }

    func extractVarList(_ args: [Expr], from start: Int) -> [Expr] {
        if start < args.count, case .matrix(let m) = args[start], m.cols == 1 {
            return m.elements.map { $0[0] }
        }
        if start < args.count, case .function("vector", let elems) = args[start] {
            return elems
        }
        return Array(args[start...])
    }

    func extractVector(_ expr: Expr) -> [Expr] {
        if case .matrix(let m) = expr, m.cols == 1 {
            return m.elements.map { $0[0] }
        }
        if case .function("vector", let elems) = expr {
            return elems
        }
        return [expr]
    }
}

// MARK: - Helpers

public func computeEigenvalues2x2(_ m: Matrix) -> Expr {
    let tr = m.trace()
    let det = m.determinant()
    let disc = simplify(tr * tr - 4 * det)
    let lambda1 = simplify((tr + CAS.sqrt(disc)) / 2)
    let lambda2 = simplify((tr - CAS.sqrt(disc)) / 2)
    return .function("eigenvalues", [lambda1, lambda2])
}
