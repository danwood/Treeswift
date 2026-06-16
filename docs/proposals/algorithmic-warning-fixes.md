# Algorithmic Fixes for Currently-Unremovable Warnings

**Status: design proposal**, except Part 3 (**unused function parameters**) which is now
**implemented and shipped** — see its verdict. Treeswift still refuses to auto-fix two annotation
kinds — `assignOnlyProperty` and `redundantProtocol` — because `ScanResult.Annotation.canRemoveCode`
returns `false` for both (`Treeswift/Core/Operations/PeripheryKit-extensions.swift`). Unused function
parameters (which arrive with the `.unused` annotation, kind `.varParameter`) were previously gated
out of removal by the missing-source-range check; they are now fixed in place by renaming the binding
to `_`. This document analyzes how a **future Treeswift could fix the remaining two algorithmically
(no LLM)**, using the real Prodcore cases and examples lifted from Periphery's own test suite. Where a
purely algorithmic fix is unsafe or under-determined, that is called out explicitly as **"needs
human/LLM judgment."**

This is Concern D (Treeswift implementation) design work. See
[`../../TREESWIFT-PROJECT-MAP.md`](../../TREESWIFT-PROJECT-MAP.md).

> Why these are hard: unlike `.unused` (delete the declaration's source range) or
> `redundantInternalAccessibility` (rewrite one access keyword), a correct fix for these two is
> **not a single-line edit in a single place**. It requires reasoning about other declarations on
> the same line, assignment sites elsewhere in the type, and the intended semantics of the property.

---

## Part 1 — `assignOnlyProperty`

A property Periphery flags `assignOnlyProperty` is **written but never read**. The naive "fix" —
delete the property declaration — is wrong in most real cases because the *writes* remain
(`self.x = …` in init/methods) and now reference a nonexistent member. So the fix is really:
**remove the property AND all of its now-dead write sites**, or decide the property must stay.

### Taxonomy of cases (from Periphery's `testSimplePropertyAssignedButNeverRead` fixture)

The Periphery fixture `FixtureClass70` enumerates the shapes the algorithm must distinguish:

| Shape | Example | Periphery verdict | Algorithmic fix difficulty |
|-------|---------|-------------------|----------------------------|
| Simple unread | `var simpleUnreadVar: String` assigned in init + method | assignOnly | **Tractable** — remove decl + all assignment statements |
| Static unread | `static var simpleStaticUnreadVar: String!` | assignOnly | Tractable — same, but assignments are `Type.x = …` |
| Shadowed | `var simpleUnreadShadowedVar` also a param name | assignOnly | Tractable, but must NOT touch the local param shadow |
| Assigned multiple times | two `x = …` lines | assignOnly | Tractable — remove every assignment site |
| Complex (`willSet`/`didSet`) | `complexUnreadVar1` | NOT assignOnly | n/a — Periphery excludes it |
| Complex (`get`/`set`) | `complexUnreadVar2` | NOT assignOnly | n/a — excluded |
| Property-wrapped | `@Wrapped var wrappedProperty` | NOT assignOnly | n/a — excluded |
| `// periphery:ignore` | `ignoredSimpleUnreadVar` | NOT reported | n/a |
| **`weak` back-reference** (case W) | `weak var hostingView: HostView?` | **reported** assignOnly | ❌ **refuse** — `weak` is an intent marker (non-owning lifecycle hook); detectable, never auto-remove |
| **`private(set)` / asymmetric access** (case P) | `private(set) var highlightCount: Int` | **reported** assignOnly | ❌ **refuse** — read-only API surface; detectable, never auto-remove |

So Periphery already filters out the genuinely hard *storage* shapes (computed, observed, wrapped),
but it still reports `weak` and `private(set)` stored `var`s — two **intent-bearing** shapes the
Prodcore evidence surfaced (cases W and P below). What reaches Treeswift as `assignOnlyProperty` is
therefore a **plain stored `var`/`static var`**, *which may still carry `weak` or asymmetric
access* — those two must be detected and excluded before anything is removed. With those excluded,
three sub-problems remain hard:

### Sub-problem A — removing the write sites

Removing `var x: String` requires deleting every `x = …` / `self.x = …` / `Type.x = …` statement.
Periphery's source graph records these as references to the property's **setter accessor USR**.
Algorithm sketch:

1. From the `assignOnlyProperty` declaration, collect its `functionAccessorSetter` child.
2. For each non-retained reference to that setter, map `reference.location` back to a source line.
3. Delete each such statement — but only if the statement is a *pure assignment*
   (`lhs = rhs` where `lhs` is exactly this property and `rhs` has no side effects).

**Where it gets hard / needs judgment:**
- `x = sideEffectingCall()` — deleting the line drops the side effect. Detecting "rhs has side
  effects" is non-trivial syntactically; a conservative algorithm must KEEP the rhs (rewrite to
  `_ = sideEffectingCall()`) or refuse. **Borderline algorithmic; safest is to refuse and flag.**
