# Periphery operation — status & roadmap

**Living document.** Update when accomplishments land. Diagram: [periphery-branch-stack.svg](periphery-branch-stack.svg). Subtree upkeep: [periphery-subtree-maintenance.md](periphery-subtree-maintenance.md). Rebuilding combine on new upstream: [periphery-combine-rebuild.md](periphery-combine-rebuild.md). Last updated: 2026-06-14.

## ✅ Accomplished

**5 upstream PRs now open:** #1132, #1133, #1134, #1136, #1137 (all draft/open, CI-green).

- **4 upstream PRs open, all CI-green:**
  - [#1132](https://github.com/peripheryapp/periphery/pull/1132) — redundant internal/fileprivate accessibility
  - [#1133](https://github.com/peripheryapp/periphery/pull/1133) — skip unresolvable subproject refs
  - [#1134](https://github.com/peripheryapp/periphery/pull/1134) — retain sole class init (draft)
  - [#1136](https://github.com/peripheryapp/periphery/pull/1136) — retain initialized constant assign-only properties
- **Old mess cleaned:** closed moot/superseded #1042/#1062/#1063; fork `master` = pure upstream mirror (f87c3f6); stale `all-fixes`/`fix-preview` deleted; zero AI traces in any commit/PR.
- **Backlog verified rigorously:** reproduce-first + real-Prodcore forceRemove probe (not minimal fixtures). Caught that the earlier "15/16 moot" verdict was WRONG.
- **`combine` branch (origin/combine @ 055609f) built AND PROVEN:** upstream + glue + #1132 + #1134 + nested + 4 restored fixes (ObservableMacroRetainer F1, ProtocolConformanceRetainer F3, assignOnly let/init F2/F8, UsedDeclarationMarker propagation walks F5/F7/F9/F11/F13). Converges ALL 4 historical baselines — forceRemoveAll(unused) → rebuild Prodcore → **0 build errors each**:

  | baseline | commit | lines removed | errors |
  |---|---|---|---|
  | R5 | a1711d27 | 4456 | 0 ✅ |
  | R4 | 20fb9b87 | 4465 | 0 ✅ |
  | R-May | 96e372e4 | 4469 | 0 ✅ |
  | R3 | 23ad2547 | 16511 | 0 ✅ |

- **Architecture documented:** branch-stack diagram, subtree→package migration runbook, catalog + memory corrected.

## ⏳ Waiting on maintainer (ileitch) — not our action

- Review + merge of the 4 open PRs (he hasn't engaged yet).
- Flag-consolidation answer (one `--redundant-accessibility` vs many flags) — shapes the nested #1048 PR. Don't build the clean umbrella until known (rework risk).
- Nothing here blocks Treeswift — combine is already proven.

## 🔨 Remaining our work

- **A — Real subtree merge of combine into Treeswift** ✅ DONE (committed 9f67b173, pushed to danwood/Treeswift main). Subtree = combine @ 055609f + 5 app-side API adaptations; real Treeswift builds clean; Package.resolved updated (swift-index-store).
- **B — Subtree → pinned Swift package — TRIED then REVERTED (decision: keep the subtree).** The package migration worked (drift-proof, builds+runs), but it gave up the subtree's self-contained "clone-and-build" property (offline build; a fresh checkout needs no network). The 1.7GB "bloat" reason for migrating was unfounded — that was gitignored `.build` artifacts, never in git (real subtree source ≈ 900KB). So the subtree's only real cost is drift-risk (guardable with a CI check), which doesn't outweigh self-containment. Reverted to the git subtree at the combine content. Tag `treeswift-combine-2026-06-14` (commit 055609f) retained as a marker of what the subtree equals.
- **C — Upstream PRs for the restored fixes:** [IN PROGRESS]
  - **Observable (F1) — NOT upstreamable standalone.** Does not reproduce on upstream toolchain (Swift 6.3.2 emits direct property→type refs; custom type already `used` without the retainer). No falsifiable test possible. Value lives in combine (forceRemove convergence bar), not as a standalone PR.
  - **Protocol (F3) — NOT upstream-appropriate.** ProtocolConformanceRetainer marks conformed protocols "retained", which suppresses upstream's redundant-protocol diagnostic (fails testSimpleRedundantProtocol + 2 siblings). STAYS Treeswift-only in combine. An upstream version needs reshaping RedundantProtocolMarker, not a lift — deferred design decision.
  - **UsedDeclarationMarker walks — only 1 of 5 upstreamable.** PR #1137 (draft) ships the returnType/parameterType walk (clean, reproduces, 0 regressions). The other 4 walks REGRESS upstream's dead-code precision or are moot on Swift 6.3.2 — they stay Treeswift-only in combine. Combine's full walk set is a deliberate recall-over-precision tradeoff: correct for Treeswift's aggressive cleanup, wrong for upstream's precise detection.
  - **C verdict:** of the 3 restored fixes, only ONE narrow walk upstreams cleanly (#1137). F1 (Observable) inert on current toolchain; F3 (Protocol) conflicts with redundant-protocol diagnostic; 4/5 UsedDecl walks regress precision. All 3 fixes correctly LIVE in combine (proven by forceRemove convergence) — they just don't translate to standalone upstream PRs. This is expected: combine optimizes recall (catch all Prodcore dead code safely), upstream optimizes precision.
  - LESSON: never run concurrent agents in one git checkout (they branch-switch under each other). Run serially.
- **D — Clean nested/private(set) #1048 PR** — gated on ileitch's flag answer.

## 🏁 Definition of done + success

- **Minimum viable:** A done — Treeswift runs on the proven combine.
- **Full success:** A + C + D upstreamed, ileitch merges them, subtree shrinks toward glue-only.

## Hard-won lessons

- ALWAYS validate Periphery fixes with the forceRemoveAll → rebuild Prodcore probe. Minimal upstream fixtures gave false "moot" verdicts — they don't reproduce real-codebase patterns at scale.
- assignOnlyProperty + redundantProtocol are non-removable by design — their scan COUNT is cosmetic, not a convergence gate. Real criterion: unused→0 after removal, zero build errors.
- agent `isolation: worktree` can resolve against the wrong repo — for Treeswift-side work, use explicit cwd, not worktree isolation.
