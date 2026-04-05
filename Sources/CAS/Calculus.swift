import Foundation

// MARK: - Differentiation

public func diff(_ expr: Expr, _ variable: Expr) -> Expr {
    guard case .symbol(let varName) = variable else {
        fatalError("Can only differentiate with respect to a symbol")
    }
    return simplify(rawDiff(expr, varName))
}

public func diff(_ expr: Expr, _ variable: Expr, order n: Int) -> Expr {
    var result = expr
    for _ in 0..<n {
        result = diff(result, variable)
    }
    return result
}

private func rawDiff(_ expr: Expr, _ v: String) -> Expr {
    switch expr {
    case .integer, .rational, .real, .constant:
        return .integer(0)

    case .symbol(let name):
        return name == v ? .integer(1) : .integer(0)

    // d/dx [f + g] = f' + g'
    case .add(let a, let b):
        return .add(rawDiff(a, v), rawDiff(b, v))

    // d/dx [f * g] = f'g + fg'
    case .mul(let a, let b):
        return .add(.mul(rawDiff(a, v), b), .mul(a, rawDiff(b, v)))

    // d/dx [f^g] = f^g * (g' * ln(f) + g * f'/f)
    case .pow(let base, let exp):
        if exp.freeSymbols.isEmpty {
            // f(x)^n  =>  n * f^(n-1) * f'
            return .mul(.mul(exp, .pow(base, .add(exp, .integer(-1)))), rawDiff(base, v))
        }
        if base.freeSymbols.isEmpty {
            // a^g(x)  =>  a^g * ln(a) * g'
            return .mul(.mul(.pow(base, exp), .function("log", [base])), rawDiff(exp, v))
        }
        // General: f^g = e^(g*ln(f))
        let logForm: Expr = .function("exp", [Expr.mul(exp, .function("log", [base]))])
        return rawDiff(logForm, v)

    case .function(let name, let args):
        // Return 0 for unevaluated forms to avoid crashes
        if name == "Integral" || name == "Limit" || name == "yp" {
            return .integer(0)
        }
        guard args.count == 1 else {
            return .function("D", [expr, .symbol(v)])  // return unevaluated derivative
        }
        let u = args[0]
        let du = rawDiff(u, v)
        let inner: Expr
        switch name {
        case "sin":   inner = .function("cos", [u])
        case "cos":   inner = .mul(.integer(-1), .function("sin", [u]))
        case "tan":   inner = .pow(.function("cos", [u]), .integer(-2))
        case "exp":   inner = .function("exp", [u])
        case "log":   inner = .pow(u, .integer(-1))
        case "asin":  inner = .pow(.add(.integer(1), .mul(.integer(-1), .pow(u, .integer(2)))), .rational(-1, 2))
        case "acos":  inner = .mul(.integer(-1), .pow(.add(.integer(1), .mul(.integer(-1), .pow(u, .integer(2)))), .rational(-1, 2)))
        case "atan":  inner = .pow(.add(.integer(1), .pow(u, .integer(2))), .integer(-1))
        case "sinh":  inner = .function("cosh", [u])
        case "cosh":  inner = .function("sinh", [u])
        case "tanh":  inner = .pow(.function("cosh", [u]), .integer(-2))
        case "abs":   inner = .mul(u, .pow(.function("abs", [u]), .integer(-1)))
        default:
            fatalError("Don't know how to differentiate \(name)")
        }
        return .mul(inner, du)

    case .matrix:
        fatalError("Cannot differentiate a matrix expression directly")
    }
}

// MARK: - Integration (basic symbolic)

public func integrate(_ expr: Expr, _ variable: Expr) -> Expr {
    guard case .symbol(let v) = variable else {
        fatalError("Can only integrate with respect to a symbol")
    }
    return simplify(rawIntegrate(simplify(expr), v))
}

