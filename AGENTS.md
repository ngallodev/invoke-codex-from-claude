# Agent Instructions for invoke-codex-from-claude

Welcome! These instructions tell you how to operate safely and effectively while helping with this repository.

## Context
- **Repository root**: `/lump/apps/invoke-codex-from-claude`
- **Sandbox**: You can read and edit files in this tree, but editing outside requires special approval, which you are not allowed to request. You must find workarounds within the workspace.
- **Skills**: See `AGENTS.md` and any `SKILL.md` files for skill-specific workflows. When a skill is mentioned or clearly applicable, use it following its instructions.

## General Workflow
1. **Assess the request**: Understand what the user needs, inspect the repo, and check for any special instructions (e.g., existing `AGENTS.md`, `SKILL.md`, or developer messages).
2. **Plan if needed**: For anything beyond trivial edits (roughly >25% difficulty), create a brief plan using the plan tool, update it after each sub-task you actually perform, and avoid single-step plans.
3. **Follow editing constraints**:
   - Use ASCII by default unless the file already uses Unicode or a clear justification exists.
   - Prefer `rg` for searching (`rg --files` for file lists).
   - Use `apply_patch` for edits when practical (but not for auto-generated files or large replacements).
   - Never revert user changes or undo unrelated edits.
   - Never run destructive git commands (`git reset --hard`, `git checkout --`, etc.).
4. **Test**: Run or add tests/scripts when helpful. If tests are added temporarily for validation, remove them before finishing.
5. **Validate**: Ensure the repo remains consistent. If you encounter unexpected files or results, pause and report rather than guessing.
6. **Communicate**: In final response, be concise, mention what changed, reference files (with line numbers), and suggest logical next steps if appropriate.

## Skills
Available skills may be listed in `.codex/skills` or other relevant paths. Use them when required by the user or when their description fits the task.

## Final Deliverables
- Provide summary of edits referencing files and line numbers.
- Mention tests run or validation steps taken.
- Suggest next steps (testing, deployment, etc.) when applicable.
