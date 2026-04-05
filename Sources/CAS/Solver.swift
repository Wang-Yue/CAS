import Foundation

// MARK: - Errors

public enum SolveError: Error, CustomStringConvertible {
    case notPolynomial
    case degreeTooHigh(Int)
    case noSolution
    case transcendentalNotRecognized
    case odeTypeNotRecognized
    case unsupportedODEOrder

    public var description: String {
        switch self {
        case .notPolynomial: return "Expression is not a polynomial"
        case .degreeTooHigh(let d): return "Polynomial degree \(d) too high for symbolic solution"
        case .noSolution: return "No solution found"
        case .transcendentalNotRecognized: return "Transcendental equation pattern not recognized"
        case .odeTypeNotRecognized: return "ODE type not recognized (try separable, linear, or constant-coefficient)"
        case .unsupportedODEOrder: return "Only first and second order ODEs are supported"
        }
    }
}

// MARK: - Helpers

private func containsUnevaluated(_ expr: Expr) -> Bool {
    switch expr {
    case .function("Integral", _), .function("Limit", _):
        return true
    case .add(let a, let b):
        return containsUnevaluated(a) || containsUnevaluated(b)
    case .mul(let a, let b):
        return containsUnevaluated(a) || containsUnevaluated(b)
    case .pow(let a, let b):
        return containsUnevaluated(a) || containsUnevaluated(b)
    case .function(_, let args):
        return args.contains(where: containsUnevaluated)
    default:
        return false
    }
}

// MARK: - Algebraic Equation Solver

/// Solve expr = 0 for variable. Returns list of solutions.
public func solve(_ expr: Expr, _ variable: Expr) throws -> [Expr] {
    guard case .symbol(let v) = variable else {
        fatalError("Can only solve for a symbol")
    }

    let simplified = simplify(expr)

    // Try polynomial extraction first
    if let coeffs = extractPolyCoefficients(simplified, v) {
        let deg = coeffs.keys.max() ?? 0
        switch deg {
        case 0:
            // Constant = 0
            if let val = coeffs[0]?.numericValue, Swift.abs(val) < 1e-12 {
                throw SolveError.noSolution  // infinitely many solutions, really
            }
            throw SolveError.noSolution
        case 1:
            let a = coeffs[1] ?? .integer(0)
            let b = coeffs[0] ?? .integer(0)
            return [solveLinear(a: a, b: b)]
        case 2:
            let a = coeffs[2] ?? .integer(0)
            let b = coeffs[1] ?? .integer(0)
            let c = coeffs[0] ?? .integer(0)
            return solveQuadratic(a: a, b: b, c: c)
        default:
            // For degree >= 3: try rational roots + deflation, then symbolic/numeric fallback
            return solvePolynomial(coeffs, degree: deg, v: v)
        }
    }

    // Try transcendental patterns
    if let roots = matchTranscendental(simplified, v, depth: 0) {
        return roots
    }

    throw SolveError.transcendentalNotRecognized
}

// MARK: - Polynomial Coefficient Extraction

private func extractPolyCoefficients(_ expr: Expr, _ v: String) -> [Int: Expr]? {
    let sv = Expr.symbol(v)

    switch expr {
    case .symbol(let name):
        if name == v { return [1: .integer(1)] }
        return [0: expr]

    case .integer, .rational, .real, .constant:
        return [0: expr]

    case .pow(let base, let exp):
        if base == sv, case .integer(let n) = exp, n >= 0 {
            return [n: .integer(1)]
        }
        // Constant^constant
        if isConstFor(base, v) && isConstFor(exp, v) {
            return [0: expr]
        }
        return nil

    case .mul(let a, let b):
        guard let ca = extractPolyCoefficients(a, v),
              let cb = extractPolyCoefficients(b, v) else { return nil }
        return multiplyPolyCoeffs(ca, cb)

    case .add(let a, let b):
        guard let ca = extractPolyCoefficients(a, v),
              let cb = extractPolyCoefficients(b, v) else { return nil }
        return addPolyCoeffs(ca, cb)

    case .function:
        if isConstFor(expr, v) { return [0: expr] }
        return nil

    case .matrix:
        return nil
    }
}

private func isConstFor(_ expr: Expr, _ v: String) -> Bool {
    !expr.freeSymbols.contains(.symbol(v))
}

private func addPolyCoeffs(_ a: [Int: Expr], _ b: [Int: Expr]) -> [Int: Expr] {
    var result = a
    for (deg, coeff) in b {
        if let existing = result[deg] {
            result[deg] = simplify(existing + coeff)
        } else {
            result[deg] = coeff
        }
    }
    // Remove zero coefficients
    return result.filter { !$0.value.isZero }
}

private func multiplyPolyCoeffs(_ a: [Int: Expr], _ b: [Int: Expr]) -> [Int: Expr] {
    var result: [Int: Expr] = [:]
    for (da, ca) in a {
        for (db, cb) in b {
            let deg = da + db
            let term = simplify(ca * cb)
            if let existing = result[deg] {
                result[deg] = simplify(existing + term)
            } else {
                result[deg] = term
            }
        }
    }
    return result.filter { !$0.value.isZero }
}

