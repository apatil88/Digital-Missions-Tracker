import { defineConfig } from 'vitest/config'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'
import { VitePWA } from 'vite-plugin-pwa'
import path from 'node:path'

// Authenticated data is never cached: Supabase API, auth and storage calls are
// network-only, and the precache holds only the built app shell and public assets.
const supabaseApi = ({ url }: { url: URL }) => /\/(rest|auth|storage|functions|realtime)\/v1\//.test(url.pathname)

export default defineConfig({
  plugins: [
    react(),
    tailwindcss(),
    VitePWA({
      // 'prompt': a new build never reloads the page on its own, so unsaved form text survives.
      registerType: 'prompt',
      includeAssets: ['icon.svg'],
      manifest: {
        name: 'Digital III Missions Tracker',
        short_name: 'Missions',
        description: 'Track and submit Teamwork and Respect missions. Demo with fictional data.',
        theme_color: '#D94320',
        background_color: '#FAF9F6',
        display: 'standalone',
        start_url: '/',
        icons: [
          { src: 'icon-192.png', sizes: '192x192', type: 'image/png' },
          { src: 'icon-512.png', sizes: '512x512', type: 'image/png' },
          { src: 'icon-512.png', sizes: '512x512', type: 'image/png', purpose: 'maskable' },
        ],
      },
      workbox: {
        globPatterns: ['**/*.{js,css,html,svg,png,woff2}'],
        navigateFallback: '/index.html',
        runtimeCaching: [{ urlPattern: supabaseApi, handler: 'NetworkOnly' }],
        cleanupOutdatedCaches: true,
      },
    }),
  ],
  resolve: { alias: { '@': path.resolve(__dirname, 'src') } },
  server: { port: 5173, strictPort: true },
  preview: { port: 4173, strictPort: true },
  test: {
    environment: 'jsdom',
    globals: true,
    setupFiles: ['src/test/setup.ts'],
    include: ['src/**/*.test.{ts,tsx}', 'tests/**/*.test.ts'],
    testTimeout: 20000,
  },
})
