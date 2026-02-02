import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    globals: true,
    environment: 'node',
    coverage: {
      provider: 'v8',
      reporter: ['text', 'json', 'html'],
      include: ['index.ts'],
      exclude: ['**/*.test.ts', 'vitest.config.ts'],
      thresholds: {
        // Target thresholds
        lines: 70,
        functions: 70,
        branches: 60,
        statements: 70,
      },
    },
    testTimeout: 10000,
  },
});