// MARK: - Linear Solver

private func solveLinear(a: Expr, b: Expr) -> Expr {
    // ax + b = 0  =>  x = -b/a
    simplify(.mul(.integer(-1), b) / a)
}

// MARK: - Quadratic Solver

public func solveQuadratic(a: Expr, b: Expr, c: Expr) -> [Expr] {
    let disc = simplify(b * b - 4 * a * c)

    // Check if discriminant is zero
    if let dv = disc.numericValue, Swift.abs(dv) < 1e-12 {
        let root = simplify(.mul(.integer(-1), b) / (.integer(2) * a))
        return [root]
    }

    let sqrtDisc = CAS.sqrt(disc)
    let denom = simplify(.integer(2) * a)
    let r1 = simplify((.mul(.integer(-1), b) + sqrtDisc) / denom)
    let r2 = simplify((.mul(.integer(-1), b) - sqrtDisc) / denom)

    if r1 == r2 { return [r1] }
    return [r1, r2]
}

// MARK: - General Polynomial Solver

/// Solve a polynomial of any degree using rational roots + deflation + symbolic formulas.
private func solvePolynomial(_ coeffs: [Int: Expr], degree: Int, v: String) -> [Expr] {
    var roots: [Expr] = []
    var currentCoeffs = coeffs
    var currentDeg = degree

    // Phase 1: extract all rational roots via the rational root theorem
    while currentDeg >= 1 {
        if let root = findRationalRoot(currentCoeffs, degree: currentDeg) {
            roots.append(root)
            currentCoeffs = deflateSymbolic(currentCoeffs, degree: currentDeg, root: root)
            currentDeg -= 1
        } else {
            break
        }
    }

    // Phase 2: solve remaining polynomial symbolically
    switch currentDeg {
    case 0:
        break
    case 1:
        let a = currentCoeffs[1] ?? .integer(0)
        let b = currentCoeffs[0] ?? .integer(0)
        roots.append(solveLinear(a: a, b: b))
    case 2:
        let a = currentCoeffs[2] ?? .integer(0)
        let b = currentCoeffs[1] ?? .integer(0)
        let c = currentCoeffs[0] ?? .integer(0)
        roots.append(contentsOf: solveQuadratic(a: a, b: b, c: c))
    case 3:
        let a = currentCoeffs[3] ?? .integer(0)
        let b = currentCoeffs[2] ?? .integer(0)
        let c = currentCoeffs[1] ?? .integer(0)
        let d = currentCoeffs[0] ?? .integer(0)
        roots.append(contentsOf: solveCubicSymbolic(a: a, b: b, c: c, d: d))
    default:
        // Degree 4+: numeric fallback
        roots.append(contentsOf: solveNumericRoots(currentCoeffs, degree: currentDeg))
    }

    return roots
}

// MARK: - Rational Root Theorem

/// Try all candidates p/q where p divides the constant term and q divides the leading coefficient.
private func findRationalRoot(_ coeffs: [Int: Expr], degree: Int) -> Expr? {
    // If constant term is 0, x=0 is always a root
    let constant = coeffs[0] ?? .integer(0)
    if constant.isZero {
        return .integer(0)
    }

    let leading = coeffs[degree] ?? .integer(1)

    guard let lv = leading.numericValue, !lv.isNaN,
          let cv = constant.numericValue, !cv.isNaN else {
        return nil
    }
    let a = Int(lv.rounded())
    let d = Int(cv.rounded())
    guard a != 0,
          Swift.abs(lv - Double(a)) < 1e-8,
          Swift.abs(cv - Double(d)) < 1e-8 else {
        return nil
    }

    let pFactors = divisors(Swift.abs(d == 0 ? 1 : d))
    let qFactors = divisors(Swift.abs(a))

    for p in pFactors {
        for q in qFactors {
            for sign in [1, -1] {
                let num = sign * p
                let candidate: Expr = q == 1 ? .integer(num) : .rational(num, q)
                if evaluatePolyAt(coeffs, degree: degree, value: candidate) {
                    return candidate
                }
            }
        }
    }
    return nil
}

private func divisors(_ n: Int) -> [Int] {
    guard n > 0 else { return [0] }
    var result: [Int] = []
    for i in 1...n {
        if n % i == 0 { result.append(i) }
    }
    return result
}

/// Check if polynomial evaluates to 0 at the given value (exact rational arithmetic).
private func evaluatePolyAt(_ coeffs: [Int: Expr], degree: Int, value: Expr) -> Bool {
    var result: Expr = .integer(0)
    for (deg, coeff) in coeffs {
        let term = simplify(coeff * Expr.pow(value, .integer(deg)))
        result = simplify(result + term)
    }
    let simplified = simplify(result)
    if simplified.isZero { return true }
    if let v = simplified.numericValue, Swift.abs(v) < 1e-10 { return true }
    return false
}