public func integrate(_ expr: Expr, _ variable: Expr, from lower: Expr, to upper: Expr) -> Expr {
    let antideriv = integrate(expr, variable)
    let upper_val = antideriv.substitute(variable, with: upper)
    let lower_val = antideriv.substitute(variable, with: lower)
    return simplify(upper_val - lower_val)
}

private let x_ = Expr.symbol  // shorthand for building expressions

private func isConst(_ expr: Expr, _ v: String) -> Bool {
    expr.freeSymbols.allSatisfy { $0 != .symbol(v) }
}

/// Flatten a multiplication tree and separate constant vs variable-dependent factors.
private func extractConstantFactors(_ expr: Expr, _ v: String) -> (Expr, Expr) {
    var factors: [Expr] = []
    flattenMul(expr, into: &factors)

    var constFactors: [Expr] = []
    var varFactors: [Expr] = []
    for f in factors {
        if isConst(f, v) {
            constFactors.append(f)
        } else {
            varFactors.append(f)
        }
    }

    let c = constFactors.isEmpty ? Expr.integer(1) : constFactors.dropFirst().reduce(constFactors[0]) { Expr.mul($0, $1) }
    let r = varFactors.isEmpty ? Expr.integer(1) : varFactors.dropFirst().reduce(varFactors[0]) { Expr.mul($0, $1) }
    return (simplify(c), simplify(r))
}

private func flattenMul(_ expr: Expr, into factors: inout [Expr]) {
    if case .mul(let a, let b) = expr {
        flattenMul(a, into: &factors)
        flattenMul(b, into: &factors)
    } else {
        factors.append(expr)
    }
}

private func isUnevaluated(_ expr: Expr) -> Bool {
    if case .function("Integral", _) = expr { return true }
    return false
}

private func rawIntegrate(_ expr: Expr, _ v: String, depth: Int = 0) -> Expr {
    let sv = Expr.symbol(v)

    // Depth guard
    if depth > 12 {
        return .function("Integral", [expr, sv])
    }

    // Constant
    if isConst(expr, v) {
        return .mul(expr, sv)
    }

    // --- Linearity: integral(a + b) = integral(a) + integral(b) ---
    if case .add(let a, let b) = expr {
        return .add(rawIntegrate(a, v, depth: depth), rawIntegrate(b, v, depth: depth))
    }

    // --- Constant multiple: extract all constant factors from product ---
    if case .mul = expr {
        let (constPart, varPart) = extractConstantFactors(expr, v)
        if constPart != .integer(1) && !isConst(varPart, v) {
            return .mul(constPart, rawIntegrate(varPart, v, depth: depth))
        }
    }

    // --- x ---
    if expr == sv {
        return .mul(.rational(1, 2), .pow(sv, .integer(2)))
    }

    // --- x^n (n constant) ---
    if case .pow(let base, let n) = expr, base == sv, isConst(n, v) {
        if n == .integer(-1) {
            return .function("log", [.function("abs", [sv])])
        }
        let n1 = Expr.add(n, .integer(1))
        return .mul(.pow(n1, .integer(-1)), .pow(sv, n1))
    }

    // --- Standard functions of x ---
    if case .function(let name, let args) = expr, args.count == 1, args[0] == sv {
        if let result = integrateStandardFunction(name, sv) {
            return result
        }
    }

    // --- Functions of linear argument: f(ax+b) ---
    if case .function(let name, let args) = expr, args.count == 1 {
        if let (a, _) = matchLinear(args[0], v), let base = integrateStandardFunction(name, sv) {
            let result = base.substitute(sv, with: args[0])
            return .mul(.pow(a, .integer(-1)), result)
        }
    }

    // --- Powers of functions: f(x)^n where we know the integral ---
    if case .pow(let base, let n) = expr, isConst(n, v) {
        // sin(x)^2 = (1 - cos(2x))/2
        if case .function("sin", let args) = base, args.count == 1, args[0] == sv, n == .integer(2) {
            return simplify(.mul(.rational(1, 2), sv) - .mul(.rational(1, 4), .function("sin", [.mul(.integer(2), sv)])))
        }
        // cos(x)^2 = (1 + cos(2x))/2
        if case .function("cos", let args) = base, args.count == 1, args[0] == sv, n == .integer(2) {
            return simplify(.mul(.rational(1, 2), sv) + .mul(.rational(1, 4), .function("sin", [.mul(.integer(2), sv)])))
        }
        // sec(x)^2 = tan(x)
        if case .function("sec", let args) = base, args.count == 1, args[0] == sv, n == .integer(2) {
            return .function("tan", [sv])
        }
        // (x^2 + a)^(-1) = (1/sqrt(a)) * atan(x/sqrt(a))
        if n == .integer(-1), let result = tryIntegrateRationalSimple(base, v) {
            return result
        }
        // (a - x^2)^(-1/2) = asin(x/sqrt(a))  [inverse trig]
        if n == .rational(-1, 2), let result = tryIntegrateSqrtForm(base, v) {
            return result
        }
        // (a + x^2)^(-1/2) = log(x + sqrt(x^2+a))  [inverse hyperbolic / log form]
        if n == .rational(-1, 2), let result = tryIntegrateSqrtFormPositive(base, v) {
            return result
        }
    }

    // --- Product of trig functions: sin(x)*cos(x) = sin(2x)/2 ---
    if case .mul(let a, let b) = expr {
        if let result = tryTrigProduct(a, b, v, depth: depth) { return result }
    }

    // --- u-substitution ---
    if let result = tryUSubstitution(expr, v, depth: depth) {
        return result
    }

    // --- Integration by parts: ∫ u dv = uv - ∫ v du ---
    if let result = tryIntegrationByParts(expr, v, depth: depth) {
        return result
    }

    // --- Multiply out products that can be expanded ---
    if let expanded = tryExpand(expr, v) {
        let result = rawIntegrate(expanded, v, depth: depth + 1)
        if !isUnevaluated(result) { return result }
    }

    // Fallback: return unevaluated integral notation
    return .function("Integral", [expr, sv])
}

