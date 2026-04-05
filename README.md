# CAS - Computer Algebra System in Swift

A symbolic computer algebra system written in pure Swift, covering college-level mathematics: calculus, linear algebra, probability, equation solving, and differential equations. Includes a built-in tokenizer, parser, and interactive REPL.

## Features

### Symbolic Expressions
- Full expression tree with integers, rationals, reals, symbols, and constants (`pi`, `e`, `i`)
- Operator overloading: `+`, `-`, `*`, `/`, `**` (power)
- Standard functions: `sin`, `cos`, `tan`, `exp`, `log`, `sqrt`, `asin`, `acos`, `atan`, `sinh`, `cosh`, `tanh`
- Complex numbers: `i` as a first-class constant, `sqrt(-1) = i`, `i^2 = -1`
- Substitution, numeric evaluation, free symbol detection
- Algebraic simplification (like terms, power rules, trig identities, constant folding, square root simplification)
- LaTeX output for all expressions

### Calculus
- **Differentiation**: all standard functions, chain rule, product rule, power rule, higher-order derivatives
- **Integration**: power rule, standard functions, u-substitution, integration by parts (including nested and cyclic IBP), trig identities, inverse trig forms, partial fractions, linear substitution
- **Limits**: direct substitution with numerical fallback for indeterminate forms
- **Taylor series**: arbitrary order around any point
- **Vector calculus**: gradient, Hessian, Jacobian

### Linear Algebra
- Matrix construction, arithmetic (`+`, `-`, `*`), scalar multiplication
- Determinant (cofactor expansion), inverse (adjugate method), transpose, trace
- Reduced row echelon form (RREF), rank
- Linear system solving (`Ax = b`)
- Characteristic polynomial, eigenvalues (2x2)
- Dot product, cross product
- Fully symbolic matrices

### Probability & Statistics
- **Distributions**: Normal, Binomial, Poisson, Exponential, Uniform, Bernoulli, Geometric
- Expected value, variance, standard deviation
- Symbolic PDF/PMF and moment generating functions
- Bayes' theorem, combinatorics (`nCr`, `nPr`)

### Equation Solving
- **Polynomial**: linear, quadratic (symbolic with complex roots), cubic (rational root theorem + symbolic Cardano/trigonometric), quartic and higher (rational roots + numeric Newton-Raphson)
- **Complex roots**: `x^2 + 1 = 0` yields `i` and `-i`; `x^2 + 2x + 5 = 0` yields `-1 + 2i` and `-1 - 2i`
- **Transcendental**: `exp(f(x)) = a`, `log(f(x)) = a`, `sin(f(x)) = a`, `a^f(x) = b`, `sqrt(f(x)) = a`, with recursive inner solving

### Differential Equations
- **First-order linear**: `y' + P(x)y = Q(x)` via integrating factor
- **Separable**: `y' = f(x)g(y)` via separation of variables
- **Second-order constant coefficient**: `ay'' + by' + cy = 0`
  - Distinct real roots, complex conjugate roots, repeated roots
  - Integration constants `C1`, `C2` in solutions

### Parser & Tokenizer
- Full tokenizer supporting numbers, identifiers, operators, brackets, Unicode symbols
- Recursive descent parser with correct operator precedence
- Supports function calls, matrix literals, absolute value, distribution properties
- Reusable as a library (public API in the CAS package)

## Getting Started

### Requirements

- Swift 5.9+
- macOS or Linux

### Build and Run

```bash
# Build
swift build

# Run the interactive REPL
swift run Demo

# Run tests (144 tests)
swift test
```

### REPL Usage

```
cas> diff(x^3 + sin(x), x)
  = 3*x^2 + cos(x)

cas> integrate(x * exp(x), x)
  = x*exp(x) - exp(x)

cas> integrate(exp(x) * sin(x), x)
  = (sin(x)*exp(x))/2 + (-cos(x)*exp(x))/2

cas> det([[1,2],[3,4]])
  = -2

cas> solve(x^2 - 5*x + 6, x)
  x1 = 3
  x2 = 2

cas> solve(x^2 + 1, x)
  x1 = i
  x2 = -i

cas> solve(exp(x) - 2, x)
  = log(2)

cas> ode(ydd + 4*y, x)
  = C1*cos(2*x) + C2*sin(2*x)

cas> ode(yd + 2*y, x)
  = C1*exp(-2*x)

cas> normal(0, 1).pdf(x)
  = (2*pi)^-1/2*exp(-x^2/2)

cas> simplify(sqrt(48))
  = 4*sqrt(3)

cas> latex(x^2/3)
  \frac{x^{2}}{3}
```

### REPL Commands

| Command | Description |
|---|---|
| `:help` | Show full help |
| `:quit` | Exit |
| `:vars` | Show defined variables |
| `:last` | Show previous result |
| `_` or `last` | Reference previous result in expressions |
| `let f = expr` | Define a variable |
| `expr where x=3` | Substitution |

### Library Usage

