# Repository Publishing Instructions

When a requested website change is complete, run `powershell -ExecutionPolicy Bypass -File .\scripts\publish-changes.ps1` from the repository root.

The publisher is restricted to the existing `origin/main` branch. It validates the website before committing, creates a clear website commit, and pushes with a normal non-force push. Stop and report any error.

Only intended website changes may be published:

- `index.html`
- `favicon.ico`
- Files under `css/`, `images/`, and `scripts/`

Do not publish `AGENTS.md`, the publishing script, files under `New folder/`, documentation, secrets, generated files, or unrelated changes. Do not change the remote configuration, commit setup files, or force-push.