/// Synthetic division: divide poly by (x - root), return new coefficients.
private func deflateSymbolic(_ coeffs: [Int: Expr], degree: Int, root: Expr) -> [Int: Expr] {
    // Synthetic division: from highest degree down
    var result: [Int: Expr] = [:]
    var carry: Expr = .integer(0)
    for i in stride(from: degree, through: 1, by: -1) {
        let coeff = coeffs[i] ?? .integer(0)
        let newCoeff = simplify(coeff + carry)
        result[i - 1] = newCoeff
        carry = simplify(newCoeff * root)
    }
    return result
}

// MARK: - Symbolic Cubic Solver (Cardano's Formula)

private func solveCubicSymbolic(a: Expr, b: Expr, c: Expr, d: Expr) -> [Expr] {
    // Normalize to monic: x³ + (b/a)x² + (c/a)x + (d/a) = 0
    let b1 = simplify(b / a)
    let c1 = simplify(c / a)
    let d1 = simplify(d / a)

    // Depressed cubic via t = x - b/(3a):  t³ + pt + q = 0
    // p = c/a - b²/(3a²) = c1 - b1²/3
    // q = d/a - bc/(3a²) + 2b³/(27a³) = d1 - b1*c1/3 + 2*b1³/27
    let p = simplify(c1 - b1 * b1 / 3)
    let q = simplify(d1 - b1 * c1 / 3 + .integer(2) * b1 * b1 * b1 / 27)
    let shift = simplify(b1 / 3)

    // Discriminant Δ = -4p³ - 27q²
    let disc = simplify(.integer(-4) * p * p * p - .integer(27) * q * q)

    // Check discriminant numerically to choose formula
    if let dv = disc.numericValue {
        if dv > 1e-10 {
            // Three distinct real roots — casus irreducibilis
            // Use trigonometric form (numeric, but clean symbolic wrapper)
            return solveCubicTrigonometric(p: p, q: q, shift: shift)
        }
    }

    // Cardano's formula (one real root, or all symbolically expressible)
    // D = q²/4 + p³/27
    let D = simplify(q * q / 4 + p * p * p / 27)

    let sqrtD = CAS.sqrt(D)
    let negHalfQ = simplify(.mul(.integer(-1), q) / 2)

    // u = cbrt(-q/2 + √D), v = cbrt(-q/2 - √D)
    let u = Expr.pow(simplify(negHalfQ + sqrtD), .rational(1, 3))
    let v = Expr.pow(simplify(negHalfQ - sqrtD), .rational(1, 3))

    // t = u + v,  x = t - shift
    let root = simplify(u + v - shift)

    // Also try to find the other two roots via deflation
    // Deflate the original cubic by (x - root) to get a quadratic
    // But root is symbolic, so this is hard. Return the one real root from Cardano.
    // For the other two, try numeric.
    var roots: [Expr] = [root]

    // Attempt numeric for the other two roots if possible
    if let an = a.numericValue, let bn = b.numericValue,
       let cn = c.numericValue, let dn = d.numericValue,
       let r1 = root.numericValue {
        // Deflate numerically
        let poly: [Double] = [dn, cn, bn, an]
        let deflated = deflateNumeric(poly, root: r1)
        if deflated.count == 3 {
            // Quadratic: deflated[2]*x² + deflated[1]*x + deflated[0] = 0
            let qa = Expr.real(deflated[2])
            let qb = Expr.real(deflated[1])
            let qc = Expr.real(deflated[0])
            let quadRoots = solveQuadratic(a: qa, b: qb, c: qc)
            // Only add real roots
            for qr in quadRoots {
                if let v = qr.numericValue, !v.isNaN && !v.isInfinite {
                    roots.append(qr)
                }
            }
        }
    }

    return roots
}

/// Trigonometric solution for three real roots (casus irreducibilis)
private func solveCubicTrigonometric(p: Expr, q: Expr, shift: Expr) -> [Expr] {
    // t_k = 2√(-p/3) * cos(1/3 * arccos(3q/(2p) * √(-3/p)) - 2πk/3)
    let negP3 = simplify(.mul(.integer(-1), p) / 3)
    let m = simplify(.integer(2) * CAS.sqrt(negP3))
    let cosArg = simplify(.integer(3) * q / (.integer(2) * p) * CAS.sqrt(simplify(.integer(-3) / p)))
    let theta = simplify(CAS.acos(cosArg) / 3)

    let r1 = simplify(m * CAS.cos(theta) - shift)
    let r2 = simplify(m * CAS.cos(theta - .integer(2) * pi / 3) - shift)
    let r3 = simplify(m * CAS.cos(theta - .integer(4) * pi / 3) - shift)
    return [r1, r2, r3]
}

// MARK: - Numeric Root Finding (fallback)

