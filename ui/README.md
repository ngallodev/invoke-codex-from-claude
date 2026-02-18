# UI Workspace

This is the local-first UI workspace for the orchestration control plane.

## Prerequisites
- Node.js `>=18`
- npm `>=9`

## Quick Start
```bash
bash scripts/ui_doctor.sh
bash scripts/bootstrap_ui.sh
cd ui
npm run dev
```

Open: `http://localhost:4173`

## Scripts
- `npm run dev`: start local UI dev server
- `npm run build`: production build check
- `npm run test`: unit tests (Vitest)
- `npm run test:e2e`: Playwright test run (requires browser install)

## Install Troubleshooting
If installs fail:
1. Verify versions: `node -v && npm -v`
2. Retry clean install:
   ```bash
   rm -rf ui/node_modules ui/package-lock.json
   cd ui && npm cache verify && npm install
   ```
3. If Playwright tests are needed, install browsers:
   ```bash
   cd ui && npx playwright install
   ```
