import CAS
import Foundation

// MARK: - REPL

func printHelp() {
    print("""

    ╔══════════════════════════════════════════════════════════════╗
    ║              Swift Computer Algebra System                  ║
    ╚══════════════════════════════════════════════════════════════╝

    VARIABLES
      x, y, z, t, a, b, c, n, k  (predefined)
      let <name> = <expr>          define a variable

    ARITHMETIC
      +  -  *  /  ^  (  )         standard operators
      3/4                          rational number

    FUNCTIONS
      sin  cos  tan  exp  log  ln  sqrt  abs
      asin  acos  atan  sinh  cosh  tanh  factorial

    CONSTANTS
      pi  e  i  oo (infinity)

    CALCULUS
      diff(<expr>, <var>)                 differentiate
      diff(<expr>, <var>, <n>)            nth derivative
      integrate(<expr>, <var>)            indefinite integral
      integrate(<expr>, <var>, <lo>, <hi>) definite integral
      limit(<expr>, <var>, <point>)       limit
      taylor(<expr>, <var>, <n>)          Taylor series (n terms around 0)
      gradient(<expr>, [<vars>])          gradient vector
      hessian(<expr>, [<vars>])           Hessian matrix

    LINEAR ALGEBRA
      matrix([[1,2],[3,4]])        construct matrix
      det(<matrix>)                determinant
      inv(<matrix>)                inverse
      transpose(<matrix>)         transpose
      trace(<matrix>)             trace
      rref(<matrix>)              reduced row echelon form
      rank(<matrix>)              rank
      solve(<A>, <b>)             solve Ax = b
      dot([a,b,c], [d,e,f])      dot product
      cross([a,b,c], [d,e,f])    cross product
      charpoly(<matrix>, <var>)   characteristic polynomial
      eigen(<matrix>)             eigenvalues (2x2 numeric)

    EQUATION SOLVING
      solve(<expr>, <var>)         solve expr = 0 for var
      solve(x^2 - 5*x + 6, x)    polynomial roots
      solve(exp(x) - 2, x)        transcendental equations
      solve(sin(x) - 1/2, x)      trig equations

    DIFFERENTIAL EQUATIONS
      ode(<expr>, <var>)           solve ODE (expr = 0)
        y = function, yd = y', ydd = y''
      ode(yd - 2*x, x)            first-order: y' = 2x
      ode(yd + 2*y - exp(x), x)   first-order linear
      ode(ydd + 3*yd + 2*y, x)    second-order constant coeff
      ode(ydd + 4*y, x)           harmonic oscillator

    PROBABILITY
      normal(<mean>, <var>)        Normal distribution
      binomial(<n>, <p>)           Binomial distribution
      poisson(<lambda>)            Poisson distribution
      exponential(<lambda>)        Exponential distribution
      uniform(<a>, <b>)            Uniform distribution
      bernoulli(<p>)               Bernoulli distribution
      geometric(<p>)               Geometric distribution
        .ev                        expected value
        .var                       variance
        .std                       standard deviation
        .pdf(<x>)                  PDF/PMF at x
        .mgf(<t>)                  moment generating function

    OTHER
      <expr> where <var>=<val>     substitution
      eval(<expr>)                 numeric evaluation
      latex(<expr>)                LaTeX output
      simplify(<expr>)             simplify expression

    COMMANDS
      :help                        show this help
      :quit or :q                  exit
      :vars                        show defined variables
      :last                        previous result

    EXAMPLES
      diff(x^3 + sin(x), x)
      integrate(x^2, x, 0, 1)
      limit(sin(x)/x, x, 0)
      taylor(exp(x), x, 8)
      matrix([[1,2],[3,4]]) * matrix([[5],[6]])
      det(matrix([[a,b],[c,d]]))
      solve(x^2 + 1, x)
      ode(ydd + 4*y, x)
      normal(0, 1).pdf(x)
      (x^2 + 2*x + 1) where x=3

    """)
}

// MARK: - REPL Loop

var userVars: [String: Expr] = [:]
var userDists: [String: Distribution] = [:]
var lastResult: Expr?

func run(_ input: String) {
    let trimmed = input.trimmingCharacters(in: .whitespaces)
    if trimmed.isEmpty { return }

    // Commands
    if trimmed.hasPrefix(":") {
        switch trimmed {
        case ":help", ":h", ":?":
            printHelp()
        case ":quit", ":q", ":exit":
            print("Goodbye!")
            exit(0)
        case ":vars":
            if userVars.isEmpty {
                print("  (no user-defined variables)")
            } else {
                for (name, val) in userVars.sorted(by: { $0.key < $1.key }) {
                    print("  \(name) = \(val)")
                }
            }
            if !userDists.isEmpty {
                print("  Distributions:")
                for (name, _) in userDists.sorted(by: { $0.key < $1.key }) {
                    print("    \(name)")
                }
            }
        case ":last":
            if let last = lastResult {
                print("  \(last)")
            } else {
                print("  (no previous result)")
            }
        default:
            print("  Unknown command: \(trimmed). Type :help for help.")
        }
        return
    }

    let tokens = tokenize(trimmed)
    let parser = Parser(tokens, vars: userVars, dists: userDists, lastResult: lastResult)

    do {
        let result = try parser.parseTopLevel()
        switch result {
        case .expr(let expr):
            let simplified = simplify(expr)
            // Special display for roots
            if case .function("roots", let roots) = simplified {
                for (i, root) in roots.enumerated() {
                    print("  x\(i+1) = \(root)")
                }
                lastResult = roots.first
            } else if case .function("implicit", let parts) = simplified, parts.count == 2 {
                print("  \(parts[0]) = \(parts[1])")
                lastResult = simplified
            } else if case .function("latex", let args) = simplified, args.count == 1 {
                print("  \(args[0].latex)")
                lastResult = args[0]
            } else {
                print("  = \(simplified)")
                lastResult = simplified
            }
        case .assignment(let name, let expr):
            let simplified = simplify(expr)
            userVars[name] = simplified
            print("  \(name) = \(simplified)")
            lastResult = simplified
        case .distribution(let dist):
            print("  E[X] = \(simplify(dist.expectedValue))")
            print("  Var(X) = \(simplify(dist.variance))")
            print("  \u{03C3} = \(simplify(dist.standardDeviation))")
        }
    } catch let error as SolveError {
        print("  Error: \(error)")
    } catch let error as ParseError {
        print("  Error: \(error)")
    } catch {
        print("  Error: \(error)")
    }
}

// MARK: - Main

print("""

  ╔══════════════════════════════════════════════════════════════╗
  ║              Swift Computer Algebra System                  ║
  ║                                                             ║
  ║  Type :help for commands, :quit to exit                     ║
  ╚══════════════════════════════════════════════════════════════╝
""")

while true {
    print("cas> ", terminator: "")
    fflush(stdout)
    guard let line = readLine() else {
        print("\nGoodbye!")
        break
    }
    run(line)
}