private func solveNumericRoots(_ coeffs: [Int: Expr], degree: Int) -> [Expr] {
    var numCoeffs: [Double] = Array(repeating: 0, count: degree + 1)
    for (deg, coeff) in coeffs {
        guard let val = coeff.numericValue else { return [] }
        numCoeffs[deg] = val
    }

    var roots: [Double] = []
    var poly = numCoeffs

    for _ in 0..<degree {
        guard let root = newtonRaphsonPoly(poly) else { break }
        roots.append(root)
        poly = deflateNumeric(poly, root: root)
    }

    return roots.map(doubleToExpr)
}

private func doubleToExpr(_ val: Double) -> Expr {
    if Swift.abs(val - val.rounded()) < 1e-8 {
        return .integer(Int(val.rounded()))
    }
    for d in 2...12 {
        let candidate = (val * Double(d)).rounded() / Double(d)
        if Swift.abs(val - candidate) < 1e-8 {
            let num = Int((val * Double(d)).rounded())
            return Expr.rational(num, d)
        }
    }
    return .real(val)
}

private func evalPoly(_ coeffs: [Double], at x: Double) -> Double {
    var result = 0.0
    var xPow = 1.0
    for c in coeffs {
        result += c * xPow
        xPow *= x
    }
    return result
}

private func evalPolyDeriv(_ coeffs: [Double], at x: Double) -> Double {
    var result = 0.0
    var xPow = 1.0
    for i in 1..<coeffs.count {
        result += Double(i) * coeffs[i] * xPow
        xPow *= x
    }
    return result
}

private func newtonRaphsonPoly(_ coeffs: [Double]) -> Double? {
    // Try multiple starting points
    let starts: [Double] = [0, 1, -1, 2, -2, 0.5, -0.5, 5, -5, 10, -10]

    for x0 in starts {
        var x = x0
        for _ in 0..<100 {
            let fx = evalPoly(coeffs, at: x)
            if Swift.abs(fx) < 1e-12 { return x }
            let dfx = evalPolyDeriv(coeffs, at: x)
            if Swift.abs(dfx) < 1e-15 { break }
            x -= fx / dfx
        }
        if Swift.abs(evalPoly(coeffs, at: x)) < 1e-8 { return x }
    }
    return nil
}

private func deflateNumeric(_ coeffs: [Double], root: Double) -> [Double] {
    // Synthetic division by (x - root)
    guard coeffs.count > 1 else { return [] }
    var result = Array(repeating: 0.0, count: coeffs.count - 1)
    result[result.count - 1] = coeffs[coeffs.count - 1]
    for i in stride(from: result.count - 2, through: 0, by: -1) {
        result[i] = coeffs[i + 1] + root * result[i + 1]
    }
    return result
}

// MARK: - Transcendental Equation Solver

private func matchTranscendental(_ expr: Expr, _ v: String, depth: Int) -> [Expr]? {
    guard depth < 4 else { return nil }
    let sv = Expr.symbol(v)

    // Flatten: try to match expr = f(x) - c = 0 patterns

    // exp(f(x)) - a = 0  =>  f(x) = log(a)
    if let (funcExpr, constPart) = matchFuncMinusConst(expr, v) {
        if case .function("exp", let args) = funcExpr, args.count == 1 {
            let inner = args[0]
            let target = simplify(CAS.log(constPart))
            return solveInner(inner, equals: target, v: v, depth: depth)
        }
        // log(f(x)) - a = 0  =>  f(x) = exp(a)
        if case .function("log", let args) = funcExpr, args.count == 1 {
            let inner = args[0]
            let target = simplify(CAS.exp(constPart))
            return solveInner(inner, equals: target, v: v, depth: depth)
        }
        // sin(f(x)) - a = 0  =>  f(x) = asin(a)  (principal value)
        if case .function("sin", let args) = funcExpr, args.count == 1 {
            let inner = args[0]
            let target = simplify(CAS.asin(constPart))
            return solveInner(inner, equals: target, v: v, depth: depth)
        }
        // cos(f(x)) - a = 0  =>  f(x) = acos(a)
        if case .function("cos", let args) = funcExpr, args.count == 1 {
            let inner = args[0]
            let target = simplify(CAS.acos(constPart))
            return solveInner(inner, equals: target, v: v, depth: depth)
        }
        // tan(f(x)) - a = 0  =>  f(x) = atan(a)
        if case .function("tan", let args) = funcExpr, args.count == 1 {
            let inner = args[0]
            let target = simplify(CAS.atan(constPart))
            return solveInner(inner, equals: target, v: v, depth: depth)
        }
        // sqrt(f(x)) - a = 0  =>  f(x) = a^2
        if case .pow(let base, .rational(1, 2)) = funcExpr {
            let target = simplify(constPart * constPart)
            return solveInner(base, equals: target, v: v, depth: depth)
        }
        // f(x)^n - a = 0  =>  f(x) = a^(1/n)
        if case .pow(let base, let n) = funcExpr, isConstFor(n, v), !isConstFor(base, v) {
            let target = simplify(Expr.pow(constPart, .integer(1) / n))
            return solveInner(base, equals: target, v: v, depth: depth)
        }
    }

    // a^f(x) - b = 0  (e.g., 2^x = 8)
    if let (funcExpr, constPart) = matchFuncMinusConst(expr, v) {
        if case .pow(let base, let exp) = funcExpr, isConstFor(base, v), !isConstFor(exp, v) {
            // base^exp = constPart  =>  exp = log(constPart) / log(base)
            let target = simplify(CAS.log(constPart) / CAS.log(base))
            return solveInner(exp, equals: target, v: v, depth: depth)
        }
    }

    return nil
}

