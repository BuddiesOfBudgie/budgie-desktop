---
name: pr
description: Create a pull request for the current branch
disable-model-invocation: false
allowed-tools: Bash(git *), Bash(gh pr create *), Skill(commit)
---

# Create a Pull Request

You are creating a pull request for the current branch on budgie-desktop (C / Vala desktop environment built with Meson + Ninja).

## Step 1: Gather Context

Run these commands to understand the current state:

```bash
git status
git log --oneline main..HEAD
git diff main...HEAD --stat
git diff main...HEAD
git branch --show-current
```

If there are uncommitted changes, run the `/commit` skill first before proceeding.

## Step 2: Determine PR Type

Based on the changes, choose the appropriate conventional commit type and scope. See [CONTRIBUTING.md](../../CONTRIBUTING.md#conventional-commits) for the full list of types and scopes.

## Step 3: Generate PR Content

**Title format**: `<type>: <short description>` (under 70 characters)

Read [`.github/PULL_REQUEST_TEMPLATE.md`](../../.github/PULL_REQUEST_TEMPLATE.md) and use its structure as the body format for the PR. Fill in the sections based on the changes being submitted.

## Step 4: Create the PR

Push the branch and create the PR:

```bash
git push -u origin HEAD
gh pr create --title "<title>" --body "$(cat <<'EOF'
<body content>
EOF
)"
```

**Target branch**: `main` (default)

## Notes

- Review all commits since divergence from main, not just the latest one
- Ensure the title accurately reflects the overall change
- Test plan should include build verification with `ninja -C build`
- See [CONTRIBUTING.md](../../CONTRIBUTING.md) for full contribution guidelines and AI attribution policy
