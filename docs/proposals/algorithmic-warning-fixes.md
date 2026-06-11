# Algorithmic Fixes for Currently-Unremovable Warnings

**Status: design proposal.** Treeswift today refuses to auto-fix two Periphery annotation kinds —
`assignOnlyProperty` and `redundantProtocol` — because `ScanResult.Annotation.canRemoveCode` returns
`false` for both (`Treeswift/Core/Operations/PeripheryKit-extensions.swift`). This document analyzes
how a **future Treeswift could fix them algorithmically (no LLM)**, using the real Prodcore cases and
examples lifted from Periphery's own test suite. Where a purely algorithmic fix is unsafe or
under-determined, that is called out explicitly as **"needs human/LLM judgment."**

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

So Periphery already filters out the genuinely hard storage shapes (computed, observed, wrapped).
What reaches Treeswift as `assignOnlyProperty` is always a **plain stored `var`** (or `static var`).
That narrows the problem — but three sub-problems remain hard:

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
| Plain stored `var`/`static var`, assignments are pure `x = literal/simpleExpr` | ✅ Yes — delete decl + delete each pure-assignment statement |
| Assignment rhs has side effects | ⚠️ Partial — rewrite to `_ = rhs` or refuse; detecting side effects safely is hard |
| Tuple-pattern / multiple-binding where only some bindings are assign-only | ⚠️ Involved — SwiftSyntax pattern surgery; doable but careful |
| "Is this property *intended* to be write-only (e.g. debugging hook, KVO sink, API surface)?" | ❌ **Needs human/LLM judgment** — the algorithm can't know intent; Periphery's type-retain list is a crude proxy |

**Recommended first implementation**: handle ONLY the safe subset — a plain single-binding stored
`var` whose every setter reference is a pure assignment statement (rhs is a literal or a
side-effect-free expression by a conservative whitelist). Refuse (leave as today) for everything
else, surfacing it for review. This makes `canRemoveCode` return true for that subset only.

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

## Prodcore evidence — the current 5 `assignOnlyProperty` cases

A clean Prodcore scan flags **5** `assignOnlyProperty` items (stable across scans; see the
convergence ledger). A notable finding emerged while trying to enumerate them:

> **`assignOnlyProperty` items are effectively invisible in Treeswift's current API/UI.** Because
> `canRemoveCode` returns `false` for them, the removal preview reports them as `deletable: 0,
> nonDeletable: 0` (filtered out before counting), and they carry no `usageBadge` in `files-tree`,
> nor do they appear in the `orphans`/`shared`/`unattached` display categories. They show up ONLY in
> the aggregate `summary` count (`assignOnlyProperty: 5`). So a user cannot currently even navigate
> to them. **Surfacing them is a prerequisite for fixing them** — the future implementation must
> first expose assignOnly items with their locations (a dedicated results category or a per-file
> badge), independent of whether removal is automated.

Because the API does not expose their locations, the per-item classification below is left as the
first task of any future assignOnly work: run the scan, surface the 5 items with file+line, then
classify each against the Part-1 taxonomy (single stored `var` with pure-assignment writes =
auto-fixable subset; multi-binding/destructured or side-effecting-rhs = involved; "intended
write-only" = human/LLM judgment). The Periphery `FixtureClass70` / `FixtureClass123` cases above
already cover every shape the 5 can take.

---

## Summary recommendation

1. **`assignOnlyProperty`**: implement the *safe subset* algorithmically (single-binding stored
   `var`, pure-assignment write sites). Flip `canRemoveCode` for that subset only; refuse + surface
   the rest. Reuse Periphery's setter-reference graph to find write sites; use SwiftSyntax for the
   declaration + statement edits. Multi-binding and side-effecting-rhs cases are involved but
   eventually tractable; *intent* questions are not — leave those to review.
2. **`redundantProtocol`**: lower priority; mechanically tractable for the internal/simple case but
   high blast radius and entangled with API-design intent. Defer until `assignOnlyProperty` lands.
3. Anything marked **❌ needs human/LLM judgment** above should remain non-auto-fixable and be
   presented to the user, never silently removed — consistent with the zero-false-positive rule.
