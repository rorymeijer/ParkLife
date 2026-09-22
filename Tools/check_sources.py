#!/usr/bin/env python3
"""
Structural checks for the ParkLife Swift sources.

This is NOT a Swift compiler and does not pretend to be one. It exists because the
container this project was developed in has no Swift toolchain, so it catches the
classes of mistake that are cheap to detect without type checking:

  * unbalanced braces / parens / brackets (with a real lexer for strings,
    escapes, interpolation and comments)
  * duplicate top-level type declarations
  * references to capitalised types that are declared nowhere (typos in type names)
  * files under Sources/ that SwiftPM would not pick up

CI runs `swift build` and `swift test` for the real answer; this runs everywhere.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Types provided by the standard library / Foundation that we legitimately reference.
KNOWN_EXTERNAL = {
    "Int", "Int8", "Int16", "Int32", "Int64", "UInt", "UInt8", "UInt16", "UInt32", "UInt64",
    "Double", "Float", "Bool", "String", "Character", "Substring", "Array", "Dictionary",
    "Set", "Optional", "Result", "Error", "Any", "AnyObject", "Void", "Never",
    "Data", "Date", "URL", "UUID", "Bundle", "FileManager", "JSONEncoder", "JSONDecoder",
    "JSONSerialization", "NSLock", "Decoder", "Encoder", "CodingKey", "CodingKeys",
    "Codable", "Decodable", "Encodable", "Hashable", "Equatable", "Comparable",
    "CustomStringConvertible", "RawRepresentable", "CaseIterable", "Sendable",
    "RandomNumberGenerator", "Swift", "Foundation", "Identifiable", "IteratorProtocol",
    "Sequence", "Collection", "Task", "Actor", "MainActor", "TimeInterval", "Numeric",
    "ClosedRange", "Range", "XCTestCase", "XCTest", "Self", "Type", "Protocol",
    "SIMD", "Locale", "Calendar", "DateFormatter", "ProcessInfo", "Measurement", "StaticString",
    "ParkLifeCore", "ParkLife",
    # SwiftUI / Combine / OSLog / SpriteKit symbols used by the app layer.
    "App", "Scene", "View", "WindowGroup", "StateObject", "ObservedObject", "EnvironmentObject",
    "Environment", "Published", "State", "Binding", "Color", "Image", "Text", "Button", "Toggle",
    "Slider", "Stepper", "List", "Section", "Form", "NavigationStack", "NavigationSplitView",
    "ScrollView", "LazyVStack", "LazyHStack", "LazyVGrid", "GridItem", "VStack", "HStack",
    "ZStack", "Spacer", "Divider", "Group", "ForEach", "Label", "Picker", "TabView", "Menu",
    "Alignment", "Font", "Angle", "Animation", "Transaction", "Gradient", "LinearGradient",
    "RoundedRectangle", "Circle", "Capsule", "Rectangle", "Path", "Canvas", "GeometryReader",
    "ProgressView", "Chart", "Combine", "Logger", "SpriteView", "DEBUG", "Sendable",
    "ContentUnavailableView", "ViewBuilder", "ShapeStyle", "EdgeInsets", "Edge", "Axis",
    "UnitPoint", "TimelineView", "AnyView", "EmptyView", "PreviewProvider", "ObservableObject",
    "Identifiable", "CaseIterable", "Hashable", "UIColor", "CGFloat", "CGPoint", "CGSize",
    "CGRect", "UIImage", "UIBezierPath", "UIGraphicsImageRenderer", "LabeledContent", "ID", "UserDefaults",
    "ToolbarItem", "DispatchQueue", "Task", "StrokeStyle", "CVarArg",
}

# XCTest assertion functions are free functions, not types, but they match the
# capitalised-identifier heuristic.
XCTEST_PREFIX = "XCT"

DECL_RE = re.compile(
    r"^(\s*)(?:public\s+|internal\s+|private\s+|fileprivate\s+|open\s+|final\s+|indirect\s+)*"
    r"(struct|class|enum|protocol|actor|typealias)\s+([A-Za-z_][A-Za-z0-9_]*)\s*(<[^>{]*>)?"
)
GENERIC_PARAM_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
# Generic parameter names introduced by functions, e.g. `func next<T: EntityIdentifier>(...)`.
FUNC_GENERIC_RE = re.compile(r"\bfunc\s+[A-Za-z_][A-Za-z0-9_]*\s*<([^>]*)>")
MEMBER_REF_RE = re.compile(r"\b([A-Z][A-Za-z0-9_]*)\b")


def strip_code(text):
    """Return the source with string literals and comments blanked out."""
    out = []
    i = 0
    n = len(text)
    while i < n:
        ch = text[i]
        if ch == "/" and i + 1 < n and text[i + 1] == "/":
            while i < n and text[i] != "\n":
                i += 1
            continue
        if ch == "/" and i + 1 < n and text[i + 1] == "*":
            depth = 1
            i += 2
            while i < n and depth > 0:
                if text[i] == "/" and i + 1 < n and text[i + 1] == "*":
                    depth += 1
                    i += 2
                elif text[i] == "*" and i + 1 < n and text[i + 1] == "/":
                    depth -= 1
                    i += 2
                else:
                    if text[i] == "\n":
                        out.append("\n")
                    i += 1
            continue
        if ch == '"':
            # Multiline string?
            if text.startswith('"""', i):
                i += 3
                while i < n and not text.startswith('"""', i):
                    if text[i] == "\n":
                        out.append("\n")
                    i += 1
                i += 3
                continue
            i += 1
            while i < n:
                if text[i] == "\\":
                    # Interpolation keeps its parentheses balanced, so keep them.
                    if i + 1 < n and text[i + 1] == "(":
                        depth = 0
                        i += 1
                        while i < n:
                            if text[i] == "(":
                                depth += 1
                            elif text[i] == ")":
                                depth -= 1
                                if depth == 0:
                                    i += 1
                                    break
                            i += 1
                        continue
                    i += 2
                    continue
                if text[i] == '"':
                    i += 1
                    break
                if text[i] == "\n":
                    out.append("\n")
                i += 1
            continue
        out.append(ch)
        i += 1
    return "".join(out)


