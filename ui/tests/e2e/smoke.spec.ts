import { test, expect } from "@playwright/test";

test("renders control plane heading", async ({ page }) => {
  await page.goto("/");
  await expect(page.getByText("Multi-Agent Orchestration Control Plane")).toBeVisible();
});
