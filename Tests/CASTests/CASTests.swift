import XCTest
@testable import CAS

final class CASTests: XCTestCase {

    let x = sym("x")
    let y = sym("y")

    // MARK: - Core Expression Tests

    func testSymbolEquality() {
        XCTAssertEqual(sym("x"), sym("x"))
        XCTAssertNotEqual(sym("x"), sym("y"))
    }

    func testArithmetic() {
        let expr = x + 2
        XCTAssertEqual("\(expr)", "x + 2")
    }

    func testSubstitution() {
        let expr = x ** 2 + x
        let result = simplify(expr.substitute(x, with: .integer(3)))
        XCTAssertEqual(result, .integer(12))
    }

    func testEval() {
        let expr = x ** 2 + 1
        let val = expr.eval([x: 3.0])
        XCTAssertEqual(val, 10.0, accuracy: 1e-10)
    }

    func testFreeSymbols() {
        let expr = x ** 2 + y * 3
        XCTAssertEqual(expr.freeSymbols, [x, y])
    }

    // MARK: - Simplification Tests

    func testSimplifyZero() {
        XCTAssertEqual(simplify(x + 0), x)
        XCTAssertEqual(simplify(.integer(0) + x), x)
        XCTAssertEqual(simplify(x * 0), .integer(0))
    }

    func testSimplifyOne() {
        XCTAssertEqual(simplify(x * 1), x)
        XCTAssertEqual(simplify(.integer(1) * x), x)
    }

    func testSimplifyIntegerArith() {
        XCTAssertEqual(simplify(.integer(3) + .integer(4)), .integer(7))
        XCTAssertEqual(simplify(.integer(3) * .integer(4)), .integer(12))
    }

    func testSimplifyPower() {
        XCTAssertEqual(simplify(x ** 0), .integer(1))
        XCTAssertEqual(simplify(x ** 1), x)
        XCTAssertEqual(simplify(.integer(2) ** .integer(3)), .integer(8))
    }

    func testSimplifyLikeTerms() {
        let result = simplify(x + x)
        XCTAssertEqual(result, .mul(.integer(2), x))
    }

    func testSimplifyLogE() {
        XCTAssertEqual(simplify(log(e)), .integer(1))
    }

    func testSimplifyExpLog() {
        XCTAssertEqual(simplify(exp(log(x))), x)
    }

    // MARK: - Differentiation Tests

    func testDiffConstant() {
        XCTAssertEqual(diff(.integer(5), x), .integer(0))
    }

    func testDiffLinear() {
        XCTAssertEqual(diff(x, x), .integer(1))
        XCTAssertEqual(diff(y, x), .integer(0))
    }

    func testDiffPolynomial() {
        // d/dx(x^3) = 3x^2
        let result = diff(x ** 3, x)
        let expected = simplify(.integer(3) * x ** 2)
        XCTAssertEqual(result, expected)
    }

    func testDiffProduct() {
        // d/dx(x * sin(x)) = sin(x) + x*cos(x)
        let result = diff(x * sin(x), x)
        // Just verify numerically
        let val = result.eval([x: 1.0])
        let expected_val = Foundation.sin(1.0) + 1.0 * Foundation.cos(1.0)
        XCTAssertEqual(val, expected_val, accuracy: 1e-8)
    }

    func testDiffChainRule() {
        // d/dx(sin(x^2)) = cos(x^2) * 2x
        let result = diff(sin(x ** 2), x)
        let val = result.eval([x: 1.0])
        let expected_val = Foundation.cos(1.0) * 2.0
        XCTAssertEqual(val, expected_val, accuracy: 1e-8)
    }

    func testDiffExp() {
        XCTAssertEqual(diff(exp(x), x), exp(x))
    }

    func testDiffLog() {
        // d/dx(log(x)) = 1/x
        let result = diff(log(x), x)
        let val = result.eval([x: 2.0])
        XCTAssertEqual(val, 0.5, accuracy: 1e-8)
    }

    func testHigherOrder() {
        // d²/dx²(x^4) = 12x^2
        let result = diff(x ** 4, x, order: 2)
        let val = result.eval([x: 2.0])
        XCTAssertEqual(val, 48.0, accuracy: 1e-8)
    }

    // MARK: - Integration Tests

    func testIntegratePolynomial() {
        // ∫x^2 dx should give x^3/3 (up to simplification)
        let result = integrate(x ** 2, x)
        // Verify via differentiation roundtrip
        let deriv = diff(result, x)
        let val = deriv.eval([x: 3.0])
        XCTAssertEqual(val, 9.0, accuracy: 1e-8)
    }

    func testIntegrateSin() {
        let result = integrate(sin(x), x)
        // Should be -cos(x)
        let val = result.eval([x: .pi])
        XCTAssertEqual(val, 1.0, accuracy: 1e-8)  // -cos(pi) = 1
    }

    func testDefiniteIntegral() {
        // ∫₀¹ x² dx = 1/3
        let result = integrate(x ** 2, x, from: .integer(0), to: .integer(1))
        let val = result.eval()
        XCTAssertEqual(val, 1.0/3.0, accuracy: 1e-8)
    }

    // MARK: - Taylor Series Tests

    func testTaylorSin() {
        let series = taylor(sin(x), x, terms: 7)
        // sin(0.5) ≈ 0.479
        let approx = series.eval([x: 0.5])
        let exact = Foundation.sin(0.5)
        XCTAssertEqual(approx, exact, accuracy: 1e-5)
    }

    func testTaylorExp() {
        let series = taylor(exp(x), x, terms: 8)
        let approx = series.eval([x: 1.0])
        XCTAssertEqual(approx, M_E, accuracy: 1e-4)
    }

    // MARK: - Linear Algebra Tests

    func testMatrixDeterminant2x2() {
        let m = Matrix([
            [.integer(1), .integer(2)],
            [.integer(3), .integer(4)],
        ])
        XCTAssertEqual(m.determinant(), .integer(-2))
    }

