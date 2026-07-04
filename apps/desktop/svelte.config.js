// Tauri has no Node.js server for SSR, so we use adapter-static with an
// index.html fallback to run the app as an SPA.
// See: https://svelte.dev/docs/kit/single-page-apps
// See: https://v2.tauri.app/start/frontend/sveltekit/
import adapter from '@sveltejs/adapter-static'
import { vitePreprocess } from '@sveltejs/vite-plugin-svelte'

/** @type {import('@sveltejs/kit').Config} */
const config = {
	preprocess: vitePreprocess(),
	kit: {
		adapter: adapter({
			fallback: 'index.html',
		}),
		alias: {
			$components: 'src/components',
			$features: 'src/features',
			$stores: 'src/stores',
			$constants: 'src/constants',
			$types: 'src/@types',
			$style: 'src/style',
			$config: 'src/config.ts',
		},
	},
}

export default config
