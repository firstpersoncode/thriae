# .hermes/project/

Product documentation: the intended requirements, architecture, and technical
specifications for this repository's product. These documents are the primary
source agents consult before making decisions — documentation before
assumptions.

This directory documents one repository-level product. Internal components are
defined within these documents, not in subdirectories.

Contents (when present):

- `PRD.md` — product requirements: overview, target user, functional
  requirements, product constraints, and scope boundaries.
- `ARCHITECTURE.md` — component design and data flow.
- `TECHNICAL_SPEC.md` — the exact API, output, error, and exit-code contract.

Conflict rule: if any other source (conversation history, plan summaries,
memory) disagrees with these documents, the documents win. Gaps or conflicts
found in these documents are escalated to the owner, never invented around.