- `x = y = z` chained assignment, or `x += …` (compound) — compound ops read-then-write, so they
  aren't pure assign-only anyway, but the algorithm must recognize and not mangle them.

### Sub-problem B — multi-binding and destructured declarations (the genuinely hard one)

From Periphery's `testRetainsAssignOnlyPropertyTypes` (`FixtureClass123`):

```swift
var (retainedDestructuredPropertyA, notRetainedDestructuredPropertyB): (CustomType, Swift.String) = (.init(), "2")
var retainedMultipleBindingPropertyA: CustomType?, notRetainedMultipleBindingPropertyB: Int?
```

If only `notRetainedDestructuredPropertyB` is assign-only, you **cannot delete the declaration** —
`retainedDestructuredPropertyA` shares it. The fix must *rewrite* the binding to drop one element
of the tuple pattern (and the matching tuple initializer element), or refuse. This is real
syntax-tree surgery (SwiftSyntax), not line deletion.

- **Tuple-pattern binding**: rewrite `var (a, b): (T, U) = (x, y)` → `var a: T = x`. Algorithmically
  doable with SwiftSyntax (remove the pattern element + the corresponding initializer element +
  the type annotation element), but must keep all three in sync. **Tractable but involved.**
- **Comma-separated multiple binding**: `var a: T?, b: Int?` → `var a: T?` — remove the one binding.
  **Tractable with SwiftSyntax.**

### Sub-problem C — type-driven retention (already handled by config, not removal)

`FixtureClass123` also shows Periphery *retaining* assign-only properties by type: `AnyCancellable`,
`Set<AnyCancellable>`, `[AnyCancellable]`, `NSKeyValueObservation`, and user-configured types. These
are never reported, so Treeswift never sees them. No action needed — but the doc notes it so a
future implementer doesn't "re-discover" the Combine cancellable case.

### Verdict for `assignOnlyProperty`

| Case | Algorithmic? |
|------|--------------|
| Plain stored `var`/`static var`, **symmetric access**, **not `weak`/`unowned`**, assignments are pure `x = literal/simpleExpr` | ✅ Yes — delete decl + delete each pure-assignment statement |
| Assignment rhs is a function call (`x = f(...)`), e.g. `playheadFrame = ticksToFrames(tick)` | ⚠️ Partial — rewrite to `_ = f(...)` or refuse; proving the call is side-effect-free is the hard part |
| Assignment rhs has side effects | ⚠️ Partial — rewrite to `_ = rhs` or refuse; detecting side effects safely is hard |
| Tuple-pattern / multiple-binding where only some bindings are assign-only | ⚠️ Involved — SwiftSyntax pattern surgery; doable but careful |
| **`weak`/`unowned` stored var** (case W — `Coordinator.hostingView`) | ❌ **Refuse (detectable)** — non-owning lifecycle hook; "never read" is expected. Read `weak`/`unowned` off the decl and exclude |
| **`private(set)` / setter-access < getter-access** (case P — `SharedWithYouService.highlightCount`) | ❌ **Refuse (detectable)** — read-only API surface; reads are external. Read the asymmetric access off the decl and exclude |
| "Is this property otherwise *intended* to be write-only (debugging hook, KVO sink not caught by `weak`/`private(set)`)?" | ❌ **Needs human/LLM judgment** — residual after W/P are excluded; Periphery's type-retain list is a crude proxy |

