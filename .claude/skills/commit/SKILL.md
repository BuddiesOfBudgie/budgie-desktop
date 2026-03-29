---
name: commit
description: Stage and commit changes using Conventional Commits
disable-model-invocation: false
allowed-tools: Bash(git *)
---

Create a git commit for the current changes following the Conventional Commits specification.

## Steps

1. Run these commands in parallel to understand the current state:
   - `git status` to see all changed and untracked files
   - `git diff` to see unstaged changes
   - `git diff --cached` to see already-staged changes
   - `git log --oneline -5` to see recent commit style

2. Analyze the changes and determine:
   - Which files should be staged (skip files that likely contain secrets like `.env`, credentials, etc.)
   - The appropriate Conventional Commit type and scope
   - A concise description of the change

3. Stage the relevant files by name (do NOT use `git add -A` or `git add .`)

4. Determine attribution — analyze the conversation context:
   - **Did Claude write or modify code** (generate implementations, refactor logic, write new functions)? → Add `Assisted-by: Claude:<model-id>` trailer
   - **Did Claude only perform mechanical tasks** (committing, formatting, running commands) or did the human make all code changes? → NO trailer
   - Never use `Co-Authored-By`

5. Craft the commit message following this format:

```
<type>(<scope>): <description>

[optional body]

[Assisted-by: Claude:<model-id> — only if Claude assisted with code changes]
Signed-off-by: <name> <email>
```

**Important**: All commits require a DCO sign-off. Always use `git commit -s` to automatically add the `Signed-off-by` trailer.

### Conventional Commit types and scopes

See [CONTRIBUTING.md](../../../CONTRIBUTING.md#conventional-commits) for the full list of types and scopes.

### Rules

- The description should be lowercase, imperative mood, and not end with a period
- Keep the first line under 72 characters
- Scope is optional but encouraged — use the most relevant area
- The body should explain **why**, not what — the diff shows what changed
- If changes span multiple concerns, prefer a single commit with a clear summary over being overly granular
- Always pass the commit message via a HEREDOC:

```bash
git commit -s -m "$(cat <<'EOF'
type(scope): description

Optional body.

Assisted-by: Claude:<model-id>
EOF
)"
```

6. After committing, run `git status` to verify success.

## Arguments

If `$ARGUMENTS` is provided, use it as guidance for the commit message or scope.