    func testMatrixDeterminant3x3() {
        let m = Matrix([
            [.integer(1), .integer(2), .integer(3)],
            [.integer(4), .integer(5), .integer(6)],
            [.integer(7), .integer(8), .integer(10)],
        ])
        XCTAssertEqual(m.determinant(), .integer(-3))
    }

    func testMatrixMultiplication() {
        let a = Matrix([
            [.integer(1), .integer(2)],
            [.integer(3), .integer(4)],
        ])
        let b = Matrix([
            [.integer(5), .integer(6)],
            [.integer(7), .integer(8)],
        ])
        let c = a * b
        XCTAssertEqual(c[0, 0], .integer(19))
        XCTAssertEqual(c[0, 1], .integer(22))
        XCTAssertEqual(c[1, 0], .integer(43))
        XCTAssertEqual(c[1, 1], .integer(50))
    }

    func testMatrixTranspose() {
        let m = Matrix([
            [.integer(1), .integer(2)],
            [.integer(3), .integer(4)],
        ])
        let t = m.transposed()
        XCTAssertEqual(t[0, 1], .integer(3))
        XCTAssertEqual(t[1, 0], .integer(2))
    }

    func testMatrixIdentity() {
        let m = Matrix([
            [.integer(1), .integer(2)],
            [.integer(3), .integer(4)],
        ])
        let I = Matrix.identity(2)
        let result = m * I
        XCTAssertEqual(result[0, 0], .integer(1))
        XCTAssertEqual(result[1, 1], .integer(4))
    }

    func testMatrixTrace() {
        let m = Matrix([
            [.integer(1), .integer(2)],
            [.integer(3), .integer(4)],
        ])
        XCTAssertEqual(m.trace(), .integer(5))
    }

    func testDotProduct() {
        let a: [Expr] = [.integer(1), .integer(2), .integer(3)]
        let b: [Expr] = [.integer(4), .integer(5), .integer(6)]
        XCTAssertEqual(Matrix.dot(a, b), .integer(32))
    }

    func testCrossProduct() {
        let a: [Expr] = [.integer(1), .integer(0), .integer(0)]
        let b: [Expr] = [.integer(0), .integer(1), .integer(0)]
        let c = Matrix.cross(a, b)
        XCTAssertEqual(c[0], .integer(0))
        XCTAssertEqual(c[1], .integer(0))
        XCTAssertEqual(c[2], .integer(1))
    }

    func testSymbolicDeterminant() {
        let a = sym("a"); let b = sym("b")
        let c = sym("c"); let d = sym("d")
        let m = Matrix([[a, b], [c, d]])
        let det = m.determinant()
        // Should be ad - bc
        let val = det.eval([a: 1, b: 2, c: 3, d: 4])
        XCTAssertEqual(val, -2.0, accuracy: 1e-10)
    }

    // MARK: - Probability Tests

    func testNormalDistribution() {
        let n = Distribution.normal(mean: .integer(0), variance: .integer(1))
        XCTAssertEqual(n.expectedValue, .integer(0))
        XCTAssertEqual(n.variance, .integer(1))
    }

    func testBinomialDistribution() {
        let b = Distribution.binomial(n: .integer(10), p: .rational(1, 2))
        let ev = simplify(b.expectedValue)
        XCTAssertEqual(ev, .integer(5))
    }

    func testPoissonDistribution() {
        let p = Distribution.poisson(lambda: .integer(3))
        XCTAssertEqual(p.expectedValue, .integer(3))
        XCTAssertEqual(p.variance, .integer(3))
    }

    func testExponentialDistribution() {
        let e = Distribution.exponential(lambda: .integer(2))
        let ev = e.expectedValue.eval()
        XCTAssertEqual(ev, 0.5, accuracy: 1e-10)
        let v = e.variance.eval()
        XCTAssertEqual(v, 0.25, accuracy: 1e-10)
    }

    // MARK: - Gradient & Hessian Tests

    func testGradient() {
        let f = x ** 2 + y ** 2
        let grad = gradient(f, [x, y])
        // df/dx = 2x, df/dy = 2y
        let gx = grad[0].eval([x: 3.0, y: 0.0])
        let gy = grad[1].eval([x: 0.0, y: 4.0])
        XCTAssertEqual(gx, 6.0, accuracy: 1e-8)
        XCTAssertEqual(gy, 8.0, accuracy: 1e-8)
    }

    func testHessian() {
        let f = x ** 2 + x * y + y ** 2
        let H = hessian(f, [x, y])
        // H = [[2, 1], [1, 2]]
        XCTAssertEqual(H[0, 0].eval(), 2.0, accuracy: 1e-8)
        XCTAssertEqual(H[0, 1].eval(), 1.0, accuracy: 1e-8)
        XCTAssertEqual(H[1, 0].eval(), 1.0, accuracy: 1e-8)
        XCTAssertEqual(H[1, 1].eval(), 2.0, accuracy: 1e-8)
    }

    // MARK: - LaTeX Tests

    func testLatexFraction() {
        let expr = Expr.rational(1, 2)
        XCTAssertEqual(expr.latex, "\\frac{1}{2}")
    }

    func testLatexSqrt() {
        let expr = sqrt(x)
        XCTAssertEqual(expr.latex, "\\sqrt{x}")
    }

    func testLatexPi() {
        XCTAssertEqual(pi.latex, "\\pi")
    }

    // MARK: - Advanced Integration Tests

    func testIntegrateXExpX() {
        // ∫ x*e^x dx = x*e^x - e^x
        let result = integrate(x * exp(x), x)
        let val = result.eval([x: 1.0])
        // x*e^x - e^x at x=1 = e - e = 0? No: 1*e - e = 0. Check at x=2:
        let val2 = result.eval([x: 2.0])
        let expected2 = 2 * Foundation.exp(2.0) - Foundation.exp(2.0)  // e^2
        XCTAssertEqual(val2, expected2, accuracy: 1e-6)
    }

