# Periphery operation — status & roadmap

**Living document.** Update when accomplishments land. Diagram: [periphery-branch-stack.svg](periphery-branch-stack.svg). Last updated: 2026-06-14.

## ✅ Accomplished

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

- **A — Real subtree merge of combine into Treeswift** (+ 5 app-side API adaptations). Converts proven scratch work into Treeswift's actual base. [IN PROGRESS / status below]
- **B — Subtree → pinned Swift package** (runbook: [subtree-to-package-migration.md](../Prodcore-cleanup/subtree-to-package-migration.md)). Kills drift, drops 1.7GB.
- **C — Upstream PRs for 3 still-un-PR'd restored fixes:** Observable (F1), Protocol (F3), UsedDeclarationMarker walks (F5/F7/F9/F11/F13). Need real-pattern tests. [DRAFT PRs being prepared]
- **D — Clean nested/private(set) #1048 PR** — gated on ileitch's flag answer.

## 🏁 Definition of done + success

- **Minimum viable:** A done — Treeswift runs on the proven combine.
- **Full success:** A + C + D upstreamed, ileitch merges them, subtree shrinks toward glue-only.

## Hard-won lessons

- ALWAYS validate Periphery fixes with the forceRemoveAll → rebuild Prodcore probe. Minimal upstream fixtures gave false "moot" verdicts — they don't reproduce real-codebase patterns at scale.
- assignOnlyProperty + redundantProtocol are non-removable by design — their scan COUNT is cosmetic, not a convergence gate. Real criterion: unused→0 after removal, zero build errors.
- agent `isolation: worktree` can resolve against the wrong repo — for Treeswift-side work, use explicit cwd, not worktree isolation.