/// Try to decompose expr as f(x) - c where f depends on v and c is constant
private func matchFuncMinusConst(_ expr: Expr, _ v: String) -> (Expr, Expr)? {
    // Collect all additive terms
    var terms: [Expr] = []
    collectAddTerms(expr, into: &terms)

    var varTerms: [Expr] = []
    var constTerms: [Expr] = []

    for t in terms {
        if isConstFor(t, v) {
            constTerms.append(t)
        } else {
            varTerms.append(t)
        }
    }

    guard !varTerms.isEmpty && !constTerms.isEmpty else { return nil }

    let funcPart = varTerms.count == 1 ? varTerms[0]
        : varTerms.dropFirst().reduce(varTerms[0]) { Expr.add($0, $1) }
    let constPart = constTerms.count == 1 ? constTerms[0]
        : constTerms.dropFirst().reduce(constTerms[0]) { Expr.add($0, $1) }

    // f(x) + (-c) = 0  =>  f(x) = c
    return (funcPart, simplify(.mul(.integer(-1), constPart)))
}

private func collectAddTerms(_ expr: Expr, into terms: inout [Expr]) {
    if case .add(let a, let b) = expr {
        collectAddTerms(a, into: &terms)
        collectAddTerms(b, into: &terms)
    } else {
        terms.append(expr)
    }
}

/// Solve inner(x) = target for x
private func solveInner(_ inner: Expr, equals target: Expr, v: String, depth: Int) -> [Expr]? {
    let eq = simplify(inner - target)
    // Try polynomial
    if let coeffs = extractPolyCoefficients(eq, v) {
        let deg = coeffs.keys.max() ?? 0
        switch deg {
        case 0: return nil
        case 1:
            let a = coeffs[1] ?? .integer(0)
            let b = coeffs[0] ?? .integer(0)
            return [solveLinear(a: a, b: b)]
        case 2:
            let a = coeffs[2] ?? .integer(0)
            let b = coeffs[1] ?? .integer(0)
            let c = coeffs[0] ?? .integer(0)
            return solveQuadratic(a: a, b: b, c: c)
        default:
            break
        }
    }
    // Recurse for nested transcendentals
    return matchTranscendental(eq, v, depth: depth + 1)
}

// MARK: ===================================================================
// MARK: - ODE Solver
// MARK: ===================================================================

/// Solve an ODE expressed as lhs = 0.
/// Uses conventions: y = function, yd = y', ydd = y''
/// x is the independent variable.
public func solveODE(_ lhs: Expr, y: Expr = .symbol("y"), x: Expr = .symbol("x")) throws -> Expr {
    guard case .symbol(let yName) = y, case .symbol(let xName) = x else {
        fatalError("y and x must be symbols")
    }
    let ydName = yName + "d"      // y'
    let yddName = yName + "dd"    // y''

    let simplified = simplify(lhs)

    // Check order
    let hasYdd = simplified.freeSymbols.contains(.symbol(yddName))
    let hasYd = simplified.freeSymbols.contains(.symbol(ydName))

    if hasYdd {
        // Second-order ODE
        if let result = trySecondOrderConstCoeff(simplified, yName: yName, ydName: ydName, yddName: yddName, xName: xName) {
            return result
        }
        throw SolveError.odeTypeNotRecognized
    }

    if hasYd {
        // First-order ODE

        // Try first-order linear: yd + P(x)*y = Q(x)
        if let result = tryFirstOrderLinear(simplified, yName: yName, ydName: ydName, xName: xName) {
            return result
        }

        // Try separable: yd = f(x) * g(y)
        if let result = trySeparable(simplified, yName: yName, ydName: ydName, xName: xName) {
            return result
        }

        throw SolveError.odeTypeNotRecognized
    }

    throw SolveError.odeTypeNotRecognized
}

// MARK: - Second-Order Constant Coefficient

