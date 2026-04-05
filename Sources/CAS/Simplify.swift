import Foundation

// MARK: - Algebraic Simplification

public func simplify(_ expr: Expr) -> Expr {
    let result = simplifyOnce(expr)
    if result == expr {
        return result
    }
    return simplify(result)
}

private func simplifyOnce(_ expr: Expr) -> Expr {
    switch expr {

    // Atoms pass through
    case .integer, .rational, .real, .constant, .symbol:
        return expr

    // --- Addition ---
    case .add(let a, let b):
        let sa = simplify(a)
        let sb = simplify(b)

        // Matrix + Matrix
        if case .matrix(let m1) = sa, case .matrix(let m2) = sb {
            return .matrix(m1 + m2)
        }

        // 0 + x = x
        if sa.isZero { return sb }
        if sb.isZero { return sa }

        // n + m = n+m
        if case .integer(let n) = sa, case .integer(let m) = sb {
            return .integer(n + m)
        }

        // Rational arithmetic
        if let (p1, q1) = asRational(sa), let (p2, q2) = asRational(sb) {
            return normalizeRational(p1 * q2 + p2 * q1, q1 * q2)
        }

        // x + x = 2*x
        if sa == sb {
            return simplify(.mul(.integer(2), sa))
        }

        // c1*x + c2*x = (c1+c2)*x
        let (c1, t1) = splitCoefficient(sa)
        let (c2, t2) = splitCoefficient(sb)
        if t1 == t2 {
            let newCoeff = c1 + c2
            if newCoeff == 0 { return .integer(0) }
            if newCoeff == 1 { return t1 }
            return simplify(.mul(.integer(newCoeff), t1))
        }

        // Flatten and collect terms
        let terms = collectAddTerms(.add(sa, sb))
        let collected = collectLikeTerms(terms)
        if collected.count == 1 { return collected[0] }
        if collected.count >= 2 {
            let rebuilt = collected.dropFirst().reduce(collected[0]) { Expr.add($0, $1) }
            if rebuilt != .add(sa, sb) {
                return rebuilt
            }
        }

        return .add(sa, sb)

    // --- Multiplication ---
    case .mul(let a, let b):
        let sa = simplify(a)
        let sb = simplify(b)

        // Matrix * Matrix
        if case .matrix(let m1) = sa, case .matrix(let m2) = sb {
            return .matrix(m1 * m2)
        }
        // Scalar * Matrix
        if case .matrix(let m) = sb, sa.isNumeric || sa.freeSymbols.isEmpty == false {
            return .matrix(sa * m)
        }
        if case .matrix(let m) = sa, sb.isNumeric || sb.freeSymbols.isEmpty == false {
            return .matrix(sb * m)
        }
        // Matrix + Matrix
        // (handled in add below, but cover mul-of-matrices here)

        // 0 * x = 0
        if sa.isZero || sb.isZero { return .integer(0) }
        // 1 * x = x
        if sa.isOne { return sb }
        if sb.isOne { return sa }
        // -1 * (-1 * x) = x
        if case .integer(-1) = sa, case .mul(.integer(-1), let inner) = sb {
            return inner
        }

        // n * m = n*m
        if case .integer(let n) = sa, case .integer(let m) = sb {
            return .integer(n * m)
        }

        // Rational arithmetic
        if let (p1, q1) = asRational(sa), let (p2, q2) = asRational(sb) {
            return normalizeRational(p1 * p2, q1 * q2)
        }

        // x * x = x^2
        if sa == sb {
            return simplify(.pow(sa, .integer(2)))
        }

        // x^a * x^b = x^(a+b)
        let (base1, exp1) = splitPower(sa)
        let (base2, exp2) = splitPower(sb)
        if base1 == base2 {
            return simplify(.pow(base1, simplify(.add(exp1, exp2))))
        }

        // Cancel common factors: (a*b) * b^(-1) = a, (a*b) * a^(-1) = b
        if case .mul(let inner1, let inner2) = sa {
            let (base2, exp2) = splitPower(sb)
            if case .integer(-1) = exp2 {
                if inner1 == base2 { return inner2 }
                if inner2 == base2 { return inner1 }
            }
        }
        if case .mul(let inner1, let inner2) = sb {
            let (base1, exp1) = splitPower(sa)
            if case .integer(-1) = exp1 {
                if inner1 == base1 { return inner2 }
                if inner2 == base1 { return inner1 }
            }
        }

        // Flatten and cancel: collect all factors, match bases, combine exponents
        if case .pow = sa, case .mul = sb {
            let simplified = flattenAndCancel(sa, sb)
            if let s = simplified { return s }
        }
        if case .mul = sa, case .pow = sb {
            let simplified = flattenAndCancel(sb, sa)
            if let s = simplified { return s }
        }

        // Associativity: (a * n) * (p/q) = a * (n*p/q) and (a * n) * m = a * (n*m)
        if case .mul(let inner1, let inner2) = sa {
            if let r = asRational(sb) {
                if let n = asRational(inner2) {
                    return simplify(.mul(inner1, normalizeRational(n.0 * r.0, n.1 * r.1)))
                }
                if let n = asRational(inner1) {
                    return simplify(.mul(inner2, normalizeRational(n.0 * r.0, n.1 * r.1)))
                }
            }
        }
        if case .mul(let inner1, let inner2) = sb {
            if let r = asRational(sa) {
                if let n = asRational(inner2) {
                    return simplify(.mul(inner1, normalizeRational(n.0 * r.0, n.1 * r.1)))
                }
                if let n = asRational(inner1) {
                    return simplify(.mul(inner2, normalizeRational(n.0 * r.0, n.1 * r.1)))
                }
            }
        }

        // Associativity: n * (m * x) = (n*m) * x
        if case .integer(let n) = sa, case .mul(let inner1, let inner2) = sb {
            if case .integer(let m) = inner1 {
                return simplify(.mul(.integer(n * m), inner2))
            }
            if case .integer(let m) = inner2 {
                return simplify(.mul(.integer(n * m), inner1))
            }
        }
        // Associativity: (n * x) * m = (n*m) * x
        if case .integer(let m) = sb, case .mul(let inner1, let inner2) = sa {
            if case .integer(let n) = inner1 {
                return simplify(.mul(.integer(n * m), inner2))
            }
            if case .integer(let n) = inner2 {
                return simplify(.mul(.integer(n * m), inner1))
            }
        }

        // Distribute: a * (b + c) = a*b + a*c
        if case .add(let b1, let b2) = sb {
            return simplify(.add(.mul(sa, b1), .mul(sa, b2)))
        }
        // Distribute: (a + b) * c = a*c + b*c
        if case .add(let a1, let a2) = sa {
            return simplify(.add(.mul(a1, sb), .mul(a2, sb)))
        }

        return .mul(sa, sb)

    // --- Power ---
    case .pow(let base, let exp):
        let sb = simplify(base)
        let se = simplify(exp)

        // x^0 = 1
        if se.isZero { return .integer(1) }
        // x^1 = x
        if se.isOne { return sb }
        // 0^n = 0 (for positive n)
        if sb.isZero { return .integer(0) }
        // 1^n = 1
        if sb.isOne { return .integer(1) }

        // n^m for integers
        if case .integer(let n) = sb, case .integer(let m) = se, m >= 0, m < 20 {
            var result = 1
            for _ in 0..<m { result *= n }
            return .integer(result)
        }

        // n^(1/2): sqrt of integers
        if case .integer(let n) = sb, case .rational(1, 2) = se {
            if n > 0 {
                // Perfect square: sqrt(16) = 4
                let root = Int(Foundation.sqrt(Double(n)).rounded())
                if root * root == n { return .integer(root) }
                // Factor out largest perfect square: sqrt(12) = 2*sqrt(3)
                let (outside, inside) = extractSquareFactor(n)
                if outside > 1 {
                    return simplify(.mul(.integer(outside), .pow(.integer(inside), .rational(1, 2))))
                }
            } else if n < 0 {
                // sqrt(-n) = i * sqrt(n)
                let absN = -n
                let inner = simplify(.pow(.integer(absN), .rational(1, 2)))
                return simplify(.mul(.constant(.i), inner))
            }
        }

        // (p/q)^(1/2): sqrt of rationals
        if case .rational(let p, let q) = sb, case .rational(1, 2) = se, p > 0, q > 0 {
            let numSimp = simplify(.pow(.integer(p), .rational(1, 2)))
            let denSimp = simplify(.pow(.integer(q), .rational(1, 2)))
            if numSimp != .pow(.integer(p), .rational(1, 2)) || denSimp != .pow(.integer(q), .rational(1, 2)) {
                return simplify(numSimp / denSimp)
            }
        }

        // n^(-1/2) for perfect squares
        if case .integer(let n) = sb, case .rational(-1, 2) = se, n > 0 {
            let root = Int(Foundation.sqrt(Double(n)).rounded())
            if root * root == n { return .rational(1, root) }
        }

        // i^2 = -1
        if case .constant(.i) = sb, case .integer(2) = se {
            return .integer(-1)
        }

        // Rational power: (p/q)^(-1) = q/p
        if let (p, q) = asRational(sb), case .integer(-1) = se {
            return normalizeRational(q, p)
        }

        // (x^a)^b = x^(a*b)
        if case .pow(let inner, let a) = sb {
            return simplify(.pow(inner, simplify(.mul(a, se))))
        }

        return .pow(sb, se)

    // --- Functions ---
    case .function(let name, let args):
        let sargs = args.map { simplify($0) }

        // sin(0) = 0, cos(0) = 1, etc.
        if sargs.count == 1, let val = sargs[0].numericValue {
            if let result = evalConstantFunction(name, val) {
                return result
            }
        }

        // log(e) = 1
        if name == "log", sargs.count == 1, case .constant(.e) = sargs[0] {
            return .integer(1)
        }

        // exp(log(x)) = x
        if name == "exp", sargs.count == 1, case .function("log", let inner) = sargs[0] {
            return inner[0]
        }
        // log(exp(x)) = x
        if name == "log", sargs.count == 1, case .function("exp", let inner) = sargs[0] {
            return inner[0]
        }

        // sin(pi) = 0, cos(pi) = -1
        if name == "sin", sargs.count == 1, case .constant(.pi) = sargs[0] {
            return .integer(0)
        }
        if name == "cos", sargs.count == 1, case .constant(.pi) = sargs[0] {
            return .integer(-1)
        }

        return .function(name, sargs)

    case .matrix(let m):
        let newElements = m.elements.map { row in row.map { simplify($0) } }
        return .matrix(Matrix(newElements))
    }
}

