import Foundation

// MARK: - Matrix Type

public struct Matrix: Hashable {
    public let rows: Int
    public let cols: Int
    public let elements: [[Expr]]

    public init(_ elements: [[Expr]]) {
        precondition(!elements.isEmpty && !elements[0].isEmpty, "Matrix cannot be empty")
        precondition(elements.allSatisfy({ $0.count == elements[0].count }), "All rows must have the same number of columns")
        self.rows = elements.count
        self.cols = elements[0].count
        self.elements = elements
    }

    public subscript(row: Int, col: Int) -> Expr {
        elements[row][col]
    }

    // MARK: Identity & Zero

    public static func identity(_ n: Int) -> Matrix {
        let elems = (0..<n).map { i in
            (0..<n).map { j -> Expr in i == j ? .integer(1) : .integer(0) }
        }
        return Matrix(elems)
    }

    public static func zero(_ rows: Int, _ cols: Int) -> Matrix {
        Matrix(Array(repeating: Array(repeating: Expr.integer(0), count: cols), count: rows))
    }

    // MARK: Transpose

    public func transposed() -> Matrix {
        let elems = (0..<cols).map { j in
            (0..<rows).map { i in elements[i][j] }
        }
        return Matrix(elems)
    }

    // MARK: Arithmetic

    public static func + (lhs: Matrix, rhs: Matrix) -> Matrix {
        precondition(lhs.rows == rhs.rows && lhs.cols == rhs.cols, "Dimension mismatch")
        let elems = (0..<lhs.rows).map { i in
            (0..<lhs.cols).map { j in simplify(lhs[i, j] + rhs[i, j]) }
        }
        return Matrix(elems)
    }

    public static func - (lhs: Matrix, rhs: Matrix) -> Matrix {
        precondition(lhs.rows == rhs.rows && lhs.cols == rhs.cols, "Dimension mismatch")
        let elems = (0..<lhs.rows).map { i in
            (0..<lhs.cols).map { j in simplify(lhs[i, j] - rhs[i, j]) }
        }
        return Matrix(elems)
    }

    public static func * (lhs: Matrix, rhs: Matrix) -> Matrix {
        precondition(lhs.cols == rhs.rows, "Dimension mismatch for multiplication")
        let elems = (0..<lhs.rows).map { i in
            (0..<rhs.cols).map { j -> Expr in
                var sum: Expr = .integer(0)
                for k in 0..<lhs.cols {
                    sum = sum + lhs[i, k] * rhs[k, j]
                }
                return simplify(sum)
            }
        }
        return Matrix(elems)
    }

    public static func * (scalar: Expr, rhs: Matrix) -> Matrix {
        let elems = rhs.elements.map { row in
            row.map { simplify(scalar * $0) }
        }
        return Matrix(elems)
    }

    public static func * (scalar: Int, rhs: Matrix) -> Matrix {
        Expr.integer(scalar) * rhs
    }

    // MARK: Determinant (Laplace expansion)

    public func determinant() -> Expr {
        precondition(rows == cols, "Determinant requires a square matrix")
        if rows == 1 { return elements[0][0] }
        if rows == 2 {
            return simplify(elements[0][0] * elements[1][1] - elements[0][1] * elements[1][0])
        }

        var det: Expr = .integer(0)
        for j in 0..<cols {
            let sign: Expr = j % 2 == 0 ? .integer(1) : .integer(-1)
            let cofactor = minor(0, j).determinant()
            det = det + sign * elements[0][j] * cofactor
        }
        return simplify(det)
    }

    public func minor(_ row: Int, _ col: Int) -> Matrix {
        let elems = elements.enumerated().compactMap { (i, r) -> [Expr]? in
            guard i != row else { return nil }
            return r.enumerated().compactMap { (j, e) in j != col ? e : nil }
        }
        return Matrix(elems)
    }

    // MARK: Trace

    public func trace() -> Expr {
        precondition(rows == cols, "Trace requires a square matrix")
        var result: Expr = .integer(0)
        for i in 0..<rows {
            result = result + elements[i][i]
        }
        return simplify(result)
    }

    // MARK: Inverse (via adjugate)

