<script lang="ts">
	import DashboardLayout from '$features/layouts/DashboardLayout.svelte'

	let { children } = $props()
</script>

<DashboardLayout>
	{@render children()}
</DashboardLayout>
