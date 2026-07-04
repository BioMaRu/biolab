<script lang="ts">
	import type { Snippet } from 'svelte'
	import Icon, { type IconName } from '$components/Icon.svelte'

	interface Props {
		icon?: IconName
		title: string
		hint?: string
		/** Optional call-to-action rendered below the hint. */
		action?: Snippet
	}

	let { icon = 'info', title, hint, action }: Props = $props()
</script>

<div class="empty-state">
	<div class="es-icon"><Icon name={icon} size={22} /></div>
	<p class="es-title">{title}</p>
	{#if hint}<p class="es-hint">{hint}</p>{/if}
	{#if action}<div class="es-action">{@render action()}</div>{/if}
</div>

<style lang="scss">
	.empty-state {
		display: flex;
		flex-direction: column;
		justify-content: center;
		align-items: center;
		gap: rem(4);
		flex: 1;
		min-height: rem(220);
		padding: rem(32);
		text-align: center;
	}

	.es-icon {
		display: flex;
		justify-content: center;
		align-items: center;
		width: rem(52);
		height: rem(52);
		margin-bottom: rem(8);
		color: var(--text-tertiary);
		background: var(--surface-2);
		border: 1px solid var(--border);
		border-radius: var(--radius-lg);
	}

	.es-title {
		color: var(--text);
		font-size: rem(14);
		font-weight: 600;
	}

	.es-hint {
		max-width: rem(340);
		color: var(--text-tertiary);
		font-size: rem(12.5);
		line-height: 1.5;
	}

	.es-action {
		margin-top: rem(12);
	}
</style>
