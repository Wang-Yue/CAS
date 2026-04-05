import Foundation

// MARK: - Probability Distributions

public enum Distribution {
    case normal(mean: Expr, variance: Expr)
    case uniform(a: Expr, b: Expr)
    case exponential(lambda: Expr)
    case binomial(n: Expr, p: Expr)
    case poisson(lambda: Expr)
    case bernoulli(p: Expr)
    case geometric(p: Expr)
}

extension Distribution {

    // MARK: Expected Value

    public var expectedValue: Expr {
        switch self {
        case .normal(let mu, _): return mu
        case .uniform(let a, let b): return simplify((a + b) / 2)
        case .exponential(let lam): return simplify(.integer(1) / lam)
        case .binomial(let n, let p): return simplify(n * p)
        case .poisson(let lam): return lam
        case .bernoulli(let p): return p
        case .geometric(let p): return simplify(.integer(1) / p)
        }
    }

    // MARK: Variance

    public var variance: Expr {
        switch self {
        case .normal(_, let sigma2): return sigma2
        case .uniform(let a, let b): return simplify((b - a) ** 2 / 12)
        case .exponential(let lam): return simplify(.integer(1) / (lam ** 2))
        case .binomial(let n, let p): return simplify(n * p * (.integer(1) - p))
        case .poisson(let lam): return lam
        case .bernoulli(let p): return simplify(p * (.integer(1) - p))
        case .geometric(let p): return simplify((.integer(1) - p) / (p ** 2))
        }
    }

    // MARK: Standard Deviation

    public var standardDeviation: Expr {
        CAS.sqrt(variance)
    }

    // MARK: Moment Generating Function M(t)

    public func mgf(_ t: Expr) -> Expr {
        switch self {
        case .normal(let mu, let sigma2):
            return CAS.exp(mu * t + sigma2 * (t ** 2) / 2)
        case .exponential(let lam):
            return simplify(lam / (lam - t))
        case .binomial(let n, let p):
            return simplify((.integer(1) - p + p * CAS.exp(t)) ** n)
        case .poisson(let lam):
            return CAS.exp(lam * (CAS.exp(t) - 1))
        case .bernoulli(let p):
            return simplify(.integer(1) - p + p * CAS.exp(t))
        case .uniform(let a, let b):
            return simplify((CAS.exp(t * b) - CAS.exp(t * a)) / (t * (b - a)))
        case .geometric(let p):
            return simplify(p * CAS.exp(t) / (.integer(1) - (.integer(1) - p) * CAS.exp(t)))
        }
    }

    // MARK: PDF / PMF as symbolic expression

    public func pdf(_ x: Expr) -> Expr {
        switch self {
        case .normal(let mu, let sigma2):
            let coeff = .integer(1) / CAS.sqrt(.integer(2) * pi * sigma2)
            let exponent = Expr.mul(.integer(-1), (x - mu) ** 2 / (.integer(2) * sigma2))
            return simplify(coeff * CAS.exp(exponent))

        case .uniform(let a, let b):
            return simplify(.integer(1) / (b - a))

        case .exponential(let lam):
            return simplify(lam * CAS.exp(.mul(.integer(-1), lam * x)))

        case .binomial(let n, let p):
            // C(n,k) * p^k * (1-p)^(n-k)
            let q: Expr = .integer(1) - p
            return simplify(
                .function("binomial", [n, x]) * (p ** x) * (q ** (n - x))
            )

        case .poisson(let lam):
            // lambda^k * e^(-lambda) / k!
            return simplify(
                (lam ** x) * CAS.exp(-lam) / factorial(x)
            )

        case .bernoulli(let p):
            // p^x * (1-p)^(1-x)
            return simplify((p ** x) * ((.integer(1) - p) ** (.integer(1) - x)))

        case .geometric(let p):
            return simplify(p * ((.integer(1) - p) ** (x - 1)))
        }
    }
}

// MARK: - Combinatorics

public func nCr(_ n: Expr, _ k: Expr) -> Expr {
    .function("binomial", [n, k])
}

public func nPr(_ n: Expr, _ k: Expr) -> Expr {
    factorial(n) / factorial(n - k)
}

// MARK: - Conditional Probability Helpers

public struct ProbabilitySpace {
    public var events: [String: Expr]

    public init(_ events: [String: Expr] = [:]) {
        self.events = events
    }

    public func P(_ event: String) -> Expr {
        guard let p = events[event] else {
            fatalError("Unknown event: \(event)")
        }
        return p
    }

    /// Bayes' theorem: P(A|B) = P(B|A) * P(A) / P(B)
    public func bayes(a: String, givenB b: String, pBgivenA: Expr) -> Expr {
        simplify(pBgivenA * P(a) / P(b))
    }
}