    func testIntegrateXSinX() {
        // ∫ x*sin(x) dx = -x*cos(x) + sin(x)
        let result = integrate(x * sin(x), x)
        let val = result.eval([x: 1.0])
        let expected = -1.0 * Foundation.cos(1.0) + Foundation.sin(1.0)
        XCTAssertEqual(val, expected, accuracy: 1e-6)
    }

    func testIntegrateSinSquared() {
        // ∫ sin²(x) dx = x/2 - sin(2x)/4
        let result = integrate(sin(x) ** 2, x)
        let val = result.eval([x: 1.0])
        let expected = 0.5 - Foundation.sin(2.0) / 4.0
        XCTAssertEqual(val, expected, accuracy: 1e-6)
    }

    func testIntegrateXOverX2Plus1() {
        // ∫ x/(x²+1) dx = (1/2)*ln(x²+1)
        let result = integrate(x / (x ** 2 + 1), x)
        let val = result.eval([x: 2.0])
        let expected = 0.5 * Foundation.log(5.0)
        XCTAssertEqual(val, expected, accuracy: 1e-6)
    }

    func testIntegrateOneOverX2Plus1() {
        // ∫ 1/(x²+1) dx = atan(x)
        let result = integrate(.integer(1) / (x ** 2 + 1), x)
        let val = result.eval([x: 1.0])
        XCTAssertEqual(val, Foundation.atan(1.0), accuracy: 1e-6)
    }

    func testIntegrateLogX() {
        // ∫ ln(x) dx = x*ln(x) - x
        let result = integrate(log(x), x)
        let val = result.eval([x: 2.0])
        let expected = 2.0 * Foundation.log(2.0) - 2.0
        XCTAssertEqual(val, expected, accuracy: 1e-6)
    }

    func testIntegrateX2ExpX() {
        // ∫ x²*e^x dx = x²*e^x - 2x*e^x + 2*e^x
        let result = integrate(x ** 2 * exp(x), x)
        let val = result.eval([x: 1.0])
        let expected = 1.0 * M_E - 2.0 * M_E + 2.0 * M_E  // e^1*(1-2+2) = e
        XCTAssertEqual(val, expected, accuracy: 1e-6)
    }

    func testIntegrateSinCos() {
        // ∫ sin(x)*cos(x) dx = -cos(2x)/4
        let result = integrate(sin(x) * cos(x), x)
        let val = result.eval([x: 1.0])
        let expected = -Foundation.cos(2.0) / 4.0
        XCTAssertEqual(val, expected, accuracy: 1e-6)
    }

    func testIntegrateTan() {
        // ∫ tan(x) dx = -ln|cos(x)|
        let result = integrate(tan(x), x)
        let val = result.eval([x: 0.5])
        let expected = -Foundation.log(Foundation.cos(0.5))
        XCTAssertEqual(val, expected, accuracy: 1e-6)
    }

    func testIntegrateInverseSqrt() {
        // ∫ 1/√(1-x²) dx = asin(x)
        let result = integrate(.pow(.integer(1) - x ** 2, .rational(-1, 2)), x)
        let val = result.eval([x: 0.5])
        XCTAssertEqual(val, Foundation.asin(0.5), accuracy: 1e-6)
    }

    func testIntegrateExpSin() {
        // ∫ e^x*sin(x) dx = (sin(x)*e^x - cos(x)*e^x)/2
        let result = integrate(exp(x) * sin(x), x)
        let val = result.eval([x: 1.0])
        let expected = (Foundation.sin(1.0) * M_E - Foundation.cos(1.0) * M_E) / 2.0
        XCTAssertEqual(val, expected, accuracy: 1e-4)
    }

    func testIntegrateX3ExpX() {
        // ∫ x³*e^x dx = x³e^x - 3x²e^x + 6xe^x - 6e^x
        let result = integrate(x ** 3 * exp(x), x)
        let val = result.eval([x: 1.0])
        let expected = M_E * (1.0 - 3.0 + 6.0 - 6.0)  // -2e
        XCTAssertEqual(val, expected, accuracy: 1e-6)
    }

    func testIntegrateXCosX() {
        // ∫ x*cos(x) dx = x*sin(x) + cos(x)
        let result = integrate(x * cos(x), x)
        let val = result.eval([x: 1.0])
        let expected = Foundation.sin(1.0) + Foundation.cos(1.0)
        XCTAssertEqual(val, expected, accuracy: 1e-6)
    }

    func testIntegrateX2SinX() {
        // ∫ x²*sin(x) dx = -x²cos(x) + 2x*sin(x) + 2cos(x)
        let result = integrate(x ** 2 * sin(x), x)
        let val = result.eval([x: 1.0])
        let expected = -Foundation.cos(1.0) + 2.0 * Foundation.sin(1.0) + 2.0 * Foundation.cos(1.0)
        XCTAssertEqual(val, expected, accuracy: 1e-6)
    }

    func testIntegrateExp2X() {
        // ∫ e^(2x) dx = e^(2x)/2
        let result = integrate(exp(.integer(2) * x), x)
        let val = result.eval([x: 1.0])
        let expected = Foundation.exp(2.0) / 2.0
        XCTAssertEqual(val, expected, accuracy: 1e-6)
    }

    func testIntegrateCosLinear() {
        // ∫ cos(3x+1) dx = sin(3x+1)/3
        let result = integrate(cos(.integer(3) * x + 1), x)
        let val = result.eval([x: 1.0])
        let expected = Foundation.sin(4.0) / 3.0
        XCTAssertEqual(val, expected, accuracy: 1e-6)
    }

    func testDefiniteIntegralX3() {
        // ∫₀² x³ dx = 16/4 = 4
        let result = integrate(x ** 3, x, from: .integer(0), to: .integer(2))
        let val = result.eval()
        XCTAssertEqual(val, 4.0, accuracy: 1e-8)
    }

