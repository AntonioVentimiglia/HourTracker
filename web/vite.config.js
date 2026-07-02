import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    // Proxy API calls to the backend so the browser sees same-origin requests.
    proxy: {
      '/auth': 'http://localhost:4000',
      '/sessions': 'http://localhost:4000',
      '/events': 'http://localhost:4000',
      '/summaries': 'http://localhost:4000',
      '/clock': 'http://localhost:4000',
      '/export': 'http://localhost:4000',
      '/sync': 'http://localhost:4000',
    },
  },
});