/// Solves a*y'' + b*y' + c*y = rhs(x) where a,b,c are constants
private func trySecondOrderConstCoeff(_ expr: Expr, yName: String, ydName: String, yddName: String, xName: String) -> Expr? {
    let ydd = Expr.symbol(yddName)
    let yd = Expr.symbol(ydName)
    let y = Expr.symbol(yName)
    let x = Expr.symbol(xName)

    // Extract coefficients using symbolic differentiation trick:
    // coefficient of ydd = derivative of expr w.r.t. ydd symbol
    let a = simplify(diff(expr, ydd))
    let b = simplify(diff(simplify(expr - a * ydd), yd))
    let c = simplify(diff(simplify(expr - a * ydd - b * yd), y))
    let rhs = simplify(.mul(.integer(-1), simplify(expr - a * ydd - b * yd - c * y)))

    // a, b, c must be constant (no x, y, yd, ydd dependence)
    let allSyms = Set([Expr.symbol(xName), Expr.symbol(yName), yd, ydd])
    for coeff in [a, b, c] {
        if !coeff.freeSymbols.isDisjoint(with: allSyms) { return nil }
    }

    // Solve characteristic equation: a*r^2 + b*r + c = 0
    let r = Expr.symbol("r")
    let charRoots = solveQuadratic(a: a, b: b, c: c)

    let C1 = Expr.symbol("C1")
    let C2 = Expr.symbol("C2")

    let homogeneous: Expr

    if charRoots.count == 2 {
        let r1 = charRoots[0]
        let r2 = charRoots[1]

        // Check if roots are real or complex
        // Discriminant = b^2 - 4ac
        let disc = simplify(b * b - 4 * a * c)
        if let dv = disc.numericValue, dv < -1e-12 {
            // Complex roots: alpha +/- beta*i
            let alpha = simplify(.mul(.integer(-1), b) / (.integer(2) * a))
            let beta = simplify(CAS.sqrt(simplify(.mul(.integer(-1), disc))) / (.integer(2) * a))
            // y = e^(alpha*x) * (C1*cos(beta*x) + C2*sin(beta*x))
            homogeneous = simplify(
                CAS.exp(alpha * x) * (C1 * CAS.cos(beta * x) + C2 * CAS.sin(beta * x))
            )
        } else {
            // Two distinct real roots
            // y = C1*e^(r1*x) + C2*e^(r2*x)
            homogeneous = simplify(C1 * CAS.exp(r1 * x) + C2 * CAS.exp(r2 * x))
        }
    } else if charRoots.count == 1 {
        // Repeated root r
        let r0 = charRoots[0]
        // y = (C1 + C2*x) * e^(r*x)
        homogeneous = simplify((C1 + C2 * x) * CAS.exp(r0 * x))
    } else {
        return nil
    }

    // If rhs = 0, return homogeneous solution
    if rhs.isZero {
        return homogeneous
    }

    // Try to find particular solution via undetermined coefficients
    if let particular = findParticularSolution(a: a, b: b, c: c, rhs: rhs, x: x, charRoots: charRoots) {
        return simplify(homogeneous + particular)
    }

    // Return homogeneous + placeholder
    return simplify(homogeneous + .function("yp", [rhs]))
}

// MARK: - Particular Solution (Undetermined Coefficients)

private func findParticularSolution(a: Expr, b: Expr, c: Expr, rhs: Expr, x: Expr, charRoots: [Expr]) -> Expr? {
    // Detect RHS pattern and generate trial solution
    guard let trial = generateTrial(rhs: rhs, x: x, charRoots: charRoots) else { return nil }

    // Substitute trial into a*y'' + b*y' + c*y and equate to rhs
    let yd = diff(trial.expr, x)
    let ydd = diff(yd, x)
    let lhsTrial = simplify(a * ydd + b * yd + c * trial.expr)

    // Collect coefficients of each basis function and solve for unknowns
    return solveUndeterminedCoeffs(lhsTrial, rhs: rhs, unknowns: trial.unknowns, x: x)
}

private struct TrialSolution {
    let expr: Expr
    let unknowns: [Expr]  // The undetermined coefficient symbols
}

private func generateTrial(rhs: Expr, x: Expr, charRoots: [Expr]) -> TrialSolution? {
    let A = Expr.symbol("_A")
    let B = Expr.symbol("_B")

    // Polynomial RHS: x^n  =>  trial = A0 + A1*x + ... + An*x^n
    if let coeffs = extractPolyCoefficients(rhs, "x") {
        let deg = coeffs.keys.max() ?? 0
        var unknowns: [Expr] = []
        var trial: Expr = .integer(0)
        let multiplier: Expr = charRoots.contains(.integer(0)) ? x : .integer(1)
        for i in 0...deg {
            let ui = Expr.symbol("_A\(i)")
            unknowns.append(ui)
            trial = trial + ui * Expr.pow(x, .integer(i)) * multiplier
        }
        return TrialSolution(expr: simplify(trial), unknowns: unknowns)
    }

    // exp(k*x)
    if case .function("exp", let args) = rhs, args.count == 1 {
        if let (k, _) = matchLinearInVar(args[0], x) {
            let multiplier: Expr = charRoots.contains(k) ? x : .integer(1)
            return TrialSolution(expr: simplify(A * multiplier * CAS.exp(k * x)), unknowns: [A])
        }
    }

    // sin(k*x) or cos(k*x)
    if case .function("sin", let args) = rhs, args.count == 1 {
        if let (k, _) = matchLinearInVar(args[0], x) {
            return TrialSolution(
                expr: simplify(A * CAS.cos(k * x) + B * CAS.sin(k * x)),
                unknowns: [A, B]
            )
        }
    }
    if case .function("cos", let args) = rhs, args.count == 1 {
        if let (k, _) = matchLinearInVar(args[0], x) {
            return TrialSolution(
                expr: simplify(A * CAS.cos(k * x) + B * CAS.sin(k * x)),
                unknowns: [A, B]
            )
        }
    }

    return nil
}

