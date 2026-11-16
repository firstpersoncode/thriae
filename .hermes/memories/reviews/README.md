# Project Review Reports

Reports are returned through Herdr agent sessions and must not be written into the repository by agents.

Lead is responsible for preserving the report in this directory after receiving it.

Suggested structure:

```text
reviews/
└── M1/
    └── P3/
        ├── round-01.md
        ├── round-02.md
        └── ...
```

Each report should identify:

- Milestone and phase.
- Review round.
- Base commit.
- Candidate commit.
- Source branch.
- Review outcome.
- Finding IDs and statuses.
- Validation evidence.
- Remaining risks.

Do not overwrite an earlier review round. Preserve each report as immutable review history.