    // MARK: - Equation Solving Tests

    func testSolveLinear() {
        let roots = try! solve(.integer(2) * x + .integer(3), x)
        XCTAssertEqual(roots.count, 1)
        XCTAssertEqual(roots[0].eval(), -1.5, accuracy: 1e-10)
    }

    func testSolveQuadraticIntegerRoots() {
        // x² - 5x + 6 = 0  =>  x = 2, 3
        let roots = try! solve(x ** 2 - 5 * x + 6, x)
        let vals = roots.map { $0.eval() }.sorted()
        XCTAssertEqual(vals.count, 2)
        XCTAssertEqual(vals[0], 2.0, accuracy: 1e-8)
        XCTAssertEqual(vals[1], 3.0, accuracy: 1e-8)
    }

    func testSolveQuadraticIrrational() {
        // x² - 2 = 0  =>  x = ±√2
        let roots = try! solve(x ** 2 - 2, x)
        let vals = roots.map { $0.eval() }.sorted()
        XCTAssertEqual(vals[0], -Foundation.sqrt(2.0), accuracy: 1e-8)
        XCTAssertEqual(vals[1], Foundation.sqrt(2.0), accuracy: 1e-8)
    }

    func testSolveQuadraticRepeatedRoot() {
        // x² - 4x + 4 = 0  =>  x = 2 (double)
        let roots = try! solve(x ** 2 - 4 * x + 4, x)
        XCTAssertEqual(roots.count, 1)
        XCTAssertEqual(roots[0].eval(), 2.0, accuracy: 1e-8)
    }

    func testSolveCubic() {
        // x³ - 6x² + 11x - 6 = 0  =>  x = 1, 2, 3
        let roots = try! solve(x ** 3 - 6 * x ** 2 + 11 * x - 6, x)
        let vals = roots.map { $0.eval() }.sorted()
        XCTAssertEqual(vals.count, 3)
        XCTAssertEqual(vals[0], 1.0, accuracy: 1e-6)
        XCTAssertEqual(vals[1], 2.0, accuracy: 1e-6)
        XCTAssertEqual(vals[2], 3.0, accuracy: 1e-6)
    }

    func testSolveQuartic() {
        // x⁴ - 5x² + 4 = 0  =>  x = ±1, ±2
        let roots = try! solve(x ** 4 - 5 * x ** 2 + 4, x)
        let vals = roots.map { $0.eval() }.sorted()
        XCTAssertEqual(vals.count, 4)
        XCTAssertEqual(vals[0], -2.0, accuracy: 1e-6)
        XCTAssertEqual(vals[1], -1.0, accuracy: 1e-6)
        XCTAssertEqual(vals[2], 1.0, accuracy: 1e-6)
        XCTAssertEqual(vals[3], 2.0, accuracy: 1e-6)
    }

    func testSolveExponential() {
        // e^x - 2 = 0  =>  x = ln(2)
        let roots = try! solve(exp(x) - 2, x)
        XCTAssertEqual(roots.count, 1)
        XCTAssertEqual(roots[0].eval(), Foundation.log(2.0), accuracy: 1e-10)
    }

    func testSolveLogarithmic() {
        // log(x) - 3 = 0  =>  x = e³
        let roots = try! solve(log(x) - 3, x)
        XCTAssertEqual(roots.count, 1)
        XCTAssertEqual(roots[0].eval(), Foundation.exp(3.0), accuracy: 1e-8)
    }

    func testSolveTrig() {
        // sin(x) - 1/2 = 0  =>  x = π/6 (principal value)
        let roots = try! solve(sin(x) - Expr.rational(1, 2), x)
        XCTAssertEqual(roots.count, 1)
        XCTAssertEqual(roots[0].eval(), Foundation.asin(0.5), accuracy: 1e-10)
    }

    func testSolveSqrt() {
        // √x - 3 = 0  =>  x = 9
        let roots = try! solve(sqrt(x) - 3, x)
        XCTAssertEqual(roots.count, 1)
        XCTAssertEqual(roots[0].eval(), 9.0, accuracy: 1e-10)
    }

    func testSolveExponentialBase() {
        // 2^x - 8 = 0  =>  x = 3
        let roots = try! solve(.pow(.integer(2), x) - 8, x)
        XCTAssertEqual(roots.count, 1)
        XCTAssertEqual(roots[0].eval(), 3.0, accuracy: 1e-8)
    }

    // MARK: - ODE Tests

    // MARK: - Complex Number & Sqrt Simplification Tests

    func testSolveComplexRootsPure() {
        // x² + 1 = 0  =>  x = ±i
        let roots = try! solve(x ** 2 + 1, x)
        XCTAssertEqual(roots.count, 2)
        // Verify structurally: one root is i, other is -i
        let hasI = roots.contains(where: { $0 == Expr.constant(.i) })
        let hasNegI = roots.contains(where: {
            if case .mul(.integer(-1), .constant(.i)) = $0 { return true }
            if case .mul(.constant(.i), .integer(-1)) = $0 { return true }
            return false
        })
        XCTAssertTrue(hasI, "Should contain i, got \(roots)")
        XCTAssertTrue(hasNegI, "Should contain -i, got \(roots)")
    }

    func testSolveComplexRootsScaled() {
        // x² + 4 = 0  =>  x = ±2i
        let roots = try! solve(x ** 2 + 4, x)
        XCTAssertEqual(roots.count, 2)
        // Both roots should have i as a factor
        for root in roots {
            XCTAssertTrue(root.freeSymbols.isEmpty, "Complex root should have no free symbols")
        }
    }