// MARK: - Helpers

extension Expr {
    public func simplified() -> Expr {
        return simplify(self)
    }
}

private func splitCoefficient(_ expr: Expr) -> (Int, Expr) {
    if case .integer(let n) = expr {
        return (n, .integer(1))
    }
    if case .mul(.integer(let c), let rest) = expr {
        return (c, rest)
    }
    if case .mul(let rest, .integer(let c)) = expr {
        return (c, rest)
    }
    return (1, expr)
}

private func splitPower(_ expr: Expr) -> (Expr, Expr) {
    if case .pow(let base, let exp) = expr {
        return (base, exp)
    }
    // Treat 1/n as n^(-1) for base-matching purposes
    if case .rational(1, let q) = expr, q > 1 {
        return (.integer(q), .integer(-1))
    }
    return (expr, .integer(1))
}

private func asRational(_ expr: Expr) -> (Int, Int)? {
    switch expr {
    case .integer(let n): return (n, 1)
    case .rational(let p, let q): return (p, q)
    default: return nil
    }
}

private func normalizeRational(_ p: Int, _ q: Int) -> Expr {
    guard q != 0 else { fatalError("Division by zero") }
    let g = gcd(Swift.abs(p), Swift.abs(q))
    let np = q < 0 ? -p / g : p / g
    let nq = Swift.abs(q) / g
    if nq == 1 { return .integer(np) }
    return .rational(np, nq)
}