// MARK: - Standard Function Table

private func integrateStandardFunction(_ name: String, _ x: Expr) -> Expr? {
    switch name {
    case "sin":  return .mul(.integer(-1), .function("cos", [x]))
    case "cos":  return .function("sin", [x])
    case "tan":  return .mul(.integer(-1), .function("log", [.function("abs", [.function("cos", [x])])]))
    case "cot":  return .function("log", [.function("abs", [.function("sin", [x])])])
    case "sec":  return .function("log", [.function("abs", [.add(.function("sec", [x]), .function("tan", [x]))])])
    case "csc":  return .mul(.integer(-1), .function("log", [.function("abs", [.add(.function("csc", [x]), .function("cot", [x]))])]))
    case "exp":  return .function("exp", [x])
    case "log":  return .add(.mul(x, .function("log", [x])), .mul(.integer(-1), x))  // x*ln(x) - x
    case "cosh": return .function("sinh", [x])
    case "sinh": return .function("cosh", [x])
    case "tanh": return .function("log", [.function("cosh", [x])])
    case "asin": return .add(.mul(x, .function("asin", [x])), .pow(.add(.integer(1), .mul(.integer(-1), .pow(x, .integer(2)))), .rational(1, 2)))
    case "acos": return .add(.mul(x, .function("acos", [x])), .mul(.integer(-1), .pow(.add(.integer(1), .mul(.integer(-1), .pow(x, .integer(2)))), .rational(1, 2))))
    case "atan": return .add(.mul(x, .function("atan", [x])), .mul(.rational(-1, 2), .function("log", [.add(.integer(1), .pow(x, .integer(2)))])))
    default:     return nil
    }
}

// MARK: - Match linear form ax + b