**Recommended first implementation**: handle ONLY the safe subset — a plain single-binding stored
`var` that is (a) **not** `weak`/`unowned`, (b) of **symmetric accessibility** (no `private(set)` or
other setter-narrower-than-getter), and (c) whose every setter reference is a pure assignment
statement (rhs is a literal or a side-effect-free expression by a conservative whitelist; a bare
function-call rhs does NOT qualify). Refuse (leave as today) for everything else, surfacing it for
review. This makes `canRemoveCode` return true for that subset only. Always key edits off the
**declaration USR / SwiftSyntax node**, never the property name (see the USR-disambiguation gotcha:
`FinalStatistics.throughputPerSecond` collides by name with an unrelated computed var).

From the Prodcore evidence, that safe subset is exactly: `AudioFileLoader.runtimeFormat` and the two
`FinalStatistics` fields (3 of the 6 distinct cases). `TickClock.playheadFrame` is the
function-call-rhs ⚠️ case; `Coordinator.hostingView` (W) and `SharedWithYouService.highlightCount`
(P) are the two detectable ❌ refusals.

---

## Part 2 — `redundantProtocol`

A `redundantProtocol` is a protocol that is only ever used as a marker/inheritance and could be
collapsed — Periphery reports the protocol plus the references that should be rewritten to the
inherited type(s). Treeswift currently refuses (`canRemoveCode` → false).

The "fix" is not a deletion but a **multi-site rewrite**: replace each conformance/usage of the
redundant protocol with its inherited protocol(s), then delete the protocol declaration. The
`ScanResult` annotation already carries `references` and `inherited` names.

**Where it gets hard / needs judgment:**
- Every conformer `T: RedundantProto` must become `T: Inherited1, Inherited2…` — straightforward
  text rewrite IF the inherited list is non-empty and the conformance clause is simple.
- Existential / generic uses (`func f(_ x: any RedundantProto)`, `where X: RedundantProto`) must all
  be rewritten too — found via the reported references, but each call site is a different syntactic
  context. **Tractable but broad; high blast radius.**
- If the protocol adds documentation, default implementations, or is part of a public API surface,
  collapsing it changes the published API. **Needs human/LLM judgment** on whether the collapse is
  desirable, even when mechanically safe.

### Verdict for `redundantProtocol`

| Case | Algorithmic? |
|------|--------------|
| Internal protocol, simple `: Proto` conformances, non-empty inherited list | ✅ Mostly — rewrite conformance clauses + delete decl, using reported references |
| Existential/generic-constraint uses scattered across files | ⚠️ Involved — many distinct rewrite contexts; needs robust SwiftSyntax handling |
| Public API protocol | ❌ Needs human/LLM judgment (API design decision, not a mechanical fix) |

---

## Part 3 — unused function parameters

A parameter that the function body never reads is reported by Periphery with the **`.unused`**
annotation (so it appears in the `unused` bucket of the scan summary, not a bucket of its own).
Unlike an unused *declaration*, Treeswift does not remove it. The gate is **not** the annotation
type — it is the source-range check shared by all `.unused` removals:

```swift
// PeripheryKit-extensions.swift
case .unused:
    hasFullRange || isImport
// UnusedDependencyAnalyzer.swift
let hasFullRange = location.endLine != nil && location.endColumn != nil
```

