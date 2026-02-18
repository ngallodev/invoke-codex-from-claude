# UI Skills and Plugins Setup

Last updated: 2026-02-18

## 1) Agent Specs in This Repo
These UI specialist agents are now available under `.claude/agents/team/`:
- `ui-product-designer`
- `design-system-engineer`
- `frontend-state-architect`
- `data-viz-ux`
- `accessibility-qa`
- `frontend-test-engineer`

No extra installation is needed for these local agent files.

## 2) Recommended UI Tooling (for initial implementation)
If you scaffold a TypeScript UI app, install these baseline packages:

```bash
npm install react react-dom @tanstack/react-query zod recharts
npm install -D typescript vite @vitejs/plugin-react vitest @testing-library/react @testing-library/user-event jsdom playwright @storybook/react-vite @storybook/addon-essentials eslint eslint-plugin-jsx-a11y
```

Optional but high-value:

```bash
npm install @axe-core/playwright
npm install -D @types/node
```

## 3) Suggested Plugin/Capability Mapping
- Component development/docs: Storybook
- E2E + workflow confidence: Playwright
- Accessibility checks: `eslint-plugin-jsx-a11y` + Axe (`@axe-core/playwright`)
- Runtime state and data sync: `@tanstack/react-query`
- Runtime contract validation: `zod`
- Dashboards/charts: `recharts`

## 4) Skill Installation Notes
This repository already supports local, repo-scoped agent specs.
For external Codex skills, use your skill installer workflow and keep UI skills narrowly scoped:
- Design flow skill
- Design system skill
- Frontend state skill
- Accessibility audit skill
- Frontend testing skill

When adding external skills, prefer:
1. Small, tool-scoped skills over broad “do everything” skills.
2. Local references to repo ADR/steering docs for architectural alignment.
3. Explicit output contracts (files changed, checks run, telemetry fields).

## 5) Quick Start Sequence
1. Create UI shell and install packages above.
2. Stand up Storybook with core tokens/components first.
3. Add API client types from your control-plane schemas.
4. Build queue + run timeline screens.
5. Add Playwright + accessibility checks before approval actions.
