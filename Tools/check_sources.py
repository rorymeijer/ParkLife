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

    for path in swift_files:
        rel = os.path.relpath(path, ROOT)
        with open(path, encoding="utf-8") as handle:
            text = handle.read()
        code = strip_code(text)
        problems.extend(check_balance(rel, code))

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
