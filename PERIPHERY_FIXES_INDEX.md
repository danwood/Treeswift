# Periphery Fixes — Master Index

**Single index for every Periphery false-positive / analysis fix.** The detail lives in three
companion docs; this table is the map between them so the knowledge is not scattered:

- **Issue #** → [`PeripheryIssues.md`](PeripheryIssues.md) — the false-positive *catalog*
  (symptom / example / root cause / fix), problem-first.
- **P #** → [`PeripherySource/periphery/README_Treeswift.md`](PeripherySource/periphery/README_Treeswift.md)
  — the subtree *change log* + upstream-contribution plan (which mutator, which branch).
- **Fixture** → [`Prodcore-cleanup/fixtures/`](Prodcore-cleanup/fixtures/README.md) — regression repro.
- **Convergence metrics** → [`Prodcore-cleanup/convergence-ledger.md`](Prodcore-cleanup/convergence-ledger.md).

Status legend: ✅ fixed & verified · 🧪 fix in place, regression fixture still owed ·
⬆️ already upstream (in `danwood/periphery`) · ⏳ pending upstream push.

| Issue | P# | Title (short) | Mutator / file changed | Upstream | Fixture | Status |
|------:|----|---------------|------------------------|----------|---------|--------|
| 1 | P1 | `@Observable` wrong source positions for synthesized accessors | `ObservableMacroRetainer` + `SourceGraphMutatorRunner` | ⏳ | — | 🧪 |
| 2 | P2 | `let`-binding false positives in assignOnly detection | `DeclarationSyntaxVisitor`, `Declaration`, `SwiftIndexer`, `AssignOnlyPropertyReferenceEliminator` | ⏳ | — | 🧪 |
| 3 | P4 | Protocol unused when used only via conformance | `ProtocolConformanceRetainer` (new) | ⏳ | — | 🧪 |
| 4 | P5 | Protocol conformance extensions wrongly removed | `ScanResultBuilder` (+ Treeswift `removeEmptyContainers`, `findHighestEmptyAncestor`) | ⏳ | — | 🧪 |
| 5 | P6 | Private members called only within same type removed (stored-property case) | `UsedDeclarationMarker` (accessor → property) | ⏳ | — | 🧪 |
| 6 | — | `redundantPublicAccessibility` strips `public` from protocol-extension members | `RedundantPublic…` analysis (Treeswift-side guard) | — | — | 🧪 |
| 7 | P7 | Nested types used only in sibling method signatures removed | `UsedDeclarationMarker` (returnType/parameterType walk) | ⏳ | — | 🧪 |
| 8 | P9 | Stored `let` with no external reads removed, orphaning `self.x = x` | `AssignOnlyPropertyReferenceEliminator` (`isLetPropertyWithInitBodyAssignment`) | ⏳ | — | 🧪 |
| 9 | — | Stored properties made `private` despite cross-file reads | `isReferencedOutsideFile` (accessor-child walk) | ⏳ | — | 🧪 |
| 10 | — | `redundantPublicAccessibility` strips `public` from protocol-requirement members | `markExplicitPublicDescendentDeclarations` (skip witnesses) | ⏳ | — | 🧪 |
| 11 | P7+P8 | Nested type removed while parent kept (orphaned refs) | `UsedDeclarationMarker` (function→parent propagation) + Treeswift `isNestedTypeWithKeptParent` | ⏳ | — | 🧪 |
| 12 | P10 | Ghost `redundantInternalAccessibility`, no source range, `static let` in `actor` | `DeclarationSyntaxVisitor` (secondary result at node position) | ⏳ | — | 🧪 |
| 13 | (upstream `master` d763b7a) | Nested type as **same-parent** stored-property type removed | `UsedDeclarationMarker` (Issue-13 nested-by-name walk) | ⬆️ | TODO | 🧪 |
| 14 | **P11** | Nested type **+ enum cases** removed when parent also unused | `AssignOnlyPropertyReferenceEliminator` (Issue-14, narrow + descendants) | ⏳ | TODO | 🧪 |
| 15 | **P12** | Sole class `init` removed → stored props un-initializable | `AssignOnlyPropertyReferenceEliminator` (`isRequiredClassInit`) | ⏳ | TODO | 🧪 |
| 16 | **P13** | Custom type used only as a **retained Codable property's** type removed | `CodablePropertyRetainer` (`retainDeclaredType`) | ⏳ | ✅ `RetentionTest.testRetainsCodablePropertyCustomType` | ✅ |

## Notes

- **Issue # ≠ P #.** The two schemes were created independently and at different times; some issues
  span multiple P-changes (e.g. 11 → P7+P8) and some P-changes have no standalone catalog entry.
  This table is the authoritative cross-walk. Keep it updated whenever a new issue or P-fix lands.
- **"⬆️ upstream" vs "⏳ pending":** only Issue 13 is already merged to `danwood/periphery` master.
  Everything marked ⏳ is applied locally in the subtree and still owes an upstream push per the
  branch workflow in `README_Treeswift.md`.
- **Fixtures:** only Issue 16 has a written regression test. 13/14/15 are owed; the rest (1–12)
  predate this index and rely on the end-to-end Prodcore probe for coverage.
- **Verification in-repo** is the convergence ledger's `build_errors == 0` (a full `forceRemoveAll`
  of Prodcore builds clean). Periphery unit tests do not run via `swift test` in this repo (subtree
  integration mods break the standalone build); they are written for the upstream checkout.

## Where to add the next one

1. Catalog the symptom in `PeripheryIssues.md` (next Issue #).
2. If it's an analysis change, log it in `README_Treeswift.md` (next P #) with the upstream branch.
3. Write a regression fixture (`Prodcore-cleanup/fixtures/`) and, for analysis fixes, a
   `RetentionTest` + fixture mirroring the author's pattern.
4. **Add the row here.** This file is the index of record.