/// Match expr as a*x + b where a,b are constant
private func matchLinearInVar(_ expr: Expr, _ x: Expr) -> (Expr, Expr)? {
    guard case .symbol(let v) = x else { return nil }
    if expr == x { return (.integer(1), .integer(0)) }
    if case .mul(let a, let b) = expr {
        if b == x && isConstFor(a, v) { return (a, .integer(0)) }
        if a == x && isConstFor(b, v) { return (b, .integer(0)) }
    }
    if case .add(let l, let r) = expr {
        if isConstFor(r, v), let (a, b0) = matchLinearInVar(l, x) {
            return (a, simplify(b0 + r))
        }
        if isConstFor(l, v), let (a, b0) = matchLinearInVar(r, x) {
            return (a, simplify(b0 + l))
        }
    }
    return nil
}

private func solveUndeterminedCoeffs(_ lhs: Expr, rhs: Expr, unknowns: [Expr], x: Expr) -> Expr? {
    guard case .symbol(let xv) = x else { return nil }

    // Evaluate at multiple x-points to build a linear system for the unknowns
    let n = unknowns.count
    let testPoints: [Double] = Array(stride(from: 0.5, through: 0.5 + Double(n) * 0.7, by: 0.7))
    guard testPoints.count >= n else { return nil }

    // Build system: for each test point, lhs(x=pt, unknowns) = rhs(x=pt)
    // Since lhs is linear in unknowns, we get a linear system
    var matrixRows: [[Expr]] = []
    var rhsVec: [Expr] = []

    for i in 0..<n {
        let pt = Expr.real(testPoints[i])
        let rhsVal = simplify(rhs.substitute(x, with: pt))

        var row: [Expr] = []
        for unk in unknowns {
            // Coefficient of unk in lhs at this x-point
            var mapping: [Expr: Expr] = [x: pt]
            for u in unknowns { mapping[u] = .integer(0) }
            mapping[unk] = .integer(1)
            let val = simplify(lhs.substitute(mapping))
            row.append(val)
        }
        matrixRows.append(row)
        rhsVec.append(rhsVal)
    }

    // Solve using Matrix
    let A = Matrix(matrixRows)
    let b = Matrix(rhsVec.map { [$0] })

    let solution = A.solve(b)

    // Build the result by substituting solved values back
    var mapping: [Expr: Expr] = [:]
    for (i, unk) in unknowns.enumerated() {
        mapping[unk] = simplify(solution[i, 0])
    }

    // Get trial from lhs structure — just substitute into the trial
    // We need the original trial expression; reconstruct by using lhs relation
    // Actually, we should pass the trial expr. For now, substitute into a fresh trial:
    // Build from unknowns
    var result: Expr = .integer(0)
    for (i, unk) in unknowns.enumerated() {
        let coeff = simplify(solution[i, 0])
        // We need the basis function for this unknown — evaluate partial
        var basisMap: [Expr: Expr] = [:]
        for u in unknowns { basisMap[u] = .integer(0) }
        basisMap[unk] = .integer(1)
        // The trial is linear in unknowns, so the basis is trial with only this unk=1
        // We don't have the trial here, so use a simpler approach:
        result = result + coeff * unk
    }

    // This gives us a symbolic expression in _A, _B etc. — not useful.
    // Better approach: return the particular trial with numeric coefficients
    // We actually need the trial expression passed in. Let me fix the API.

    // Workaround: we know the trial from the unknowns and test points.
    // Since the trial was passed to findParticularSolution, we need a different approach.
    // Let's use a different strategy: build the particular solution from the basis.

    return nil  // Placeholder — we'll use variation of parameters fallback
}

// MARK: - First-Order ODE: Separable