private func matchLinear(_ expr: Expr, _ v: String) -> (Expr, Expr)? {
    let sv = Expr.symbol(v)

    // Just x  =>  (1, 0)
    if expr == sv { return (.integer(1), .integer(0)) }

    // a*x  =>  (a, 0)
    if case .mul(let a, let b) = expr {
        if b == sv && isConst(a, v) { return (a, .integer(0)) }
        if a == sv && isConst(b, v) { return (b, .integer(0)) }
    }

    // a*x + b  or  b + a*x
    if case .add(let left, let right) = expr {
        if isConst(right, v), let (a, b0) = matchLinear(left, v), b0 == .integer(0) {
            return (a, right)
        }
        if isConst(left, v), let (a, b0) = matchLinear(right, v), b0 == .integer(0) {
            return (a, left)
        }
    }

    return nil
}

// MARK: - Trig Product

private func tryTrigProduct(_ a: Expr, _ b: Expr, _ v: String, depth: Int) -> Expr? {
    let sv = Expr.symbol(v)

    // sin(x)*cos(x) = sin(2x)/2  =>  ∫ = -cos(2x)/4
    if case .function("sin", let args1) = a, case .function("cos", let args2) = b,
       args1.count == 1, args2.count == 1, args1[0] == args2[0] {
        let u = args1[0]
        return .mul(.rational(-1, 4), .function("cos", [.mul(.integer(2), u)]))
    }
    if case .function("cos", let args1) = a, case .function("sin", let args2) = b,
       args1.count == 1, args2.count == 1, args1[0] == args2[0] {
        let u = args1[0]
        return .mul(.rational(-1, 4), .function("cos", [.mul(.integer(2), u)]))
    }

    return nil
}

// MARK: - u-Substitution

private func tryUSubstitution(_ expr: Expr, _ v: String, depth: Int = 0) -> Expr? {
    let sv = Expr.symbol(v)

    // Pattern: f'(g(x)) * g'(x)  =>  f(g(x))
    // More practically: look for expressions where one factor is the derivative of an inner function

    guard case .mul(let a, let b) = expr else { return nil }

    // Try both orderings
    for (outer, inner) in [(a, b), (b, a)] {
        if let result = tryUSubInner(outer, inner, v) {
            return result
        }
    }

    return nil
}

private func tryUSubInner(_ outer: Expr, _ inner: Expr, _ v: String) -> Expr? {
    let sv = Expr.symbol(v)

    // Look for f(g(x)) * g'(x) patterns
    // e.g., x * exp(x^2)  =>  u=x^2, du=2x dx  => (1/2) exp(u)

    // Case: inner contains a sub-expression u(x), and outer ~ du/dx * something
    // Try common u-substitution candidates

    // Candidate: x * f(x^2)  =>  u = x^2
    if case .function(let name, let args) = inner, args.count == 1 {
        let u = args[0]
        let du = simplify(rawDiff(u, v))
        // Check if outer = c * du for some constant c
        if let c = matchConstantMultiple(outer, du, v) {
            if let antideriv = integrateStandardFunction(name, sv) {
                let result = antideriv.substitute(sv, with: u)
                return .mul(c, result)
            }
        }
    }

    // Candidate: g'(x) * g(x)^n  =>  u = g(x), ∫u^n du = u^(n+1)/(n+1)
    if case .pow(let base, let n) = inner, isConst(n, v), !isConst(base, v) {
        let du = simplify(rawDiff(base, v))
        if let c = matchConstantMultiple(outer, du, v) {
            if n == .integer(-1) {
                return .mul(c, .function("log", [.function("abs", [base])]))
            }
            let n1 = Expr.add(n, .integer(1))
            return .mul(c, .mul(.pow(n1, .integer(-1)), .pow(base, n1)))
        }
    }

    // Candidate: outer is f(g(x)) and inner is g'(x)
    if case .function(let name, let args) = outer, args.count == 1 {
        let u = args[0]
        let du = simplify(rawDiff(u, v))
        if let c = matchConstantMultiple(inner, du, v) {
            if let antideriv = integrateStandardFunction(name, sv) {
                let result = antideriv.substitute(sv, with: u)
                return .mul(c, result)
            }
        }
    }

    return nil
}