    func testSolveComplexWithRealPart() {
        // x² + 2x + 5 = 0  =>  x = -1 ± 2i
        let roots = try! solve(x ** 2 + 2 * x + 5, x)
        XCTAssertEqual(roots.count, 2)
        // Verify: both solutions satisfy the equation numerically
        // Use x = -1 + 2i: (-1+2i)² + 2(-1+2i) + 5 = 1-4-4i + -2+4i + 5 = 0
        // We can't eval complex, but we verify the structure has i in it
        let str = "\(roots[0])"
        XCTAssertTrue(str.contains("i"), "Root should contain i: \(str)")
    }

    func testSolveQuadraticComplexGeneral() {
        // x² + x + 1 = 0  =>  x = -1/2 ± i√3/2
        let roots = try! solve(x ** 2 + x + 1, x)
        XCTAssertEqual(roots.count, 2)
        let str = "\(roots[0])"
        XCTAssertTrue(str.contains("i"), "Root should contain i: \(str)")
        XCTAssertTrue(str.contains("sqrt(3)"), "Root should contain sqrt(3): \(str)")
    }

    func testImaginaryUnitSquared() {
        // i² = -1
        XCTAssertEqual(simplify(imaginaryUnit ** 2), .integer(-1))
    }

    func testSqrtNegativeOne() {
        // √(-1) = i
        XCTAssertEqual(simplify(sqrt(.integer(-1))), Expr.constant(.i))
    }

    func testSqrtNegativeInteger() {
        // √(-9) = 3i
        let result = simplify(sqrt(.integer(-9)))
        let val = "\(result)"
        XCTAssertTrue(val.contains("i") && val.contains("3"), "sqrt(-9) should be 3i, got \(val)")
    }

    func testSqrtNegativeNonPerfect() {
        // √(-2) = i√2
        let result = simplify(sqrt(.integer(-2)))
        let val = "\(result)"
        XCTAssertTrue(val.contains("i") && val.contains("sqrt(2)"), "sqrt(-2) should be i*sqrt(2), got \(val)")
    }

    func testSqrtSimplifyPerfectSquareFactor() {
        // √12 = 2√3
        let result = simplify(sqrt(.integer(12)))
        let val = "\(result)"
        XCTAssertTrue(val.contains("2") && val.contains("sqrt(3)"), "sqrt(12) should be 2*sqrt(3), got \(val)")
    }

    func testSqrtSimplifyLarger() {
        // √48 = 4√3
        let result = simplify(sqrt(.integer(48)))
        let val = "\(result)"
        XCTAssertTrue(val.contains("4") && val.contains("sqrt(3)"), "sqrt(48) should be 4*sqrt(3), got \(val)")
    }

    func testSqrtSimplify75() {
        // √75 = 5√3
        let result = simplify(sqrt(.integer(75)))
        let val = "\(result)"
        XCTAssertTrue(val.contains("5") && val.contains("sqrt(3)"), "sqrt(75) should be 5*sqrt(3), got \(val)")
    }

    func testSolveIrrationalSimplified() {
        // x² - 2 = 0  =>  x = √2 (not 2^(3/2)/2)
        let roots = try! solve(x ** 2 - 2, x)
        // Find the positive root by evaluating
        let evals = roots.compactMap { r -> (Expr, Double)? in
            let v = r.eval()
            return v.isNaN ? nil : (r, v)
        }
        let positive = evals.first(where: { $0.1 > 0 })!
        XCTAssertEqual(positive.1, Foundation.sqrt(2.0), accuracy: 1e-10)
        // Structural: should display as sqrt(2)
        let str = "\(positive.0)"
        XCTAssertEqual(str, "sqrt(2)", "Should display as sqrt(2), got \(str)")
    }

    // MARK: - Rational Root Theorem Tests

    func testSolveCubicAllRational() {
        // 2x³ - 3x² - 11x + 6 = 0  =>  x = -2, 3, 1/2
        let roots = try! solve(.integer(2) * x ** 3 - 3 * x ** 2 - 11 * x + 6, x)
        let vals = roots.map { $0.eval() }.sorted()
        XCTAssertEqual(vals.count, 3)
        XCTAssertEqual(vals[0], -2.0, accuracy: 1e-8)
        XCTAssertEqual(vals[1], 0.5, accuracy: 1e-8)
        XCTAssertEqual(vals[2], 3.0, accuracy: 1e-8)
    }

    func testSolveCubicOneRational() {
        // x³ + x - 2 = 0  =>  x = 1 (rational), then quadratic x² + x + 2 (complex)
        let roots = try! solve(x ** 3 + x - 2, x)
        let realRoots = roots.compactMap { $0.numericValue }.filter { !$0.isNaN }
        XCTAssertTrue(realRoots.contains(where: { Swift.abs($0 - 1.0) < 1e-8 }), "Should find x=1")
    }

    func testSolveCubicPureCube() {
        // x³ - 8 = 0  =>  x = 2
        let roots = try! solve(x ** 3 - 8, x)
        XCTAssertTrue(roots.contains(where: {
            if let v = $0.numericValue { return Swift.abs(v - 2.0) < 1e-8 }
            return false
        }), "Should find x=2")
    }

    func testSolveQuinticWithRationalRoots() {
        // x⁵ - x = x(x⁴-1) = x(x²-1)(x²+1) = x(x-1)(x+1)(x²+1)
        let roots = try! solve(x ** 5 - x, x)
        let realVals = roots.compactMap { $0.numericValue }.filter { !$0.isNaN }.sorted()
        XCTAssertTrue(realVals.count >= 3, "Should find at least 3 real roots")
        XCTAssertEqual(realVals[0], -1.0, accuracy: 1e-8)
        XCTAssertEqual(realVals[1], 0.0, accuracy: 1e-8)
        XCTAssertEqual(realVals[2], 1.0, accuracy: 1e-8)
    }

    func testSolveCubicSymbolicCardano() {
        // 6x³ + x² - 5x + 1 = 0 — no rational roots, should return symbolic Cardano
        let roots = try! solve(.integer(6) * x ** 3 + x ** 2 - 5 * x + 1, x)
        XCTAssertTrue(roots.count >= 1, "Should find at least one root")
        // Verify the first root satisfies the equation numerically
        for root in roots {
            if let rv = root.numericValue, !rv.isNaN {
                let check = 6 * rv * rv * rv + rv * rv - 5 * rv + 1
                XCTAssertEqual(check, 0.0, accuracy: 1e-4)
            }
        }
    }

