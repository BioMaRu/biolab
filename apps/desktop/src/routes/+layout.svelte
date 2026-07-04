<script lang="ts">
	import '$style/main.scss'
	import { onMount } from 'svelte'
	import { themeStore } from '$features/theme/app-theme.svelte'
	import { configStore } from '$features/settings/config.svelte'
	import { checkForUpdates } from '$lib/updater'

	let { children } = $props()

	onMount(() => {
		themeStore.init()
		configStore.init()
		// Silently check for a newer release on launch (only prompts if one exists).
		void checkForUpdates(true)
	})
</script>

{@render children()}
