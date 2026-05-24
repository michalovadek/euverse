# data-external/

Mirrors of data files produced by sibling projects under
`C:\Users\uctqova\Documents\github\<other-repo>\`. Each subfolder corresponds
to one upstream project.

Every NEW file added here MUST have a sibling `<filename>.source.txt` (or a
folder-level `_SOURCE.md`) recording:

```
source-repo: <repo-name>
source-path: <path/inside/repo>
source-commit: <git-sha>
pulled-at: YYYY-MM-DD
```

This makes the provenance reproducible without depending on the other repo's
state at a future point in time.

Existing subfolders (`euplex/`, `euprops/`, `manifesto/`, `parlgov/`) predate
this convention. When a tracker first consumes one of them, add a
`_SOURCE.md` then so the provenance is captured at the moment of first use.

See AGENTS.md §4.
