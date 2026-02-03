import { defineConfig, devices } from '@playwright/test';

/**
 * Playwright configuration for OneList UI testing.
 * PLAN-050: Playwright Testing Framework
 */
export default defineConfig({
  testDir: './tests',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 1 : undefined,
  reporter: 'html',

  use: {
    // Base URL for tests
    baseURL: process.env.TEST_BASE_URL || 'http://localhost:4000',

    // Collect trace on failure
    trace: 'on-first-retry',

    // Screenshot on failure
    screenshot: 'only-on-failure',
  },

  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
  ],

  // Run local dev server before tests (optional)
  // webServer: {
  //   command: 'mix phx.server',
  //   url: 'http://localhost:4000',
  //   reuseExistingServer: !process.env.CI,
  //   cwd: '..',
  // },
});