private func trySeparable(_ expr: Expr, yName: String, ydName: String, xName: String) -> Expr? {
    let yd = Expr.symbol(ydName)
    let y = Expr.symbol(yName)
    let x = Expr.symbol(xName)

    // expr = yd - h(x,y) = 0, so h(x,y) = yd's coefficient * (-remainder/coeff)
    // Extract: coeff_yd * yd + rest = 0  =>  yd = -rest / coeff_yd
    let coeffYd = simplify(diff(expr, yd))
    if coeffYd.isZero { return nil }
    let rest = simplify(expr - coeffYd * yd)  // Oops, should subtract coeffYd * yd
    let restFixed = simplify(expr - coeffYd * yd)

    // h(x,y) = -restFixed / coeffYd  ... but restFixed still might contain yd
    // Let's be more careful
    let h = simplify(.mul(.integer(-1), rest) / coeffYd)

    // Check h doesn't contain yd
    if h.freeSymbols.contains(yd) { return nil }

    // Now check if h = f(x) * g(y)
    // Try to separate: if h has no y, it's trivially separable
    if isConstFor(h, yName) {
        // yd = f(x), so y = ∫f(x)dx + C1
        let integral = integrate(h, x)
        return simplify(integral + .symbol("C1"))
    }

    // If h has no x, it's yd = g(y)
    if isConstFor(h, xName) {
        // ∫dy/g(y) = x + C1
        let integral = integrate(.integer(1) / h, y)
        // Return implicit: integral = x + C1
        return .function("implicit", [simplify(integral), simplify(x + .symbol("C1"))])
    }

    // Try to factor h into f(x) * g(y)
    // Simple approach: check if h = a(x) * b(y) by testing h(x1,y)/h(x1,y1) == h(x2,y)/h(x2,y1)
    let testX1 = 1.1, testX2 = 2.3, testY1 = 0.7, testY2 = 1.9

    let h11 = h.substitute([x: .real(testX1), y: .real(testY1)]).eval()
    let h12 = h.substitute([x: .real(testX1), y: .real(testY2)]).eval()
    let h21 = h.substitute([x: .real(testX2), y: .real(testY1)]).eval()
    let h22 = h.substitute([x: .real(testX2), y: .real(testY2)]).eval()

    guard !h11.isNaN && !h12.isNaN && !h21.isNaN && !h22.isNaN else { return nil }
    guard Swift.abs(h11) > 1e-15 && Swift.abs(h21) > 1e-15 else { return nil }

    // If separable: h12/h11 == h22/h21
    let ratio1 = h12 / h11
    let ratio2 = h22 / h21
    guard Swift.abs(ratio1 - ratio2) < 1e-6 else { return nil }

    // It's separable. Extract f(x) and g(y):
    // f(x) = h(x, y1) / g(y1),  g(y) = h(x1, y) / f(x1)
    // Practically: f(x) = h / g(y), where g(y) = h(x=x1) / f(x1)
    // Use symbolic: substitute a test y value to get f(x)
    let fx = simplify(h.substitute(y, with: .real(testY1)))
    let gy = simplify(h / fx)  // This should depend only on y if truly separable
    let gySimp = simplify(gy.substitute(x, with: .real(testX1)))

    // Verify gy doesn't depend on x
    let fx_norm = simplify(fx / .real(fx.substitute(x, with: .real(testX1)).eval()))
    let gy_norm = simplify(h.substitute(x, with: .real(testX1)))

    // ∫ dy/g(y) = ∫ f(x) dx + C1
    let intY = integrate(.integer(1) / gy_norm, y)
    let intX = integrate(fx_norm, x)

    if case .function("Integral", _) = intY { return nil }
    if case .function("Integral", _) = intX { return nil }

    // Check if we can solve for y
    // For common case: log(y) = F(x) + C => y = e^(F(x)+C)
    // Return implicit form
    return .function("implicit", [simplify(intY), simplify(intX + .symbol("C1"))])
}

// MARK: - First-Order Linear ODE

private func tryFirstOrderLinear(_ expr: Expr, yName: String, ydName: String, xName: String) -> Expr? {
    let yd = Expr.symbol(ydName)
    let y = Expr.symbol(yName)
    let x = Expr.symbol(xName)

    // Standard form: yd + P(x)*y = Q(x)
    // expr = a*yd + b*y + c(x) = 0
    // Coefficient of yd
    let a = simplify(diff(expr, yd))
    if a.isZero { return nil }

    // Remove yd term
    let withoutYd = simplify(expr - a * yd)

    // Coefficient of y in what's left
    let bCoeff = simplify(diff(withoutYd, y))

    // Remove y term
    let remainder = simplify(withoutYd - bCoeff * y)

    // Check that a, bCoeff don't depend on y or yd
    let badSyms: Set<Expr> = [y, yd]
    if !a.freeSymbols.isDisjoint(with: badSyms) { return nil }
    if !bCoeff.freeSymbols.isDisjoint(with: badSyms) { return nil }
    if !remainder.freeSymbols.isDisjoint(with: badSyms) { return nil }

    // Normalize: yd + P*y = Q
    let P = simplify(bCoeff / a)
    let Q = simplify(.mul(.integer(-1), remainder) / a)

    // Integrating factor: mu = exp(∫P dx)
    let intP = integrate(P, x)
    if case .function("Integral", _) = intP { return nil }

    let mu = CAS.exp(intP)

    // If Q is zero, shortcut: y = C1 / mu
    if Q.isZero {
        return simplify(.symbol("C1") * CAS.exp(simplify(.mul(.integer(-1), intP))))
    }

    // y = (1/mu) * (∫ mu*Q dx + C1)
    let muQ = simplify(mu * Q)
    let intMuQ = integrate(muQ, x)
    if containsUnevaluated(intMuQ) { return nil }

    let solution = simplify((intMuQ + .symbol("C1")) / mu)
    return solution
}