Periphery emits a parameter's location as a **point** (line/column of the parameter name, with no
`endLine`/`endColumn`), so `hasFullRange` is `false`, `canRemoveCode` returns `false`, and
`forceRemoveAll` reports the finding as **0 deletable**. This is why a Prodcore scan can show, say,
47 `unused` findings of which `forceRemoveAll` removes zero — they are all parameters.

### Why this is correct to refuse (today)

Even given a full range, deleting a parameter is **not** a self-contained edit the way deleting a
dead declaration is. A correct fix must also:

1. Remove the corresponding **argument at every call site** (Periphery's reference graph records
   calls to the function, not to the individual parameter, so the argument position must be
   recovered from the signature + SwiftSyntax, not from a reference USR).
2. Respect **signature-locked** contexts where the parameter cannot be removed at all and the only
   valid fix is renaming it to `_`:
   - **protocol witnesses** — the function satisfies a protocol requirement whose signature is fixed
     (e.g. `init(from:)`, delegate methods);
   - **overrides** — `override func` must match the superclass signature;
   - **`@objc` / selector-referenced** methods, and functions passed as values where the full
     parameter list is part of the type;
   - **closures/handlers** assigned to a typed function value.

So the taxonomy of fixes is:

| Shape | Fix | Algorithmic? |
|-------|-----|--------------|
| `private`/`fileprivate` free function, param genuinely unused, few call sites | remove param + arguments, OR rename to `_` | ⚠️ Tractable for rename-to-`_`; argument removal needs call-site rewrites |
| Protocol witness / `override` / `@objc` / typed-function-value | **rename to `_`** (only legal fix; never remove) | ✅ Safe single-token rewrite, no call-site changes |
| Param actually used via a wrapper / KVO / reflection Periphery can't see | leave it | ❌ Needs human/LLM judgment |

### Verdict for unused parameters — IMPLEMENTED

The universally-safe fix is **rename to `_`**: it silences the warning, never touches an external
signature, and requires no call-site edits. This is now shipped:

- **Gate** — `ScanResult.Annotation.canRemoveCode` takes a `kind:` argument and returns `true` for
  `.unused` + `.varParameter` (a point location is sufficient; no full range needed). All five call
  sites pass `declaration.kind` (`PeripheryKit-extensions.swift`, plus `FileNode+CodeRemoval`,
  `UnusedDependencyAnalyzer`, `PeripheryTreeView`, `DetailPeripheryWarningsSection`).
- **Rewrite** — `CodeModificationHelper.renameParameterBinding(in:bindingName:column:)` is a
  column-anchored, line-based token rewrite (house style — no SwiftSyntax). It reads the binding-name
  token at the reported column, asserts it equals `declaration.name` (a drifted column → no-op ghost,
  never a corrupted signature), and applies one of three forms by inspecting the token to its left:
  `for name:` → `for _:`; `_ name:` → `_:`; `name:` (label == binding) → `name _:`. Wired as a
  `declaration.kind == .varParameter` branch in `computeBatchModifications`, before the full-delete
  `else`, committed through `applyAccessControlRewrite` (no-op rejection + undo tracking for free).
- **Verified** — end-to-end on Prodcore as corpus: 47 `.varParameter` findings renamed across 30
  files, Prodcore **builds clean**, `unused` count 47 → 0, all call sites intact, `assignOnlyProperty`
  untouched. Algorithm self-check: `Prodcore-cleanup/fixtures/renameParameterBinding-selfcheck.swift`
  (run with `swift`; covers all three forms + the no-op guard).

*Removing* the parameter entirely (call-site argument deletion) remains the involved case and is NOT
implemented — the rename-to-`_` fix is correct and sufficient for every signature-locked context
(protocol witness / override / `@objc` / typed function value), so removal was not needed.

---

## Prodcore evidence — the enumerated `assignOnlyProperty` cases (2026-06-11)