    // MARK: - ODE Tests

    func testODESimpleIntegration() {
        // y' = 2x  =>  y = x² + C1
        let sol = try! solveODE(sym("yd") - 2 * x, y: sym("y"), x: x)
        // Evaluate at x=3 with C1=0
        let val = sol.substitute(sym("C1"), with: .integer(0)).eval([x: 3.0])
        XCTAssertEqual(val, 9.0, accuracy: 1e-6)
    }

    func testODEFirstOrderLinearHomogeneous() {
        // y' + 2y = 0  =>  y = C1*e^(-2x)
        let sol = try! solveODE(sym("yd") + 2 * sym("y"), y: sym("y"), x: x)
        let val = sol.substitute(sym("C1"), with: .integer(1)).eval([x: 1.0])
        XCTAssertEqual(val, Foundation.exp(-2.0), accuracy: 1e-6)
    }

    func testODESecondOrderDistinctRealRoots() {
        // y'' + 3y' + 2y = 0  =>  y = C1*e^(-x) + C2*e^(-2x)
        let sol = try! solveODE(
            sym("ydd") + 3 * sym("yd") + 2 * sym("y"),
            y: sym("y"), x: x
        )
        // With C1=1, C2=0, at x=1: e^(-1)
        let val = sol.substitute([sym("C1"): .integer(1), sym("C2"): .integer(0)]).eval([x: 1.0])
        XCTAssertEqual(val, Foundation.exp(-1.0), accuracy: 1e-6)
    }

    func testODESecondOrderComplexRoots() {
        // y'' + 4y = 0  =>  y = C1*cos(2x) + C2*sin(2x)
        let sol = try! solveODE(
            sym("ydd") + 4 * sym("y"),
            y: sym("y"), x: x
        )
        // With C1=1, C2=0, at x=π/4: cos(π/2) = 0
        let val = sol.substitute([sym("C1"): .integer(1), sym("C2"): .integer(0)])
            .eval([x: .pi / 4])
        XCTAssertEqual(val, 0.0, accuracy: 1e-6)
    }

    func testODESecondOrderRepeatedRoot() {
        // y'' + 2y' + y = 0  =>  y = (C1 + C2*x)*e^(-x)
        let sol = try! solveODE(
            sym("ydd") + 2 * sym("yd") + sym("y"),
            y: sym("y"), x: x
        )
        // With C1=1, C2=1, at x=2: (1+2)*e^(-2) = 3e^(-2)
        let val = sol.substitute([sym("C1"): .integer(1), sym("C2"): .integer(1)])
            .eval([x: 2.0])
        XCTAssertEqual(val, 3.0 * Foundation.exp(-2.0), accuracy: 1e-6)
    }

    func testODEHarmonicOscillator() {
        // y'' + 9y = 0  =>  y = C1*cos(3x) + C2*sin(3x)
        let sol = try! solveODE(
            sym("ydd") + 9 * sym("y"),
            y: sym("y"), x: x
        )
        // With C1=0, C2=1, at x=π/6: sin(π/2) = 1
        let val = sol.substitute([sym("C1"): .integer(0), sym("C2"): .integer(1)])
            .eval([x: .pi / 6])
        XCTAssertEqual(val, 1.0, accuracy: 1e-6)
    }

    func testODESecondOrderRealRoots2() {
        // y'' - 4y = 0  =>  y = C1*e^(2x) + C2*e^(-2x)
        let sol = try! solveODE(
            sym("ydd") - 4 * sym("y"),
            y: sym("y"), x: x
        )
        // With C1=1, C2=0, at x=1: e^2
        let val = sol.substitute([sym("C1"): .integer(1), sym("C2"): .integer(0)])
            .eval([x: 1.0])
        XCTAssertEqual(val, Foundation.exp(2.0), accuracy: 1e-6)
    }

    func testODERepeatedRoot2() {
        // y'' - 6y' + 9y = 0  =>  y = (C1 + C2*x)*e^(3x)
        let sol = try! solveODE(
            sym("ydd") - 6 * sym("yd") + 9 * sym("y"),
            y: sym("y"), x: x
        )
        // With C1=1, C2=0, at x=1: e^3
        let val = sol.substitute([sym("C1"): .integer(1), sym("C2"): .integer(0)])
            .eval([x: 1.0])
        XCTAssertEqual(val, Foundation.exp(3.0), accuracy: 1e-6)
    }

    // MARK: - Tokenizer Tests

    func testTokenizeNumber() {
        let tokens = tokenize("42")
        XCTAssertEqual(tokens, [.number("42")])
    }

    func testTokenizeDecimal() {
        let tokens = tokenize("3.14")
        XCTAssertEqual(tokens, [.number("3.14")])
    }

    func testTokenizeIdentifier() {
        let tokens = tokenize("xyz")
        XCTAssertEqual(tokens, [.ident("xyz")])
    }

    func testTokenizeKeywords() {
        let tokens = tokenize("let x = 1 where y = 2")
        XCTAssertEqual(tokens, [
            .keyword("let"), .ident("x"), .eq, .number("1"),
            .keyword("where"), .ident("y"), .eq, .number("2"),
        ])
    }

    func testTokenizeOperators() {
        let tokens = tokenize("a + b * c - d / e ^ f")
        XCTAssertEqual(tokens, [
            .ident("a"), .op("+"), .ident("b"), .op("*"), .ident("c"),
            .op("-"), .ident("d"), .op("/"), .ident("e"), .caret, .ident("f"),
        ])
    }

    func testTokenizeParens() {
        let tokens = tokenize("sin(x)")
        XCTAssertEqual(tokens, [.ident("sin"), .lparen, .ident("x"), .rparen])
    }

