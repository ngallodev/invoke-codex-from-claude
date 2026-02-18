File Structure - DO NOT CHANGE
invoke-codex-from-claude/
  .claude/agents/team/
  
  .gitignore
  CLAUDE.md
  AGENTS.md - link to CLAUDE.md
  README.md
  install.sh
  runs/
  codex-job/
    SKILL.md
    references/
      examples/
        claude_hook_example.sh
        sample.log
        sample.meta.json
    scripts/
    assets/

    ## Agents
    Agents for this task live in .claude/agents/team/ and are specced out in agent-notes/rec-subagent-list.md

Steering:
- Product steering and architecture direction are defined in `docs/STEERING.md`.
- Core architecture draft decision record lives at `docs/ADR-0001-control-plane-core-architecture.md`.
    
