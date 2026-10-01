# The merge editor (WS6)

The design record for the Hyperon Wiki's editorial workflow: the `<Card>+proposal`
convention, the three-way merge workbench, and the gate that runs before a merge touches a
published card.

**If you are going to change the editorial workflow, read
[`ws6-merge-editor-design.md`](ws6-merge-editor-design.md) first.** The phase documents
below record decisions that the code still depends on; several encode reasoning that is not
obvious from the implementation.

For the workflow as a *user* rather than a builder, start at
[`../../ONBOARDING.md`](../../ONBOARDING.md) §4 and
[`../FEATURE-PRIMERS.md`](../FEATURE-PRIMERS.md) §5.

| Document | What it covers |
|---|---|
| [`ws6-merge-editor-design.md`](ws6-merge-editor-design.md) | **Start here.** Why `+proposal` exists and is separate from `+AI`; the three-way merge model; the human-approval governance rule. |
| [`ws6-merge-editor-impl-plan.md`](ws6-merge-editor-impl-plan.md) | The phased build behind the design document. |
| [`ws6-merge-editor-phase4-ui-contract.md`](ws6-merge-editor-phase4-ui-contract.md) | The merge workbench interface contract — panes, hunks, payload shape. |
| [`ws6-merge-editor-phase4_1-ribbons.md`](ws6-merge-editor-phase4_1-ribbons.md) | Workbench visual design note — connector ribbons and resizable bands. |
| [`ws6-merge-editor-phase5-tinymce-gate.md`](ws6-merge-editor-phase5-tinymce-gate.md) | The polish step, and why the merge draft is kept separate from the proposal. |
| [`ws6-merge-editor-phase6-apply-gate.md`](ws6-merge-editor-phase6-apply-gate.md) | The verification gate that runs before a merge touches a published card. |
| [`ws6-merge-editor-phase7-plan.md`](ws6-merge-editor-phase7-plan.md) | Lifecycle, entry points, and the legacy `+AI` bridge. |
| [`ws6-merge-editor-phase8-capability-gating.md`](ws6-merge-editor-phase8-capability-gating.md) | Permission gating for merge actions. |
| [`ws6-merge-editor-prod-deploy-notes.md`](ws6-merge-editor-prod-deploy-notes.md) | Production deploy and migration notes. |

These documents are **build-time records**. Where one disagrees with the running system, the
running system is correct — and where one describes a branch, a pull request, or a
sequencing decision from the build, read it as history rather than as instructions.

The implementation lives in `mod/editorial_review/`, whose source files carry detailed
rationale comments and cross-reference these documents by name. A summary of the pull
request that shipped the first version is in
[`../archive/ws6-merge-editor-pr25-summary.md`](../archive/ws6-merge-editor-pr25-summary.md).
