// Self-check for CodeModificationHelper.renameParameterBinding (unused-parameter -> `_`).
// Treeswift has no XCTest target, so this is a standalone runnable check: `swift this-file.swift`.
// It mirrors the private helper's logic exactly; keep the two in sync if the algorithm changes.
// Asserts the three external-label forms plus a multi-line own-line parameter.
// ponytail: column-anchored, ASCII identifiers (matches all real Prodcore param findings).

import Foundation

func renameParameterBinding(in line: String, bindingName: String, column: Int) -> String {
	let chars = Array(line)
	let start = column - 1
	guard start >= 0, start < chars.count else { return line }
	var end = start
	let isIdent: (Character) -> Bool = { $0 == "_" || $0.isLetter || $0.isNumber }
	while end < chars.count, isIdent(chars[end]) {
		end += 1
	}
	guard String(chars[start ..< end]) == bindingName else { return line }
	var j = start
	while j > 0, chars[j - 1] == " " {
		j -= 1
	}
	var prevStart = j
	while prevStart > 0, isIdent(chars[prevStart - 1]) {
		prevStart -= 1
	}
	let prevToken = String(chars[prevStart ..< j])
	let prefix = String(chars[0 ..< start])
	let suffix = String(chars[end...])
	if prevToken == "_" {
		return String(chars[0 ..< prevStart]) + "_" + suffix
	} else if prevToken.isEmpty {
		return prefix + bindingName + " _" + suffix
	} else {
		return prefix + "_" + suffix
	}
}

func col(_ line: String, _ name: String) -> Int {
	line.distance(from: line.startIndex, to: line.range(of: name)!.lowerBound) + 1
}

let cases: [(String, String, String)] = [
	(
		"    private func sequenceDisplayModels(for production: Production) -> [X] {",
		"production",
		"    private func sequenceDisplayModels(for _: Production) -> [X] {"
	),
	(
		"    private func handlePasswordCredential(_ credential: ASPasswordCredential) {",
		"credential",
		"    private func handlePasswordCredential(_: ASPasswordCredential) {"
	),
	(
		"    private func addProgramVersionByID(programID: UUID, versionID: UUID, at index: Int) async {",
		"programID",
		"    private func addProgramVersionByID(programID _: UUID, versionID: UUID, at index: Int) async {"
	),
	(
		"    init(from organization: Organization, context: NSManagedObjectContext) {",
		"context",
		"    init(from organization: Organization, context _: NSManagedObjectContext) {"
	),
	("        anchor: Int64,", "anchor", "        anchor _: Int64,"),
	// drifted column / wrong name -> no-op (never corrupt a signature)
	("    func f(real: Int) {", "ghost", "    func f(real: Int) {")
]

var ok = true
for (line, name, exp) in cases {
	let column = name == "ghost" ? 12 : col(line, name)
	let got = renameParameterBinding(in: line, bindingName: name, column: column)
	if got != exp { ok = false; print("FAIL \(name): \(got)\n     exp: \(exp)") }
}

print(ok ? "renameParameterBinding self-check: ALL PASS" : "renameParameterBinding self-check: FAILURES")
assert(ok)
