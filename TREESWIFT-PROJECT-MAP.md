# Treeswift Project Map

One router for the project's documentation. Four concerns, four homes — no overlap. Start here,
then go to the doc that answers your question.

| If you want to know… | Concern | Go to |
|----------------------|---------|-------|
| Why Periphery flagged something wrong and how we fixed it (the false-positive catalog) | **A — Periphery analysis fixes** | [`PERIPHERY-ANALYSIS-FIXES.md`](PERIPHERY-ANALYSIS-FIXES.md) |
| What we changed in Periphery *just to consume it as a library*, and how to preserve that across subtree pulls | **B — Periphery integration mods** | [`PeripherySource/periphery/README_Treeswift.md`](PeripherySource/periphery/README_Treeswift.md) |
| How to run a cleanup cycle against Prodcore and prove it's converging (the measured loop + supervisor) | **C — Cleanup process** | [`CLEANUP-PROCESS.md`](CLEANUP-PROCESS.md) |
| How Treeswift itself is built — architecture, scan/removal, automation API | **D — Treeswift implementation** | [`IMPLEMENTATION_NOTES.md`](IMPLEMENTATION_NOTES.md) · [`docs/automation-api.md`](docs/automation-api.md) |
| Design proposals for future Treeswift capabilities (e.g. algorithmically fixing `assignOnlyProperty` / `redundantProtocol`) | **D — proposals** | [`docs/proposals/`](docs/proposals/) |
| Build commands, code conventions, agent rules | (project guidance) | [`CLAUDE.md`](CLAUDE.md) |
| Live convergence metrics | (part of C) | `Prodcore-cleanup/convergence-ledger.md` |
| The git-history convergence experiment (replay historical baselines to zero) — what ran, results, and **resume state** | (part of C) | `Prodcore-cleanup/experiment-log.md` (narrative) · `Prodcore-cleanup/experiment-state.json` (authoritative resume) |

## The boundary that keeps A and B separate

A and B both touch `PeripherySource/periphery/`, so the split matters:

- **A (analysis fixes)** = changes to *what Periphery decides is used/unused/redundant*. Symptoms,
  root causes, the mutator fixes, regression fixtures, upstream-push status. Catalogued as **F1–F20**
  in `PERIPHERY-ANALYSIS-FIXES.md`. (Note: F17–F20 are Treeswift-side *removal/rewrite* fixes — they
  live in `Treeswift/Core`, not the subtree — but are catalogued in A alongside the analysis fixes
  because they are all "false positive a `forceRemoveAll` would hit, and how it was fixed".)
- **B (integration mods)** = changes to *make Periphery importable and drivable as a library* —
  public APIs, library products, the progress delegate, end-position tracking, concurrency
  checkpoints — plus the subtree/upstream workflow. In `README_Treeswift.md`.

If a change alters analysis results → A. If it only exposes/wires Periphery for Treeswift → B.

## Adding new knowledge — where it goes

- New false positive / analysis fix → **A** (`PERIPHERY-ANALYSIS-FIXES.md`, next F#), plus a
  regression fixture, plus a subtree-change note in **B** if it modifies the subtree.
- New library-integration change to Periphery → **B**.
- New process/workflow rule for cleaning a codebase → **C**.
- New fact about how Treeswift is implemented → **D**.

Keep each fact in exactly one home; cross-link rather than copy.
