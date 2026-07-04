import { defineConfig } from 'vite'
import { sveltekit } from '@sveltejs/kit/vite'

// @ts-expect-error process is a nodejs global
const host = process.env.TAURI_DEV_HOST

// https://vite.dev/config/
export default defineConfig(async () => ({
	plugins: [sveltekit()],

	// Auto-inject SCSS helpers (rem(), etc.) into every stylesheet / <style lang="scss">.
	css: {
		preprocessorOptions: {
			scss: {
				loadPaths: ['.'],
				additionalData: `@use 'src/style/functions' as *;\n`,
			},
		},
	},

	// Vite options tailored for Tauri development, applied in `tauri dev` / `tauri build`.
	//
	// 1. prevent Vite from obscuring rust errors
	clearScreen: false,
	// 2. tauri expects a fixed port, fail if that port is not available
	server: {
		port: 1420,
		strictPort: true,
		host: host || false,
		hmr: host
			? {
					protocol: 'ws',
					host,
					port: 1421,
				}
			: undefined,
		watch: {
			// 3. tell Vite to ignore watching `src-tauri`
			ignored: ['**/src-tauri/**'],
		},
	},
}))