/// Check if expr = c * target for some constant c. Returns c or nil.
private func matchConstantMultiple(_ expr: Expr, _ target: Expr, _ v: String) -> Expr? {
    if expr == target { return .integer(1) }

    // expr = c * target
    if case .mul(let a, let b) = expr {
        if isConst(a, v) && b == target { return a }
        if isConst(b, v) && a == target { return b }
    }

    // target = c * expr  =>  return 1/c
    if case .mul(let a, let b) = target {
        if isConst(a, v) && b == expr { return .pow(a, .integer(-1)) }
        if isConst(b, v) && a == expr { return .pow(b, .integer(-1)) }
    }

    // Try numeric comparison for simple cases
    if let ev = expr.numericValue, let tv = target.numericValue, tv != 0 {
        let ratio = ev / tv
        if ratio == ratio.rounded() {
            return .integer(Int(ratio))
        }
        // Check simple fractions
        for d in 1...12 {
            let candidate = (ratio * Double(d)).rounded() / Double(d)
            if Swift.abs(ratio - candidate) < 1e-10 {
                let num = Int((ratio * Double(d)).rounded())
                if d == 1 { return .integer(num) }
                return .rational(num, d)
            }
        }
    }

    return nil
}

// MARK: - Integration by Parts

/// ∫ u dv = u*v - ∫ v du
/// Heuristic: LIATE rule (Log, Inverse trig, Algebraic, Trig, Exponential)
private func tryIntegrationByParts(_ expr: Expr, _ v: String, depth: Int = 0) -> Expr? {
    guard depth < 6 else { return nil }

    guard case .mul(let a, let b) = expr else { return nil }

    // Both factors must depend on v
    guard !isConst(a, v) && !isConst(b, v) else { return nil }

    // Use LIATE to pick u (the one to differentiate) vs dv (the one to integrate)
    let (u, dv) = liatePick(a, b)

    let du = simplify(rawDiff(u, v))
    let vInteg = rawIntegrate(dv, v, depth: depth + 1)

    // If we couldn't integrate dv, try the other way
    if isUnevaluated(vInteg) {
        let (u2, dv2) = (dv, u)
        let du2 = simplify(rawDiff(u2, v))
        let vInteg2 = rawIntegrate(dv2, v, depth: depth + 1)
        if isUnevaluated(vInteg2) { return nil }
        let remainder = rawIntegrate(simplify(.mul(vInteg2, du2)), v, depth: depth + 2)
        if isUnevaluated(remainder) { return nil }
        return simplify(.add(.mul(u2, vInteg2), .mul(.integer(-1), remainder)))
    }

    let remainder = simplify(.mul(vInteg, du))

    // Special case: tabular/cyclic integration by parts (e.g., ∫e^x sin(x) dx)
    if let result = trySolveCyclicIBP(expr, u, vInteg, remainder, v, depth: depth) {
        return result
    }

    let remInteg = rawIntegrate(remainder, v, depth: depth + 2)
    if isUnevaluated(remInteg) { return nil }

    return simplify(.add(.mul(u, vInteg), .mul(.integer(-1), remInteg)))
}

private func liatePriority(_ expr: Expr) -> Int {
    switch expr {
    case .function("log", _): return 5
    case .function("asin", _), .function("acos", _), .function("atan", _): return 4
    case .symbol, .pow(.symbol(_), _): return 3  // algebraic
    case .function("sin", _), .function("cos", _), .function("tan", _): return 2
    case .function("exp", _), .pow(.constant(.e), _): return 1
    default:
        if case .pow(let base, _) = expr, case .symbol = base { return 3 }
        return 0
    }
}

private func liatePick(_ a: Expr, _ b: Expr) -> (Expr, Expr) {
    let pa = liatePriority(a)
    let pb = liatePriority(b)
    return pa >= pb ? (a, b) : (b, a)
}

