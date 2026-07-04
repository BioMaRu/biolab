<script lang="ts">
	import { goto } from '$app/navigation'
	import { onMount } from 'svelte'

	// Land on the first working feature.
	onMount(() => {
		goto('/ports', { replaceState: true })
	})
</script>