/// Try to cancel a power factor against factors in a product.
/// E.g., pow(2,-1) against mul(i, 2) → i
private func flattenAndCancel(_ powExpr: Expr, _ mulExpr: Expr) -> Expr? {
    guard case .pow(let pBase, let pExp) = powExpr else { return nil }
    var factors: [Expr] = []
    flattenMulFactors(mulExpr, into: &factors)

    for (idx, f) in factors.enumerated() {
        let (fBase, fExp) = splitPower(f)
        if fBase == pBase {
            let newExp = simplify(.add(fExp, pExp))
            var remaining = factors
            remaining.remove(at: idx)
            let cancelledFactor = newExp.isZero ? Expr.integer(1) : simplify(.pow(fBase, newExp))
            remaining.append(cancelledFactor)
            let result = remaining.reduce(nil as Expr?) { acc, f in
                if let a = acc { return .mul(a, f) }
                return f
            }
            return result.map { simplify($0) }
        }
    }
    return nil
}

private func flattenMulFactors(_ expr: Expr, into factors: inout [Expr]) {
    if case .mul(let a, let b) = expr {
        flattenMulFactors(a, into: &factors)
        flattenMulFactors(b, into: &factors)
    } else {
        factors.append(expr)
    }
}

/// Factor n = outside² * inside, returning (outside, inside)
private func extractSquareFactor(_ n: Int) -> (Int, Int) {
    var outside = 1
    var inside = n
    var f = 2
    while f * f <= inside {
        while inside % (f * f) == 0 {
            outside *= f
            inside /= (f * f)
        }
        f += 1
    }
    return (outside, inside)
}

private func gcd(_ a: Int, _ b: Int) -> Int {
    var a = a, b = b
    while b != 0 { (a, b) = (b, a % b) }
    return a
}

private func collectAddTerms(_ expr: Expr) -> [Expr] {
    if case .add(let a, let b) = expr {
        return collectAddTerms(a) + collectAddTerms(b)
    }
    return [expr]
}

private func collectLikeTerms(_ terms: [Expr]) -> [Expr] {
    var buckets: [(Expr, Int)] = []  // (base_term, total_coefficient)
    for term in terms {
        let (c, t) = splitCoefficient(term)
        if let idx = buckets.firstIndex(where: { $0.0 == t }) {
            buckets[idx].1 += c
        } else {
            buckets.append((t, c))
        }
    }
    return buckets.compactMap { (t, c) in
        if c == 0 { return nil }
        if t == .integer(1) { return .integer(c) }
        if c == 1 { return t }
        return Expr.mul(.integer(c), t)
    }
}

private func evalConstantFunction(_ name: String, _ val: Double) -> Expr? {
    if val == 0 {
        switch name {
        case "sin", "tan", "sinh", "tanh", "asin", "atan": return .integer(0)
        case "cos", "cosh": return .integer(1)
        case "exp": return .integer(1)
        default: break
        }
    }
    return nil
}