/// Handle cyclic IBP: ∫e^x sin(x) dx type problems
/// After first IBP: I = u1*v1 - ∫ remainder
/// Do a second IBP on remainder: ∫ remainder = u2*v2 - ∫ remainder2
/// If remainder2 = c * original: I = u1*v1 - u2*v2 + c*I  =>  I = (u1*v1 - u2*v2) / (1 - c)
private func trySolveCyclicIBP(_ original: Expr, _ u1: Expr, _ v1: Expr, _ remainder: Expr, _ v: String, depth: Int = 0) -> Expr? {
    let sv = Expr.symbol(v)

    // Extract constant factors from remainder
    let (remConst, remVar) = extractConstantFactors(remainder, v)

    // remVar must be a product of two v-dependent factors for IBP
    var varFactors: [Expr] = []
    flattenMul(remVar, into: &varFactors)
    let depFactors = varFactors.filter { !isConst($0, v) }
    guard depFactors.count >= 2 else { return nil }

    // Second IBP on remVar
    let left = depFactors[0]
    let right = depFactors.count == 2
        ? depFactors[1]
        : simplify(depFactors.dropFirst().reduce(Expr.integer(1)) { Expr.mul($0, $1) })
    let (u2, dv2) = liatePick(left, right)
    let du2 = simplify(rawDiff(u2, v))
    let v2 = rawIntegrate(dv2, v, depth: depth + 4)
    if isUnevaluated(v2) { return nil }

    // remainder2 from second IBP = v2 * du2
    let remainder2 = simplify(.mul(v2, du2))

    // The full second remainder (including remConst) compared to original
    // ∫ remainder = remConst * (u2*v2 - ∫ remainder2)
    // We need: remConst * remainder2 = c * original
    if let ratio = numericRatio(remainder2, original, v) {
        let c = ratio * (remConst.numericValue ?? 1.0)
        // I = u1*v1 - remConst*(u2*v2) + c*I
        // I*(1-c) = u1*v1 - remConst*u2*v2
        if Swift.abs(1.0 - c) > 1e-10 {
            let u2v2 = simplify(Expr.mul(remConst, .mul(u2, v2)))
            let numer = simplify(Expr.add(.mul(u1, v1), .mul(.integer(-1), u2v2)))
            let denomVal = 1.0 - c
            let denom: Expr
            if Swift.abs(denomVal - denomVal.rounded()) < 1e-10 {
                denom = .integer(Int(denomVal.rounded()))
            } else {
                denom = .real(denomVal)
            }
            return simplify(.mul(numer, .pow(denom, .integer(-1))))
        }
    }

    return nil
}

/// Check if a/b is a constant by evaluating at several random points.
private func numericRatio(_ a: Expr, _ b: Expr, _ v: String) -> Double? {
    let sv = Expr.symbol(v)
    let testPoints = [1.1, 2.3, 0.7]
    var ratios: [Double] = []

    for pt in testPoints {
        let va = a.substitute(sv, with: .real(pt)).eval()
        let vb = b.substitute(sv, with: .real(pt)).eval()
        if vb.isNaN || vb.isInfinite || Swift.abs(vb) < 1e-15 { return nil }
        if va.isNaN || va.isInfinite { return nil }
        ratios.append(va / vb)
    }

    // All ratios should be the same
    guard let first = ratios.first else { return nil }
    for r in ratios {
        if Swift.abs(r - first) > 1e-6 { return nil }
    }
    return first
}

// MARK: - Rational / Inverse Trig Forms