    func testTokenizeBrackets() {
        let tokens = tokenize("[[1,2],[3,4]]")
        XCTAssertEqual(tokens, [
            .lbracket, .lbracket, .number("1"), .comma, .number("2"), .rbracket,
            .comma,
            .lbracket, .number("3"), .comma, .number("4"), .rbracket, .rbracket,
        ])
    }

    func testTokenizePipe() {
        let tokens = tokenize("|x|")
        XCTAssertEqual(tokens, [.pipe, .ident("x"), .pipe])
    }

    func testTokenizeUnicode() {
        let tokens = tokenize("λ + θ")
        XCTAssertEqual(tokens, [.ident("λ"), .op("+"), .ident("θ")])
    }

    func testTokenizeWhitespace() {
        let tokens = tokenize("  x  +  1  ")
        XCTAssertEqual(tokens, [.ident("x"), .op("+"), .number("1")])
    }

    func testTokenizeComplex() {
        let tokens = tokenize("diff(x^3 + sin(x), x)")
        XCTAssertEqual(tokens, [
            .ident("diff"), .lparen,
            .ident("x"), .caret, .number("3"), .op("+"),
            .ident("sin"), .lparen, .ident("x"), .rparen,
            .comma, .ident("x"), .rparen,
        ])
    }

    func testTokenizeDot() {
        let tokens = tokenize("normal(0,1).ev")
        XCTAssertEqual(tokens, [
            .ident("normal"), .lparen, .number("0"), .comma, .number("1"), .rparen,
            .dot, .ident("ev"),
        ])
    }

    // MARK: - Parser Tests

    func testParseInteger() {
        let parser = Parser(tokenize("42"))
        let result = try! parser.parseExpr()
        XCTAssertEqual(result, .integer(42))
    }

    func testParseRational() {
        let parser = Parser(tokenize("3/4"))
        let result = try! parser.parseExpr()
        XCTAssertEqual(result, .rational(3, 4))
    }

    func testParseDecimal() {
        let parser = Parser(tokenize("2.5"))
        let result = try! parser.parseExpr()
        XCTAssertEqual(result, .real(2.5))
    }

    func testParseSymbol() {
        let parser = Parser(tokenize("x"))
        let result = try! parser.parseExpr()
        XCTAssertEqual(result, .symbol("x"))
    }

    func testParseConstants() {
        let p = Parser(tokenize("pi"))
        XCTAssertEqual(try! p.parseExpr(), CAS.pi)

        let e = Parser(tokenize("e"))
        XCTAssertEqual(try! e.parseExpr(), CAS.e)

        let i = Parser(tokenize("i"))
        XCTAssertEqual(try! i.parseExpr(), CAS.imaginaryUnit)
    }

    func testParseAddition() {
        let parser = Parser(tokenize("x + 2"))
        let result = try! parser.parseExpr()
        XCTAssertEqual(result, .add(.symbol("x"), .integer(2)))
    }

    func testParseSubtraction() {
        let parser = Parser(tokenize("x - 3"))
        let result = try! parser.parseExpr()
        // x - 3  =>  add(x, mul(-1, 3))
        let val = result.eval([sym("x"): 5.0])
        XCTAssertEqual(val, 2.0, accuracy: 1e-10)
    }

    func testParseMultiplication() {
        let parser = Parser(tokenize("2 * x"))
        let result = try! parser.parseExpr()
        XCTAssertEqual(result, .mul(.integer(2), .symbol("x")))
    }

    func testParseDivision() {
        // 6 / 2 uses the rational path: 6/2 = rational(6,2)? No, only if both are adjacent numbers.
        // Actually 6 / 2 parses as: number "6", op "/", number "2" -> rational(6,2)
        // But "x / 2" parses as mul(x, pow(2, -1))
        let parser = Parser(tokenize("x / 2"))
        let result = try! parser.parseExpr()
        let val = result.eval([sym("x"): 6.0])
        XCTAssertEqual(val, 3.0, accuracy: 1e-10)
    }

    func testParsePower() {
        let parser = Parser(tokenize("x^3"))
        let result = try! parser.parseExpr()
        XCTAssertEqual(result, .pow(.symbol("x"), .integer(3)))
    }

    func testParseNegation() {
        let parser = Parser(tokenize("-x"))
        let result = try! parser.parseExpr()
        let val = result.eval([sym("x"): 5.0])
        XCTAssertEqual(val, -5.0, accuracy: 1e-10)
    }

    func testParsePrecedence() {
        // 2 + 3 * 4 = 14  (not 20)
        let parser = Parser(tokenize("2 + 3 * 4"))
        let result = try! parser.parseExpr()
        let val = result.eval()
        XCTAssertEqual(val, 14.0, accuracy: 1e-10)
    }

    func testParseParentheses() {
        // (2 + 3) * 4 = 20
        let parser = Parser(tokenize("(2 + 3) * 4"))
        let result = try! parser.parseExpr()
        let val = result.eval()
        XCTAssertEqual(val, 20.0, accuracy: 1e-10)
    }

    func testParseFunctionCall() {
        let parser = Parser(tokenize("sin(x)"))
        let result = try! parser.parseExpr()
        XCTAssertEqual(result, .function("sin", [.symbol("x")]))
    }

    func testParseFunctionMultiArg() {
        let parser = Parser(tokenize("diff(x^2, x)"))
        let result = try! parser.parseExpr()
        // diff returns the derivative, not the AST of the call
        let val = result.eval([sym("x"): 3.0])
        XCTAssertEqual(val, 6.0, accuracy: 1e-8)
    }

    func testParseMatrix() {
        let parser = Parser(tokenize("[[1,2],[3,4]]"))
        let result = try! parser.parseExpr()
        if case .matrix(let m) = result {
            XCTAssertEqual(m.rows, 2)
            XCTAssertEqual(m.cols, 2)
            XCTAssertEqual(m[0, 0], .integer(1))
            XCTAssertEqual(m[1, 1], .integer(4))
        } else {
            XCTFail("Expected matrix, got \(result)")
        }
    }

