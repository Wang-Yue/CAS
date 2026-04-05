import Foundation

// MARK: - Token

public enum Token: Equatable, CustomStringConvertible {
    case number(String)
    case ident(String)
    case op(Character)
    case lparen, rparen
    case lbracket, rbracket
    case comma, dot
    case caret
    case eq
    case pipe       // |
    case keyword(String)  // "let", "where"

    public var description: String {
        switch self {
        case .number(let s): return s
        case .ident(let s): return s
        case .op(let c): return String(c)
        case .lparen: return "("
        case .rparen: return ")"
        case .lbracket: return "["
        case .rbracket: return "]"
        case .comma: return ","
        case .dot: return "."
        case .caret: return "^"
        case .eq: return "="
        case .pipe: return "|"
        case .keyword(let s): return s
        }
    }
}

// MARK: - Tokenizer

public func tokenize(_ input: String) -> [Token] {
    var tokens: [Token] = []
    let chars = Array(input)
    var i = 0

    while i < chars.count {
        let c = chars[i]

        if c.isWhitespace { i += 1; continue }

        // Numbers (integer or decimal)
        if c.isNumber || (c == "." && i + 1 < chars.count && chars[i + 1].isNumber) {
            var num = ""
            while i < chars.count && (chars[i].isNumber || chars[i] == ".") {
                num.append(chars[i]); i += 1
            }
            tokens.append(.number(num))
            continue
        }

        // Identifiers and keywords
        if c.isLetter || c == "_" || c == "λ" || c == "α" || c == "β" || c == "θ" || c == "σ" || c == "μ" {
            var name = ""
            while i < chars.count && (chars[i].isLetter || chars[i].isNumber || chars[i] == "_"
                                       || chars[i] == "λ" || chars[i] == "α" || chars[i] == "β"
                                       || chars[i] == "θ" || chars[i] == "σ" || chars[i] == "μ") {
                name.append(chars[i]); i += 1
            }
            if name == "let" || name == "where" {
                tokens.append(.keyword(name))
            } else {
                tokens.append(.ident(name))
            }
            continue
        }

        switch c {
        case "+", "-", "*", "/": tokens.append(.op(c))
        case "^": tokens.append(.caret)
        case "(": tokens.append(.lparen)
        case ")": tokens.append(.rparen)
        case "[": tokens.append(.lbracket)
        case "]": tokens.append(.rbracket)
        case ",": tokens.append(.comma)
        case ".": tokens.append(.dot)
        case "=": tokens.append(.eq)
        case "|": tokens.append(.pipe)
        default: break
        }
        i += 1
    }
    return tokens
}