/// ∫ 1/(x² + a) dx = (1/√a) atan(x/√a)   for a > 0
/// ∫ 1/(x² - a) dx = partial fractions
private func tryIntegrateRationalSimple(_ base: Expr, _ v: String) -> Expr? {
    let sv = Expr.symbol(v)

    // Match x² + a  or  a + x²
    if case .add(let left, let right) = base {
        let (xPart, constPart): (Expr, Expr)
        if isConst(right, v) { (xPart, constPart) = (left, right) }
        else if isConst(left, v) { (xPart, constPart) = (right, left) }
        else { return nil }

        // Check xPart = x^2
        guard case .pow(let b, .integer(2)) = xPart, b == sv else { return nil }

        if let a = constPart.numericValue {
            if a > 0 {
                // ∫ 1/(x²+a) = (1/√a) atan(x/√a)
                let sqrtA = Expr.pow(constPart, .rational(1, 2))
                return .mul(.pow(sqrtA, .integer(-1)), .function("atan", [.mul(sv, .pow(sqrtA, .integer(-1)))]))
            } else if a < 0 {
                // ∫ 1/(x²-|a|) = partial fractions: (1/2√|a|) * log(|(x-√|a|)/(x+√|a|)|)
                let absA: Expr = .integer(Int(-a))
                let sqrtA = Expr.pow(absA, .rational(1, 2))
                let num = Expr.add(sv, .mul(.integer(-1), sqrtA))
                let den = Expr.add(sv, sqrtA)
                return .mul(
                    .pow(.mul(.integer(2), sqrtA), .integer(-1)),
                    .function("log", [.function("abs", [.mul(num, .pow(den, .integer(-1)))])])
                )
            }
        }
    }
    return nil
}

/// ∫ 1/√(a - x²) dx = asin(x/√a)
private func tryIntegrateSqrtForm(_ base: Expr, _ v: String) -> Expr? {
    let sv = Expr.symbol(v)

    if case .add(let left, let right) = base {
        // a + (-1)*x^2  or  a - x^2
        let (constPart, xPart): (Expr, Expr)
        if isConst(left, v) { (constPart, xPart) = (left, right) }
        else if isConst(right, v) { (constPart, xPart) = (right, left) }
        else { return nil }

        // xPart should be -x^2 => mul(-1, pow(x, 2))
        var isNegX2 = false
        if case .mul(.integer(-1), .pow(let b, .integer(2))) = xPart, b == sv { isNegX2 = true }
        if case .mul(.pow(let b, .integer(2)), .integer(-1)) = xPart, b == sv { isNegX2 = true }
        // Also handle integer subtraction: add(1, integer(-1)*x^2) simplified form
        if case .integer(let n) = xPart, n < 0 { return nil } // that's just a number

        if isNegX2 {
            if constPart == .integer(1) {
                return .function("asin", [sv])
            }
            let sqrtA = Expr.pow(constPart, .rational(1, 2))
            return .function("asin", [.mul(sv, .pow(sqrtA, .integer(-1)))])
        }
    }
    return nil
}

/// ∫ 1/√(x² + a) dx = log(x + √(x²+a))  (inverse sinh form)
private func tryIntegrateSqrtFormPositive(_ base: Expr, _ v: String) -> Expr? {
    let sv = Expr.symbol(v)

    if case .add(let left, let right) = base {
        let (constPart, xPart): (Expr, Expr)
        if isConst(right, v) { (constPart, xPart) = (right, left) }
        else if isConst(left, v) { (constPart, xPart) = (left, right) }
        else { return nil }

        guard case .pow(let b, .integer(2)) = xPart, b == sv else { return nil }

        if let a = constPart.numericValue, a > 0 {
            return .function("log", [.add(sv, .pow(base, .rational(1, 2)))])
        }
    }
    return nil
}

// MARK: - Expansion helper

private func tryExpand(_ expr: Expr, _ v: String) -> Expr? {
    // x * (x + 1)  =>  x^2 + x
    if case .mul(let a, let b) = expr {
        if case .add(let b1, let b2) = b {
            return .add(.mul(a, b1), .mul(a, b2))
        }
        if case .add(let a1, let a2) = a {
            return .add(.mul(a1, b), .mul(a2, b))
        }
        // x * x  =>  x^2
        if a == .symbol(v) && b == .symbol(v) {
            return .pow(.symbol(v), .integer(2))
        }
    }
    return nil
}