```swift
import CAS

let x = sym("x")

// Differentiation
let f = x ** 3 + sin(x)
let df = diff(f, x)  // 3*x^2 + cos(x)

// Integration
let g = integrate(x * exp(x), x)  // x*exp(x) - exp(x)

// Definite integral
let area = integrate(x ** 2, x, from: .integer(0), to: .integer(1))  // 1/3

// Equation solving
let roots = try solve(x ** 2 - 5 * x + 6, x)  // [3, 2]

// Complex roots
let complex = try solve(x ** 2 + 1, x)  // [i, -i]

// ODE: y'' + 4y = 0
let sol = try solveODE(sym("ydd") + 4 * sym("y"), y: sym("y"), x: x)
// C1*cos(2*x) + C2*sin(2*x)

// Matrices
let A = Matrix([[.integer(1), .integer(2)], [.integer(3), .integer(4)]])
let det = A.determinant()  // -2
let inv = A.inverse()

// Probability
let normal = Distribution.normal(mean: .integer(0), variance: .integer(1))
let ev = normal.expectedValue  // 0
let pdf = normal.pdf(x)

// Taylor series
let series = taylor(sin(x), x, terms: 5)

// Parsing expressions from strings
let tokens = tokenize("x^2 + 2*x + 1")
let parser = Parser(tokens)
let expr = try parser.parseExpr()  // Expr tree for x^2 + 2*x + 1

// Numeric evaluation
let val = sin(pi / 4).eval()  // 0.7071...

// LaTeX
let tex = (x ** 2 + 1).latex  // "x^{2} + 1"
```

## Architecture

```
Sources/CAS/
  Expression.swift      Core Expr enum, operators, eval, substitution
  Simplify.swift        Algebraic simplification engine
  Calculus.swift         Differentiation, integration, limits, Taylor series
  LinearAlgebra.swift    Matrix type and operations
  Probability.swift      Distributions and combinatorics
  Solver.swift           Equation solving and ODE solver
  Tokenizer.swift        Lexer (Token enum + tokenize function)
  Parser.swift           Recursive descent parser
  Printing.swift         Pretty printer and LaTeX renderer

Sources/Demo/
  main.swift             Interactive REPL

Tests/CASTests/
  CASTests.swift         144 tests covering all modules
```

### Expression Representation

Expressions use a recursive `indirect enum`:

```swift
public indirect enum Expr: Hashable {
    case integer(Int)
    case rational(Int, Int)
    case real(Double)
    case symbol(String)
    case constant(Constant)    // pi, e, i, infinity
    case add(Expr, Expr)
    case mul(Expr, Expr)
    case pow(Expr, Expr)
    case function(String, [Expr])
    case matrix(Matrix)
}
```

### Integration Techniques

The integrator applies strategies in order:

1. Linearity (sums and constant multiples)
2. Power rule (`x^n`)
3. Standard function table (17 functions)
4. Linear substitution (`f(ax+b)`)
5. Trig power identities (`sin^2`, `cos^2`)
6. Inverse trig / rational forms (`1/(x^2+a)`, `1/sqrt(1-x^2)`)
7. Trig product (`sin*cos`)
8. u-substitution (pattern matching on `f'(g(x))*g'(x)`)
9. Integration by parts (LIATE heuristic, nested, cyclic detection)
10. Algebraic expansion

### Equation Solving Strategy

1. Extract polynomial coefficients from the expression
2. Try the **rational root theorem** to find exact integer/fractional roots
3. **Deflate** the polynomial by each found root to reduce degree
4. Apply **symbolic formulas** for the remaining polynomial:
   - Degree 1: direct solve
   - Degree 2: quadratic formula (with complex root support via `i`)
   - Degree 3: Cardano's formula / trigonometric method
   - Degree 4+: numeric Newton-Raphson
5. For non-polynomial equations, **pattern-match** transcendental forms (`exp`, `log`, `sin`, `sqrt`, etc.)

### ODE Classification

The ODE solver classifies equations automatically:

| Type | Form | Method |
|---|---|---|
| First-order linear | `y' + P(x)y = Q(x)` | Integrating factor |
| Separable | `y' = f(x)g(y)` | Separation of variables |
| 2nd-order const. coeff. | `ay'' + by' + cy = 0` | Characteristic equation |

For second-order equations, the solver detects:
- Distinct real roots: `y = C1*exp(r1*x) + C2*exp(r2*x)`
- Complex roots: `y = exp(ax)*(C1*cos(bx) + C2*sin(bx))`
- Repeated root: `y = (C1 + C2*x)*exp(rx)`

## Testing

```bash
swift test
```

144 tests covering:
- Core expression operations (5 tests)
- Simplification (7 tests)
- Differentiation (8 tests)
- Integration (19 tests)
- Taylor series (2 tests)
- Linear algebra (10 tests)
- Probability (4 tests)
- Vector calculus (2 tests)
- LaTeX output (3 tests)
- Equation solving (11 tests)
- Complex numbers & sqrt simplification (12 tests)
- Rational root theorem & symbolic Cardano (5 tests)
- ODE solving (8 tests)
- Tokenizer (12 tests)
- Parser: expressions, precedence, functions, matrices (20 tests)
- Parser: top-level, assignments, where, distributions (5 tests)
- Parser: error handling (4 tests)
- Parser: CAS function integration (5 tests)

## License

BSD 3-Clause License. See [LICENSE](LICENSE).
