---
name: git-tag-changelog
description: Use when the user asks to write changelogs, change logs, release notes, or summarize what changed between git tags. Especially useful when the user wants a changelog based on the latest two git tags or asks for a concise release summary from recent commits.
---

# Git Tag Changelog

Generate changelogs from git tags instead of guessing from memory.

## When To Use

- The user asks for a changelog or release notes
- The user mentions "Change Logs", "changelog", or "what changed"
- The user wants the summary based on git history, tags, or commits

## Default Workflow

1. Run `scripts/generate_git_tag_changelog.sh` from the skill directory.
2. If the user did not specify tags, compare the latest two version-like git tags.
3. Read the script output:
   - compared tags
   - commit subjects
   - changed files
4. Write a concise changelog from the actual diff.

## Output Rules

- Default to English unless the user asks for another language.
- Prefer short release-note language, not commit-by-commit narration.
- Group user-facing changes when the diff clearly separates platforms or surfaces such as `Mac`, `Windows`, `Docs`, or `Internal`.
- If one platform has no meaningful changes, omit that section.
- Do not invent details that are not supported by commit subjects or changed files.
- If the change is implementation-only and not user-facing, keep it out or compress it into one short internal note.

## Commands

Default:

```bash
bash .agents/skills/git-tag-changelog/scripts/generate_git_tag_changelog.sh
```

Specific tags:

```bash
bash .agents/skills/git-tag-changelog/scripts/generate_git_tag_changelog.sh v1.40 v1.41
```