ENUM_DECL_RE = re.compile(
    r"^\s*(?:public\s+|internal\s+|private\s+|fileprivate\s+|indirect\s+)*enum\s+([A-Za-z_][A-Za-z0-9_]*)"
)
CASE_DECL_RE = re.compile(r"^\s*case\s+([A-Za-z_][A-Za-z0-9_]*(?:\s*,\s*[A-Za-z_][A-Za-z0-9_]*)*)")


def collect_enum_cases(code):
    """Map each enum name to the set of its case names, by brace depth."""
    enums = {}
    stack = []          # (enum name or None, depth at which it opened)
    depth = 0
    for line in code.splitlines():
        match = ENUM_DECL_RE.match(line)
        opening = line.count("{")
        closing = line.count("}")
        if match and opening:
            name = match.group(1)
            enums.setdefault(name, set())
            stack.append((name, depth))
        elif opening and not match:
            stack.append((None, depth))
        depth += opening - closing
        while stack and depth <= stack[-1][1]:
            stack.pop()
        if stack and stack[-1][0]:
            case_match = CASE_DECL_RE.match(line)
            if case_match and "(" not in line.split("case", 1)[1].split("=")[0][:40]:
                for name in case_match.group(1).split(","):
                    enums[stack[-1][0]].add(name.strip())
            elif case_match:
                # Case with an associated value: `case walkingTo(BuildingID)`
                first = line.split("case", 1)[1].strip()
                enums[stack[-1][0]].add(re.split(r"[(\s:=,]", first)[0])
    return enums


SWITCH_RE = re.compile(r"^(\s*)(?:\w+\s*=\s*)?switch\s+.+\{\s*$")


def split_top_level(text, separator=","):
    """Split on `separator`, ignoring anything inside brackets."""
    parts = []
    depth = 0
    current = ""
    for ch in text:
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
        if ch == separator and depth == 0:
            parts.append(current)
            current = ""
        else:
            current += ch
    parts.append(current)
    return [p.strip() for p in parts if p.strip()]


def case_labels(text):
    """
    Labels from a case pattern such as
        `.walkingTo(let id), .queueing(let id)` or `.number(let v)` or `.a, .b,\n .c`.
    Returns None when any pattern is not a plain leading-dot case (a `where` clause, a tuple,
    a bound value), because those cannot be checked for exhaustiveness this way.
    """
    if "where" in text:
        return None
    labels = []
    for part in split_top_level(text):
        if not part.startswith("."):
            return None
        name = re.split(r"[(\s:]", part[1:])[0]
        if not name:
            return None
        labels.append(name)
    return labels


