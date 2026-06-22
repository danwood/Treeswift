# Regression Fixtures

One minimal Swift repro per fixed Periphery/Treeswift false positive. A fix is not real until its
repro is here AND a scan of it produces the expected (correct) outcome, AND it keeps producing that
outcome after later changes. The supervisor runs these and reports `passing/total`.

Two homes for a fixture:
- **Periphery unit test** (the upstream-contributable form): mirror the author's pattern — add a
  `.swift` fixture under `PeripherySource/periphery/Tests/Fixtures/Sources/RetentionFixtures/` and a
  `func test…()` assertion in `Tests/PeripheryTests/RetentionTest.swift` using `assertReferenced` /
  `assertNotReferenced` / `assertAssignOnlyProperty`.

  ⚠️ **These tests do NOT run via `swift test` in this repo.** The subtree carries Treeswift-specific
  modifications (split `Frontend`/`FrontendLib` targets, removed `CheckUpdateCommand`/
  `ClearCacheCommand`/`VersionCommand`, library-product exports) that make the standalone package
  un-buildable by `swift test`. The tests are written to be VALID and to encode the expected
  behavior for upstream contribution, but their actual execution must happen against a clean
  upstream `danwood/periphery` checkout (`~/code/periphery-dan-private`) where the package builds.
  In THIS repo, verification of these fixes is the end-to-end path below.

- **End-to-end Prodcore probe** (the operative verification here): the supervisor's `forceRemoveAll`
  → build-Prodcore → `build_errors == 0` measurement. This is what proves a fix works in-repo. A
  fix's Periphery unit test is its upstream artifact; the E2E zero-build-errors result is its
  in-repo proof.

## Fixture index

| # | Fix | Shape | Expected | Home / status |
|---|-----|-------|----------|---------------|
| 13 | Nested type as same-parent stored-property type | `struct P { let s: E; enum E { case x } }`, P used | `E` referenced (not unused) | Periphery `RetentionTest` — TODO add |
| 14 | Nested type + its enum cases, parent unused | same as 13 but `P` itself unused | `E` and `E.x` not removed (no orphaned `let s: E`) | E2E repro — TODO add |
| 15 | Sole required class init | `class C { let x: T; init(x:){…} }`, init uncalled | `init` retained (or downgraded), `x` initializable | Periphery `RetentionTest` — TODO add |
| 16 | Custom type as retained Codable property's type | `struct R: Codable { let v: V }; struct V: Codable {…}`, both otherwise unused, `retainCodableProperties:true` | `V` retained (referenced) when `R`'s props retained | ✅ Periphery test written: `RetentionTest.testRetainsCodablePropertyCustomType` + fixture `testRetainsCodablePropertyCustomType.swift` (FixtureStruct200/201). Runs only on upstream checkout; verified in-repo via E2E (build_errors 0). |
| 18 | Synchronized-folder `membershipExceptions` file deleted | file in a `PBXFileSystemSynchronizedRootGroup` pinned via `membershipExceptions`, entirely dead | file SHELLED (kept on disk as import-only), not deleted → no "Build input files cannot be found" | ✅ repro: `F18-synchronized-group-membership/` (`Fixture.swift` + `project.pbxproj.snippet`). **Treeswift-only** bug; verified E2E on R-May. Unit form: `XcodeProjectFileChecker.isSafeToDelete(.../pinned.swift) == false`. |
| 19 | `public` left on extension member after type downgrade | `public struct W<T>` + `extension W where T==Int { public init() }`, W used in-module | type → `internal` AND extension `public init` → `init` (cascade) → compiles | ✅ repro: `F19-public-extension-member/Fixture.swift`. **Treeswift-only**; verified E2E on R-May. Fix: `CodeModificationHelper.cascadePublicStripFromExtensions`. |
| 20 | `fileprivate` not cascaded to extension-method/free-func result | top-level type → `fileprivate`, returned by `extension Other { func … -> [Type] }` and a free func | the func(s) → `fileprivate` (cascade) → compiles (no "method must be declared fileprivate…") | ✅ repro: `F20-fileprivate-func-cascade/Fixture.swift`. **Treeswift-only**; verified E2E on R3. Fix: `CodeModificationHelper.cascadeFileprivateToReferencingFunctions`. |
| 25 | `fileprivate` not cascaded to a member `init`'s parameter | top-level type → `fileprivate`, used as a member `init(onCommit: (Type)->Void)` parameter | the `init` → `fileprivate` (cascade) → compiles (no "initializer must be declared fileprivate…") | ✅ repro: `F25-fileprivate-init-param/Fixture.swift`. **Treeswift-only**; verified E2E on R-May. Fix: same function, now matching `func`\|`init` + `insertFileprivateBeforeDecl`. |
| 26 | empty-ancestor promotion deletes a type still referenced as a type | a type whose members are ALL flagged (props redundant-acc + one unused init), still named by a sibling's `var x: Type?` / a parameter | the type is KEPT (not deleted) even though emptied → no "cannot find type" | ✅ repro: `F26-empty-ancestor-referenced-type/Fixture.swift`. **Treeswift-only**; Periphery never flags the struct, only its members. Verified E2E on R3. Fix: `CodeModificationHelper.isReferencedAsTypeBySurvivingDeclaration` guard in `findHighestEmptyAncestor`. |

## F18/F19/F20 are Treeswift removal-logic bugs (not Periphery analysis)

Unlike fixtures 13–16 (Periphery analysis gaps, whose canonical home is a `RetentionTest` unit
test), **F18/F19/F20 are bugs in Treeswift's own code-modification logic** — they live in
`Treeswift/Core/Utilities/XcodeProjectFileChecker.swift` and
`Treeswift/Core/Operations/CodeModificationHelper.swift`. So:

- Their repro is an **E2E Prodcore probe** (the operative in-repo proof): on the baseline that
  surfaced them, `forceRemoveAll` → build → `build_errors == 0`. Already achieved (R-May for F18/F19,
  R3 for F20).
- The `Fixture.swift` files here are the **minimal source shapes** + the exact expected outcome, so
  the bug can be re-triggered deliberately. They are not wired to a runner because **Treeswift has no
  XCTest target yet** (the fixed functions are `private static`). If/when a Treeswift test target is
  added, the unit-level assertions noted in each fixture header are the tests to write
  (`XcodeProjectFileChecker.isSafeToDelete` for F18; a small `computeBatchModifications` round-trip
  for F19/F20).
- They are **not** upstream-Periphery contributions. The *deeper* cause of F19/F20 (Periphery emits a
  redundant-accessibility warning on a type without coupling it to the access of its
  extension-members / referencing-funcs) could be addressed upstream in `danwood/periphery`, which
  would then need its own `RetentionTest`/`AccessibilityTest`; that is a separate, optional follow-up.

## Building these out

Priority order: 16 (just fixed, most fragile — a custom-type Codable property), then 14 (the
removal-cascade case that caused the empty-enum re-orphan), then 13 and 15. Each upstream fixture
also discharges the "owed Periphery test" noted in `README_Treeswift.md` P11–P13.

For F18/F19/F20: the highest-value next step is a **Treeswift XCTest target** so the cascade helpers
and `XcodeProjectFileChecker` get true unit coverage (they are pure, fast, deterministic functions —
ideal for unit tests). Until then the `Fixture.swift` shapes + the E2E baseline results are the
regression record.
