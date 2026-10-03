"""Small lexical extractor for the repository's Lean declarations, not a Lean parser.

Tokens preserve literals, comments act as whitespace, and theorem body separators
are found outside binders. Unsupported/malformed input raises instead of being cached.
Lean's kernel and a fresh axiom report remain the proof checks.
"""
from dataclasses import dataclass


@dataclass(frozen=True)
class Token:
    value: str
    line: int
    kind: str = "code"


def tokens(source):
    result = []
    i, line = 0, 1
    while i < len(source):
        ch = source[i]
        if ch.isspace():
            line += ch == "\n"
            i += 1
            continue
        if source.startswith("--", i):
            end = source.find("\n", i)
            i = len(source) if end < 0 else end
            continue
        if source.startswith("/-", i):
            i += 2
            depth = 1
            while i < len(source) and depth:
                if source.startswith("/-", i):
                    depth += 1
                    i += 2
                elif source.startswith("-/", i):
                    depth -= 1
                    i += 2
                else:
                    line += source[i] == "\n"
                    i += 1
            if depth:
                raise ValueError("Unclosed Lean block comment")
            continue
        start, start_line = i, line
        # Lean raw strings: r"...", r#"..."#, and additional hash delimiters.
        raw_hashes = None
        if ch == "r":
            j = i + 1
            while j < len(source) and source[j] == "#":
                j += 1
            if j < len(source) and source[j] == '"':
                raw_hashes = source[i + 1:j]
                close = '"' + raw_hashes
                end = source.find(close, j + 1)
                if end < 0:
                    raise ValueError("Unclosed Lean raw string")
                i = end + len(close)
        if raw_hashes is not None:
            value = source[start:i]
            line += value.count("\n")
            result.append(Token(value, start_line, "literal"))
            continue
        if ch == '"':
            i += 1
            while i < len(source):
                if source[i] == "\\":
                    i += 2
                elif source[i] == '"':
                    i += 1
                    break
                else:
                    i += 1
            else:
                raise ValueError("Unclosed Lean string")
            value = source[start:i]
            line += value.count("\n")
            result.append(Token(value, start_line, "literal"))
            continue
        if ch == "«":
            end = source.find("»", i + 1)
            if end < 0:
                raise ValueError("Unclosed quoted Lean identifier")
            i = end + 1
            result.append(Token(source[start:i], start_line, "identifier"))
            continue
        # Character literals, including escaped quote. A trailing identifier apostrophe
        # is handled by the identifier branch below.
        if ch == "'" and i + 2 < len(source):
            j = i + 2
            if source[i + 1] == "\\":
                j = i + 3
                while j < len(source) and source[j] != "'" and source[j] != "\n":
                    j += 1
            if j < len(source) and source[j] == "'":
                i = j + 1
                result.append(Token(source[start:i], start_line, "literal"))
                continue
        if ch.isalpha() or ch == "_":
            i += 1
            while i < len(source) and (source[i].isalnum() or source[i] in "_'."):
                i += 1
            result.append(Token(source[start:i], start_line, "identifier"))
            continue
        if ch.isdigit():
            i += 1
            while i < len(source) and source[i].isdigit():
                i += 1
        elif source.startswith((":=", "@[", "=>", "->", "&&", "||"), i):
            i += 2
        else:
            i += 1
        result.append(Token(source[start:i], start_line))
    return result


DECLARATIONS = {"theorem", "lemma", "def", "abbrev", "structure", "inductive", "instance"}
BOUNDARIES = DECLARATIONS | {"end", "namespace", "section", "variable", "open", "export"}
MODIFIERS = {"public", "private", "protected", "noncomputable", "unsafe", "partial"}


def commands(ts):
    """Recognize declaration/section starts after line-leading modifiers/attributes."""
    line_start = 0
    for i, tok in enumerate(ts):
        if i == 0 or tok.line != ts[i - 1].line:
            line_start = i
        if tok.value not in BOUNDARIES:
            continue
        prefix = ts[line_start:i]
        depth = 0
        valid = True
        for p in prefix:
            if p.value == "@[":
                depth += 1
            elif p.value == "]" and depth:
                depth -= 1
            elif p.value == "[" and depth:
                depth += 1
            elif not depth and p.value not in MODIFIERS:
                valid = False
        if valid and not depth:
            prefix_start = line_start
            # An attribute may occupy its own preceding line.
            while prefix_start and ts[prefix_start - 1].value == "]":
                j, brackets = prefix_start - 1, 1
                while j and brackets:
                    j -= 1
                    if ts[j].value in {"@[", "["}:
                        brackets -= 1
                    elif ts[j].value == "]":
                        brackets += 1
                if brackets or ts[j].value != "@[":
                    break
                prefix_start = j
            yield i, tok.value, prefix_start


def signature(ts, start, stop):
    stack = []
    pairs = {"(": ")", "{": "}", "[": "]", "⟨": "⟩"}
    for i in range(start, stop):
        value = ts[i].value
        if value == ":=" and not stack:
            return tuple(t.value for t in ts[start:i])
        if value in pairs:
            stack.append(pairs[value])
        elif value in pairs.values():
            if not stack or stack.pop() != value:
                raise ValueError("Unbalanced theorem header")
    raise ValueError("Cannot locate theorem body separator")


def without_account_binder(values):
    # The baseline Ledger production module hoists exactly this binder to `variable`.
    binder = ("{", "n", ":", "Nat", "}")
    result, i = [], 0
    while i < len(values):
        if values[i:i + len(binder)] == binder:
            i += len(binder)
        else:
            result.append(values[i])
            i += 1
    return tuple(result)


def statements(source):
    ts = tokens(source)
    starts = list(commands(ts))
    result = {}
    for k, (i, kind, _) in enumerate(starts):
        if kind not in {"theorem", "lemma"}:
            continue
        name = ts[i + 1].value
        if name in result:
            raise ValueError(f"Duplicate theorem declaration: {name}")
        stop = starts[k + 1][2] if k + 1 < len(starts) else len(ts)
        result[name] = without_account_binder(signature(ts, i + 2, stop))
    return result


def definitions(source):
    ts = tokens(source)
    starts = list(commands(ts))
    result = {}
    for k, (i, kind, _) in enumerate(starts):
        if kind not in DECLARATIONS - {"theorem", "lemma", "instance"}:
            continue
        name = ts[i + 1].value
        if name in result:
            raise ValueError(f"Duplicate definition declaration: {name}")
        stop = starts[k + 1][2] if k + 1 < len(starts) else len(ts)
        result[name] = tuple(t.value for t in ts[i:stop])
    return result


def proof_scan(source):
    """Ignore ordinary literals; conservatively scan interpolated-string contents."""
    ts = tokens(source)
    out = []
    for i, t in enumerate(ts):
        if t.kind != "literal":
            out.append(t.value)
        elif i >= 2 and ts[i - 2].value == "s" and ts[i - 1].value == "!":
            out.append(t.value)
    return " ".join(out)
