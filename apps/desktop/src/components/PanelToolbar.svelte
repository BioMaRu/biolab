<script lang="ts">
	import type { Snippet } from 'svelte'

	interface Props {
		/** Left cluster — typically a search field + inline meta. */
		start?: Snippet
		/** Right cluster — typically the section's primary actions. */
		end?: Snippet
	}

	let { start, end }: Props = $props()
</script>

<div class="panel-toolbar">
	<div class="tb-start">
		{@render start?.()}
	</div>
	<div class="tb-end">
		{@render end?.()}
	</div>
</div>

<style lang="scss">
	.panel-toolbar {
		display: flex;
		justify-content: space-between;
		align-items: center;
		gap: rem(12);
		flex-shrink: 0;
		min-height: rem(50);
		padding: rem(9) rem(16);
		border-bottom: 1px solid var(--border);
	}

	.tb-start,
	.tb-end {
		display: flex;
		align-items: center;
		gap: rem(10);
		min-width: 0;
	}

	.tb-end {
		flex-shrink: 0;
	}
</style>