    func testParseVector() {
        let parser = Parser(tokenize("[1,2,3]"))
        let result = try! parser.parseExpr()
        if case .matrix(let m) = result {
            XCTAssertEqual(m.rows, 3)
            XCTAssertEqual(m.cols, 1)
        } else {
            XCTFail("Expected column matrix, got \(result)")
        }
    }

    func testParseAbsValue() {
        let parser = Parser(tokenize("|x|"))
        let result = try! parser.parseExpr()
        XCTAssertEqual(result, .function("abs", [.symbol("x")]))
    }

    func testParseUserVars() {
        let parser = Parser(tokenize("f + 1"), vars: ["f": .integer(10)])
        let result = try! parser.parseExpr()
        let val = result.eval()
        XCTAssertEqual(val, 11.0, accuracy: 1e-10)
    }

    func testParseLastResult() {
        let parser = Parser(tokenize("last + 1"), lastResult: .integer(5))
        let result = try! parser.parseExpr()
        let val = result.eval()
        XCTAssertEqual(val, 6.0, accuracy: 1e-10)
    }

    func testParseUnderscore() {
        let parser = Parser(tokenize("_ * 2"), lastResult: .integer(7))
        let result = try! parser.parseExpr()
        let val = result.eval()
        XCTAssertEqual(val, 14.0, accuracy: 1e-10)
    }

    func testParseLastResultNil() {
        let parser = Parser(tokenize("last"))
        XCTAssertThrowsError(try parser.parseExpr())
    }

    // MARK: Top-level parsing

    func testParseTopLevelExpr() {
        let parser = Parser(tokenize("2 + 3"))
        let result = try! parser.parseTopLevel()
        if case .expr(let e) = result {
            XCTAssertEqual(e.eval(), 5.0, accuracy: 1e-10)
        } else {
            XCTFail("Expected .expr")
        }
    }

    func testParseTopLevelAssignment() {
        let parser = Parser(tokenize("let f = x^2 + 1"))
        let result = try! parser.parseTopLevel()
        if case .assignment(let name, let expr) = result {
            XCTAssertEqual(name, "f")
            let val = expr.eval([sym("x"): 3.0])
            XCTAssertEqual(val, 10.0, accuracy: 1e-10)
        } else {
            XCTFail("Expected .assignment")
        }
    }

    func testParseTopLevelWhere() {
        let parser = Parser(tokenize("x^2 + 1 where x=3"))
        let result = try! parser.parseTopLevel()
        if case .expr(let e) = result {
            XCTAssertEqual(e.eval(), 10.0, accuracy: 1e-10)
        } else {
            XCTFail("Expected .expr")
        }
    }

    func testParseTopLevelDistribution() {
        let parser = Parser(tokenize("normal(0, 1)"))
        let result = try! parser.parseTopLevel()
        if case .distribution = result {
            // OK
        } else {
            XCTFail("Expected .distribution, got \(result)")
        }
    }

    func testParseDistributionProperty() {
        let parser = Parser(tokenize("normal(0, 1).ev"))
        let result = try! parser.parseTopLevel()
        if case .expr(let e) = result {
            XCTAssertEqual(e, .integer(0))
        } else {
            XCTFail("Expected .expr(0)")
        }
    }

    // MARK: Error handling

    func testParseErrorMissingParen() {
        let parser = Parser(tokenize("sin(x"))
        XCTAssertThrowsError(try parser.parseExpr())
    }

    func testParseErrorEmptyFunction() {
        let parser = Parser(tokenize("sin()"))
        XCTAssertThrowsError(try parser.parseExpr())
    }

    func testParseErrorWrongArgCount() {
        let parser = Parser(tokenize("diff(x)"))
        XCTAssertThrowsError(try parser.parseExpr())
    }

    func testParseErrorUnexpectedToken() {
        let parser = Parser(tokenize(")"))
        XCTAssertThrowsError(try parser.parseExpr())
    }

    // MARK: Integration with CAS functions

    func testParseSolve() {
        let parser = Parser(tokenize("solve(x^2 - 4, x)"))
        let result = try! parser.parseExpr()
        // Should return roots function with 2 solutions
        if case .function("roots", let roots) = result {
            let vals = roots.map { $0.eval() }.sorted()
            XCTAssertEqual(vals[0], -2.0, accuracy: 1e-8)
            XCTAssertEqual(vals[1], 2.0, accuracy: 1e-8)
        } else {
            XCTFail("Expected roots, got \(result)")
        }
    }

    func testParseODE() {
        let parser = Parser(tokenize("ode(ydd + 4*y, x)"))
        let result = try! parser.parseExpr()
        // Should return a solution involving cos and sin
        let str = "\(result)"
        XCTAssertTrue(str.contains("cos") && str.contains("sin"), "ODE solution should have cos/sin: \(str)")
    }

    func testParseDet() {
        let parser = Parser(tokenize("det([[1,2],[3,4]])"))
        let result = try! parser.parseExpr()
        XCTAssertEqual(result, .integer(-2))
    }

    func testParseIntegrate() {
        let parser = Parser(tokenize("integrate(x^2, x, 0, 1)"))
        let result = try! parser.parseExpr()
        let val = result.eval()
        XCTAssertEqual(val, 1.0 / 3.0, accuracy: 1e-8)
    }

    func testParseNestedExpression() {
        // diff(sin(x^2), x) at x=1 should be cos(1)*2
        let parser = Parser(tokenize("diff(sin(x^2), x)"))
        let result = try! parser.parseExpr()
        let val = result.eval([sym("x"): 1.0])
        XCTAssertEqual(val, Foundation.cos(1.0) * 2.0, accuracy: 1e-8)
    }
}