def check_switch_exhaustiveness(path, code, enum_cases):
    """
    Flags a switch whose case labels are all leading-dot patterns matching exactly one known
    enum, that has no `default`, and that misses cases. A non-exhaustive switch is a compile
    error in Swift, and it is the class of mistake a checker without a type system can still
    catch.
    """
    problems = []
    lines = code.splitlines()
    index = 0
    while index < len(lines):
        match = SWITCH_RE.match(lines[index])
        if not match:
            index += 1
            continue
        indent = len(match.group(1))
        labels = []
        has_default = False
        unparseable = False
        cursor = index + 1
        depth = 1
        start_line = index + 1

        while cursor < len(lines) and depth > 0:
            line = lines[cursor]
            depth += line.count("{") - line.count("}")
            if depth <= 0:
                break
            stripped = line.strip()
            line_indent = len(line) - len(line.lstrip())
            # Swift style puts `case` at the same indentation as `switch`; allow both.
            if line_indent in (indent, indent + 4):
                if stripped.startswith("default"):
                    has_default = True
                elif stripped.startswith("case "):
                    # A case label may wrap over several lines; gather until the pattern's
                    # closing colon at bracket depth zero.
                    pattern = stripped[len("case "):]
                    scan = cursor
                    while _colon_index(pattern) is None and scan + 1 < len(lines):
                        scan += 1
                        pattern += " " + lines[scan].strip()
                    colon = _colon_index(pattern)
                    if colon is None:
                        unparseable = True
                    else:
                        found = case_labels(pattern[:colon])
                        if found is None:
                            unparseable = True
                        else:
                            labels.extend(found)
                    cursor = scan
            cursor += 1
        index = cursor + 1

        if has_default or unparseable or len(labels) < 2:
            continue
        label_set = set(labels)
        candidates = [name for name, cases in enum_cases.items() if label_set <= cases]
        if len(candidates) != 1:
            continue
        missing = enum_cases[candidates[0]] - label_set
        if missing:
            problems.append(
                f"{path}:{start_line}: switch over '{candidates[0]}' has no default and is "
                f"missing: {', '.join(sorted(missing))}"
            )
    return problems


def _colon_index(text):
    """Index of the first `:` outside any bracket, or None."""
    depth = 0
    for position, ch in enumerate(text):
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
        elif ch == ":" and depth == 0:
            return position
    return None


def check_conditional_compilation(path, code):
    """`#if` without a matching `#endif` fails to compile and is invisible to a brace check."""
    opens = len(re.findall(r"^\s*#if\b", code, flags=re.M))
    closes = len(re.findall(r"^\s*#endif\b", code, flags=re.M))
    if opens != closes:
        return [f"{path}: {opens} '#if' but {closes} '#endif'"]
    return []


SELF_ASSIGN_RE = re.compile(
    r"^\s*([A-Za-z_][\w]*(?:\.[\w]+)*)\?\.([\w]+)\s*(?:\+=|-=|\*=|/=|=)\s*(.+)$"
)
MODIFY_RE = re.compile(r"\b(\w+)\.(\w+)\.modify\(")
# Computed properties on World: reading one accesses the *whole* struct.
WORLD_COMPUTED = {
    "tick", "date", "reception", "parkEntranceTiles", "netWorth", "totalUnitCapacity",
    "totalUnits", "occupiedUnits", "occupancyRate", "averageGuestHappiness",
}


def check_exclusivity(path, code):
    """
    Two patterns Swift's exclusivity checker rejects, both found the hard way by CI:

      a?.b = f(a?.b)              reads and writes one optional chain in a single expression
      store.modify { … world.tick … }   reads a computed property on the struct whose part is
                                        already exclusively accessed

    Neither is visible to a brace check, and both are compile errors rather than warnings.
    """
    problems = []
    lines = code.splitlines()

    for number, line in enumerate(lines, 1):
        match = SELF_ASSIGN_RE.match(line)
        if match:
            prefix, prop, rhs = match.groups()
            if re.search(rf"{re.escape(prefix)}\?\.{re.escape(prop)}\b", rhs):
                problems.append(
                    f"{path}:{number}: '{prefix}?.{prop}' is read and written in one "
                    f"expression; read it into a local first [exclusivity]"
                )

    depth = 0
    opener = None
    owner = None
    for number, line in enumerate(lines, 1):
        if depth == 0:
            match = MODIFY_RE.search(line)
            if match:
                owner = match.group(1)
                opener = number
                # A single-line closure — `store.modify(id) { $0.x = world.date }` — opens and
                # closes on this line, so the line itself has to be inspected here or it is
                # never inspected at all.
                tail = line[match.end():]
                for name in WORLD_COMPUTED:
                    if re.search(rf"\b{re.escape(owner)}\.{name}\b", tail):
                        problems.append(
                            f"{path}:{number}: closure reads '{owner}.{name}' (a computed "
                            f"property) while '{owner}' is exclusively accessed; hoist it to a "
                            f"local [exclusivity]"
                        )
                depth = line.count("{") - line.count("}")
                if depth < 0:
                    depth = 0
                continue
        else:
            for name in WORLD_COMPUTED:
                if re.search(rf"\b{re.escape(owner)}\.{name}\b", line):
                    problems.append(
                        f"{path}:{opener}: closure reads '{owner}.{name}' (a computed property) "
                        f"while '{owner}' is exclusively accessed; hoist it to a local "
                        f"[exclusivity]"
                    )
            depth += line.count("{") - line.count("}")
            if depth <= 0:
                depth = 0
    return problems