    public func inverse() -> Matrix {
        precondition(rows == cols, "Inverse requires a square matrix")
        let det = determinant()

        let cofactors = (0..<rows).map { i in
            (0..<cols).map { j -> Expr in
                let sign: Expr = (i + j) % 2 == 0 ? .integer(1) : .integer(-1)
                return simplify(sign * minor(i, j).determinant())
            }
        }
        let adjugate = Matrix(cofactors).transposed()
        let invDet = Expr.integer(1) / det
        return invDet * adjugate
    }

    // MARK: Row Echelon Form (for numeric matrices)

    public func rref() -> Matrix {
        var m = elements
        let numRows = rows
        let numCols = cols
        var pivotRow = 0

        for col in 0..<numCols {
            guard pivotRow < numRows else { break }

            // Find pivot
            var maxRow = pivotRow
            var maxVal = Swift.abs(m[pivotRow][col].eval())
            for row in (pivotRow + 1)..<numRows {
                let val = Swift.abs(m[row][col].eval())
                if val > maxVal {
                    maxVal = val
                    maxRow = row
                }
            }
            if maxVal < 1e-12 { continue }

            m.swapAt(pivotRow, maxRow)

            // Scale pivot row
            let pivotVal = m[pivotRow][col]
            for j in 0..<numCols {
                m[pivotRow][j] = simplify(m[pivotRow][j] / pivotVal)
            }

            // Eliminate column
            for i in 0..<numRows where i != pivotRow {
                let factor = m[i][col]
                if factor.isZero { continue }
                for j in 0..<numCols {
                    m[i][j] = simplify(m[i][j] - factor * m[pivotRow][j])
                }
            }
            pivotRow += 1
        }
        return Matrix(m)
    }

    // MARK: Rank

    public var rank: Int {
        let r = rref()
        return r.elements.filter { row in
            !row.allSatisfy { $0.isZero }
        }.count
    }

    // MARK: Eigenvalues (2x2 and 3x3 characteristic polynomial)

    public func characteristicPolynomial(_ lambda: Expr) -> Expr {
        precondition(rows == cols, "Eigenvalues require a square matrix")
        let lambdaI = lambda * Matrix.identity(rows)
        let diff = self - lambdaI
        return simplify(diff.determinant())
    }

    // MARK: Dot product (vectors as column matrices or 1D arrays)

    public static func dot(_ a: [Expr], _ b: [Expr]) -> Expr {
        precondition(a.count == b.count, "Vectors must be same length")
        var result: Expr = .integer(0)
        for i in 0..<a.count {
            result = result + a[i] * b[i]
        }
        return simplify(result)
    }

    // MARK: Cross product (3D vectors)

    public static func cross(_ a: [Expr], _ b: [Expr]) -> [Expr] {
        precondition(a.count == 3 && b.count == 3, "Cross product requires 3D vectors")
        return [
            simplify(a[1] * b[2] - a[2] * b[1]),
            simplify(a[2] * b[0] - a[0] * b[2]),
            simplify(a[0] * b[1] - a[1] * b[0]),
        ]
    }

    // MARK: Solve Ax = b (via rref of augmented matrix)

    public func solve(_ b: Matrix) -> Matrix {
        precondition(rows == cols, "System must be square")
        precondition(b.cols == 1 && b.rows == rows, "b must be a column vector of matching size")

        // Build augmented matrix [A | b]
        let augmented = (0..<rows).map { i in
            elements[i] + [b[i, 0]]
        }
        let rrefResult = Matrix(augmented).rref()

        // Extract solution
        let solution = (0..<rows).map { i in [rrefResult[i, cols]] }
        return Matrix(solution)
    }

    // MARK: Pretty print

    public var description: String {
        let strs = elements.map { row in
            row.map { "\($0)" }
        }
        let maxWidths = (0..<cols).map { j in
            strs.map { $0[j].count }.max() ?? 0
        }
        let lines = strs.map { row in
            let padded = row.enumerated().map { (j, s) in
                s.padding(toLength: maxWidths[j], withPad: " ", startingAt: 0)
            }
            return "| " + padded.joined(separator: "  ") + " |"
        }
        return lines.joined(separator: "\n")
    }
}
