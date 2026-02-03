import { test, expect } from '@playwright/test';

/**
 * Trio Chat Dashboard Tests
 * PLAN-050: Playwright Testing Framework
 *
 * Tests the real-time chat between splntrb, Keystone, and Stream
 */

// Test credentials from environment or defaults
const TEST_USER = process.env.TEST_USER || 'splntrb';
const TEST_PASS = process.env.TEST_PASS || 'test_password';
const BASE_URL = process.env.TEST_BASE_URL || 'http://localhost:4000';

test.describe('Trio Chat Dashboard', () => {
  test.beforeEach(async ({ page }) => {
    // Login first
    await page.goto(`${BASE_URL}/login`);

    // Fill login form
    await page.fill('input[name="email"]', `${TEST_USER}@onelist.my`);
    await page.fill('input[name="password"]', TEST_PASS);
    await page.click('button[type="submit"]');

    // Wait for redirect after login
    await page.waitForURL(/\/(app|dashboard|watch)/);
  });

  test('displays four chat panes', async ({ page }) => {
    await page.goto(`${BASE_URL}/dashboard`);

    // Wait for the chat UI to load
    await page.waitForSelector('.trio-chat');

    // Should have 3 DM panes
    const dmPanes = await page.locator('.dm-pane').count();
    expect(dmPanes).toBe(3);

    // Should have 1 group pane
    await expect(page.locator('.group-pane')).toBeVisible();
  });

  test('pane headers are correct', async ({ page }) => {
    await page.goto(`${BASE_URL}/dashboard`);
    await page.waitForSelector('.trio-chat');

    // Check DM pane headers
    await expect(page.locator('.pane-header:has-text("splntrb ↔ Key")')).toBeVisible();
    await expect(page.locator('.pane-header:has-text("splntrb ↔ Stream")')).toBeVisible();
    await expect(page.locator('.pane-header:has-text("Key ↔ Stream")')).toBeVisible();

    // Check group pane header
    await expect(page.locator('.pane-header:has-text("The Trio")')).toBeVisible();
  });

  test('Key ↔ Stream pane is read-only for splntrb', async ({ page }) => {
    await page.goto(`${BASE_URL}/dashboard`);
    await page.waitForSelector('.trio-chat');

    // The Key ↔ Stream pane should show read-only notice
    await expect(page.locator('.dm-pane.readonly')).toBeVisible();
    await expect(page.locator('.readonly-notice')).toBeVisible();
  });

  test('can type in group chat input', async ({ page }) => {
    await page.goto(`${BASE_URL}/dashboard`);
    await page.waitForSelector('.trio-chat');

    const input = page.locator('.group-pane input[name="content"]');
    await expect(input).toBeVisible();

    await input.fill('Test message from Playwright');
    await expect(input).toHaveValue('Test message from Playwright');
  });

  test('send button exists for writable panes', async ({ page }) => {
    await page.goto(`${BASE_URL}/dashboard`);
    await page.waitForSelector('.trio-chat');

    // Group pane should have send button
    await expect(page.locator('.group-pane button[type="submit"]')).toBeVisible();

    // First two DM panes should have send buttons
    const sendButtons = await page.locator('.dm-pane:not(.readonly) button[type="submit"]').count();
    expect(sendButtons).toBe(2);
  });
});

test.describe('Trio Chat - Message Flow', () => {
  test.skip('can send message to group', async ({ page }) => {
    // Skip this test in CI as it modifies data
    // Run manually: npx playwright test --grep "can send message"

    await page.goto(`${BASE_URL}/login`);
    await page.fill('input[name="email"]', `${TEST_USER}@onelist.my`);
    await page.fill('input[name="password"]', TEST_PASS);
    await page.click('button[type="submit"]');
    await page.waitForURL(/\/(app|dashboard|watch)/);

    await page.goto(`${BASE_URL}/dashboard`);
    await page.waitForSelector('.trio-chat');

    const testMessage = `Playwright test ${Date.now()}`;

    // Type and send message
    const input = page.locator('.group-pane input[name="content"]');
    await input.fill(testMessage);
    await page.locator('.group-pane button[type="submit"]').click();

    // Wait for message to appear
    await expect(page.locator(`.group-pane .message:has-text("${testMessage}")`)).toBeVisible({
      timeout: 5000
    });
  });
});