def check_balance(path, code):
    problems = []
    pairs = {")": "(", "]": "[", "}": "{"}
    stack = []
    line = 1
    for ch in code:
        if ch == "\n":
            line += 1
        elif ch in "([{":
            stack.append((ch, line))
        elif ch in ")]}":
            if not stack:
                problems.append(f"{path}:{line}: unmatched '{ch}'")
            else:
                opener, opened_line = stack.pop()
                if opener != pairs[ch]:
                    problems.append(
                        f"{path}:{line}: '{ch}' closes '{opener}' opened at line {opened_line}"
                    )
    for opener, opened_line in stack:
        problems.append(f"{path}:{opened_line}: '{opener}' is never closed")
    return problems


def main():
    swift_files = []
    for base in ("Sources", "Tests"):
        for dirpath, _dirnames, filenames in os.walk(os.path.join(ROOT, base)):
            for name in filenames:
                if name.endswith(".swift"):
                    swift_files.append(os.path.join(dirpath, name))
    app_dir = os.path.join(ROOT, "App")
    if os.path.isdir(app_dir):
        for dirpath, _dirnames, filenames in os.walk(app_dir):
            for name in filenames:
                if name.endswith(".swift"):
                    swift_files.append(os.path.join(dirpath, name))
    swift_files.sort()

    problems = []
    declarations = {}
    references = {}
    all_enum_cases = {}
    pending_switches = []

    for path in swift_files:
        rel = os.path.relpath(path, ROOT)
        with open(path, encoding="utf-8") as handle:
            text = handle.read()
        code = strip_code(text)
        problems.extend(check_balance(rel, code))
        problems.extend(check_conditional_compilation(rel, code))
        problems.extend(check_exclusivity(rel, code))
        file_enums = collect_enum_cases(code)
        all_enum_cases.update(file_enums)
        pending_switches.append((rel, code))

        for line in code.splitlines():
            match = DECL_RE.match(line)
            if match:
                indent, _keyword, name, generics = match.group(1), match.group(2), match.group(3), match.group(4)
                nested = len(indent) > 0
                declarations.setdefault(name, []).append((rel, nested))
                if generics:
                    for param in GENERIC_PARAM_RE.findall(generics):
                        declarations.setdefault(param, []).append((rel, True))
        for generics in FUNC_GENERIC_RE.findall(code):
            for param in GENERIC_PARAM_RE.findall(generics.split(":")[0] if ":" in generics else generics):
                declarations.setdefault(param, []).append((rel, True))

        for name in MEMBER_REF_RE.findall(code):
            references.setdefault(name, set()).add(rel)

    # Switch exhaustiveness needs every enum in the module, so it runs after the first pass.
    for rel, code in pending_switches:
        problems.extend(check_switch_exhaustiveness(rel, code, all_enum_cases))

    # Duplicate *top-level* declarations of the same name. Nested types (`CodingKeys`,
    # `Identifier`, a private `Node`) legitimately repeat across files.
    for name, entries in sorted(declarations.items()):
        top_level = sorted({rel for rel, nested in entries if not nested})
        if len(top_level) > 1:
            problems.append(f"duplicate declaration of '{name}' in {', '.join(top_level)}")

    # References to capitalised names that are declared nowhere.
    declared = set(declarations) | KNOWN_EXTERNAL
    # Anything imported wholesale (SwiftUI/SpriteKit/UIKit symbols in the app layer) is skipped.
    app_only_prefixes = ("SK", "UI", "NS", "CG", "CA", "SwiftUI", "SpriteKit", "GameplayKit", "CloudKit", "CK", "OS")
    unknown = {}
    for name, files in references.items():
        if name in declared:
            continue
        if name.startswith(app_only_prefixes) or name.startswith(XCTEST_PREFIX):
            continue
        unknown.setdefault(name, sorted(files))
    for name, files in sorted(unknown.items()):
        problems.append(f"unknown type reference '{name}' used in {', '.join(files[:3])}")

    print(f"Checked {len(swift_files)} Swift files, {len(declarations)} declared type names.")
    if problems:
        print(f"\n{len(problems)} problem(s):")
        for problem in problems:
            print("  " + problem)
        return 1
    print("No structural problems found.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