// MARK: - Limits

public func limit(_ expr: Expr, _ variable: Expr, to point: Expr, direction: LimitDirection = .both) -> Expr {
    guard case .symbol = variable else {
        fatalError("Can only take limits with respect to a symbol")
    }

    // Try direct numeric evaluation first (catches non-indeterminate cases)
    if let pointVal2 = point.numericValue {
        let val = expr.substitute(variable, with: .real(pointVal2)).eval()
        if !val.isNaN && !val.isInfinite {
            if Swift.abs(val - val.rounded()) < 1e-10 {
                return .integer(Int(val.rounded()))
            }
            return .real(val)
        }
    }

    // Numerical approach for indeterminate forms
    guard let pointVal = point.numericValue else {
        return .function("Limit", [expr, variable, point])
    }

    // Use a sequence of decreasing h to estimate the limit
    let hValues = [1e-3, 1e-5, 1e-7, 1e-9]

    func evalAt(_ pt: Double) -> Double? {
        let val = expr.substitute(variable, with: .real(pt)).eval()
        if val.isNaN || val.isInfinite { return nil }
        return val
    }

    switch direction {
    case .both:
        // Evaluate from both sides at multiple scales
        var lastLeft: Double?
        var lastRight: Double?
        for h in hValues {
            lastLeft = evalAt(pointVal - h) ?? lastLeft
            lastRight = evalAt(pointVal + h) ?? lastRight
        }
        guard let lv = lastLeft, let rv = lastRight else {
            return .function("Limit", [expr, variable, point])
        }
        if Swift.abs(lv - rv) < 1e-4 {
            let avg = (lv + rv) / 2
            if Swift.abs(avg - avg.rounded()) < 1e-4 {
                return .integer(Int(avg.rounded()))
            }
            // Check simple fractions
            for denom in 1...12 {
                let candidate = (avg * Double(denom)).rounded() / Double(denom)
                if Swift.abs(avg - candidate) < 1e-6 {
                    let num = Int((avg * Double(denom)).rounded())
                    if denom == 1 { return .integer(num) }
                    return .rational(num, denom)
                }
            }
            return .real(avg)
        }
        return .function("Limit", [expr, variable, point])

    case .left:
        let val = hValues.compactMap({ evalAt(pointVal - $0) }).last ?? .nan
        return .real(val)

    case .right:
        let val = hValues.compactMap({ evalAt(pointVal + $0) }).last ?? .nan
        return .real(val)
    }
}

public enum LimitDirection {
    case left, right, both
}

// MARK: - Taylor Series

public func taylor(_ expr: Expr, _ variable: Expr, around point: Expr = .integer(0), terms n: Int = 6) -> Expr {
    var result: Expr = .integer(0)
    var currentDeriv = expr

    for k in 0..<n {
        let coeff = simplify(currentDeriv.substitute(variable, with: point))
        if !coeff.isZero {
            var factorialVal = 1
            for i in 1...max(1, k) { factorialVal *= i }
            let term: Expr = .mul(
                .mul(.pow(.integer(factorialVal), .integer(-1)), coeff),
                .pow(.add(variable, .mul(.integer(-1), point)), .integer(k))
            )
            result = .add(result, term)
        }
        currentDeriv = diff(currentDeriv, variable)
    }

    return simplify(result)
}

// MARK: - Gradient & Jacobian

public func gradient(_ expr: Expr, _ variables: [Expr]) -> [Expr] {
    variables.map { diff(expr, $0) }
}

public func jacobian(_ exprs: [Expr], _ variables: [Expr]) -> Matrix {
    let elements = exprs.map { expr in
        variables.map { v in diff(expr, v) }
    }
    return Matrix(elements)
}

public func hessian(_ expr: Expr, _ variables: [Expr]) -> Matrix {
    let elements = variables.map { vi in
        variables.map { vj in diff(diff(expr, vi), vj) }
    }
    return Matrix(elements)
}