> **`assignOnlyProperty` items are effectively invisible in Treeswift's current API/UI.** Because
> `canRemoveCode` returns `false` for them, the removal preview reports them as `deletable: 0,
> nonDeletable: 0` (filtered out before counting), and they carry no `usageBadge` in `files-tree`,
> nor do they appear in the `orphans`/`shared`/`unattached` display categories. They show up ONLY in
> the aggregate `summary` count. **Surfacing them is a prerequisite for fixing them** — the future
> implementation must first expose assignOnly items with their locations (a dedicated results
> category or a per-file badge), independent of whether removal is automated.

**They were enumerated out-of-band** during the git-history convergence experiment by reading the
declaration USRs straight out of Treeswift's scan-cache JSON
(`ScanCache/scan-cache-<UUID>.json` → every object with `"annotationKind":"assignOnlyProperty"`
carries a `declarationUSR`) and resolving each USR to source by grep. The four historical baselines
(R5/R4/R-May/R3) and the converged R3 tree together yield a **small, stable, overlapping** set — the
same handful of properties recur, because they are long-lived in the codebase, not baseline-specific.

### The complete distinct set (union across baselines)

| Property (type.member) | Declaration | Write site(s) | Shape | Verdict |
|------------------------|-------------|---------------|-------|---------|
| `AudioFileLoader.runtimeFormat` | `private var runtimeFormat: AVAudioFormat?` | `self.runtimeFormat = format` | single stored `var`, one **pure** assignment | ✅ **safe subset** — delete decl + the one assignment |
| `ImportResult.FinalStatistics.averageProcessingTime` | `var averageProcessingTime: TimeInterval = 0` (struct field) | `statistics.averageProcessingTime = duration / Double(rows)` | stored `var`, **pure-arithmetic** assignment via an instance | ✅ **safe subset** — but see USR-disambiguation note below |
| `ImportResult.FinalStatistics.throughputPerSecond` | `var throughputPerSecond: Double = 0` (struct field) | `statistics.throughputPerSecond = Double(rows) / duration` | same as above | ✅ **safe subset** — same USR-disambiguation note |
| `TickClock.playheadFrame` | `private var playheadFrame: AVAudioFramePosition = 0` | `playheadFrame = ticksToFrames(ticks: tick)` | stored `var`, assignment **rhs is a function call** | ⚠️ **borderline** — `ticksToFrames` is a pure conversion here, but proving "no side effects" syntactically is the hard part; refuse OR rewrite to `_ = ticksToFrames(...)` |
| `PathBarSegmentButton.Coordinator.hostingView` | **`weak var hostingView: PathBarSegmentHostView?`** | `coordinator.hostingView = host` | **`weak`** back-reference, written then never read | ❌ **intent — do NOT auto-remove** (see new case W) |
| `SharedWithYouService.highlightCount` | **`private(set) var highlightCount: Int = 0`** | `self.highlightCount = count` | **`private(set)`** read-only-public property | ❌ **intent — do NOT auto-remove** (see new case P) |

Per-baseline counts: R5 = 5 (rows 1–3 + hostingView + highlightCount), R4 ≈ R5 (days apart,
codebase identical for these), R-May = 3 (rows 1–3 only), R3 pristine = 2, R3 converged = 4 (rows
1–3 + `TickClock.playheadFrame`, which only surfaces after surrounding dead code is removed —
a reminder that the assignOnly set is **second-order-sensitive**: it grows/shrinks as `.unused`
removal changes what is reachable, so it must be re-enumerated after each pass, not once).

### New cases this evidence adds to the taxonomy

The `FixtureClass70`/`FixtureClass123` shapes (Part 1) cover the *storage* mechanics, but the real
Prodcore set surfaced two **intent markers that are themselves syntactically detectable** and that
the algorithm should treat as automatic "refuse + surface", not as a judgment call left to a human
to notice later:

- **Case W — `weak var` written-but-unread (`Coordinator.hostingView`).** A `weak` property is almost
  never genuinely dead: it is a deliberately-non-owning back-reference (here a Coordinator holding a
  weak handle to its hosting view to avoid a retain cycle). "Never read" is expected for a weak hook
  whose only job is lifecycle/identity. **Detect `weak` on the declaration → never auto-remove**; if
  removed, the assignment site (`coordinator.hostingView = host`) and the ownership intent both
  vanish silently. This is a hard NO, cheaply detectable, and should be promoted to a first-class
  exclusion (ideally in Periphery, like its existing `AnyCancellable` type-retain list — `weak`
  assign-only properties should arguably not be reported at all).

- **Case P — `private(set) var` written-but-unread (`SharedWithYouService.highlightCount`).** A
  `private(set)` property is a **public/internal read-only API surface**: writable only inside the
  type, readable from outside. Periphery sees no *in-module* reads and flags it, but the property
  exists precisely so *external* code (or SwiftUI/KVO/tests) can read it. Removing it deletes
  intended API. **Detect a `private(set)` (or any asymmetric setter access narrower than the getter)
  → refuse + surface**, never auto-remove. (Compare the existing simple `var simpleUnreadVar` in
  `FixtureClass70`, which has *symmetric* access and no API-surface intent — that one IS in the safe
  subset.)

Both W and P sharpen Part-1's "❌ needs human/LLM judgment" row into **concrete, detectable
discriminators**: `weak` and `private(set)`/asymmetric-access are mechanical signals the algorithm
can read off the declaration and use to refuse *without* needing to infer intent. The safe-subset
rule should therefore be tightened to: *plain stored single-binding `var` with **symmetric**
accessibility, **not** `weak`/`unowned`, whose every setter reference is a pure assignment.*

### USR-disambiguation note (a real gotcha)

`ImportResult.FinalStatistics.throughputPerSecond` (the assign-only **stored** field) coexists in the
same file (`Shared/CoreData/Products/ProductImportModels.swift`) with an unrelated **computed**
`var throughputPerSecond: Double { … }` on a *different* type. A name-based fix would corrupt the
wrong declaration. The algorithm must key every edit off the **declaration USR / SwiftSyntax node
identity**, never the property name — Periphery already gives the USR in the scan result, so this is
straightforward but must not be skipped.

---

## Summary recommendation

1. **`assignOnlyProperty`**: implement the *safe subset* algorithmically (single-binding stored
   `var`, **symmetric access, not `weak`/`unowned`**, pure-assignment write sites). Flip
   `canRemoveCode` for that subset only; refuse + surface the rest. Reuse Periphery's setter-reference
   graph to find write sites; use SwiftSyntax for the declaration + statement edits, keyed off the
   **USR** (never the name). **First, cheaply exclude the two detectable intent markers the Prodcore
   evidence surfaced — `weak`/`unowned` (case W) and `private(set)`/asymmetric access (case P)** —
   ideally upstream in Periphery so they are never reported (like its `AnyCancellable` type-retain
   list). Multi-binding, function-call-rhs, and side-effecting-rhs cases are involved but eventually
   tractable; residual *intent* questions are not — leave those to review.
2. **`redundantProtocol`**: lower priority; mechanically tractable for the internal/simple case but
   high blast radius and entangled with API-design intent. Defer until `assignOnlyProperty` lands.
3. **Unused parameters** (reported as `.unused`, gated out by the missing source range): implement
   the *rename-to-`_`* fix as the safe default — a single-token rewrite that needs no call-site
   changes and is the only legal fix for protocol-witness/override/`@objc`/typed-value contexts.
   Outright *removal* of the parameter (with call-site argument deletion) is the involved case; defer
   it and refuse the signature-locked shapes. This requires either supplying a full source range for
   parameter findings or special-casing the parameter declaration kind in `canRemoveCode`.
4. Anything marked **❌ needs human/LLM judgment** above should remain non-auto-fixable and be
   presented to the user, never silently removed — consistent with the zero-false-positive rule.
