# .hermes/memories/

Shared project state for the multi-agent workflow. One owner per file; agents
must not modify another role's artifacts. Do not append repetitive session
summaries here — files record only what is needed to resume work accurately.

Contents (when present):

- `ROADMAP.md` — Lead-generated structural build sequence: milestones, phases,
  dependencies, exit criteria. Derived from the requirements in
  `.hermes/project/`, which remains the source of truth for requirements and
  architecture.
- `PLANS.md` — exactly one active milestone plan, owned by the Lead. Empty or
  absent means the next milestone has not been planned yet; the Lead plans
  exactly one milestone at a time and never the whole roadmap.
- `PROGRESS.md` — Lead-owned execution tracker, updated from verified evidence
  (Kanban state, commits, agent reports). Workers report; the Lead records.
- `archive/milestones/` — archived plans for completed milestones.
- `reviews/` — preserved independent review reports, organized as
  `<milestone>/round-NN.md`. A review report cited anywhere must exist here.
