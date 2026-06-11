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

## Building these out

Priority order: 16 (just fixed, most fragile — a custom-type Codable property), then 14 (the
removal-cascade case that caused the empty-enum re-orphan), then 13 and 15. Each upstream fixture
also discharges the "owed Periphery test" noted in `README_Treeswift.md` P11–P13.
