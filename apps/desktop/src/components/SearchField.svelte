<script lang="ts">
	import Icon from '$components/Icon.svelte'

	interface Props {
		value: string
		placeholder?: string
		/** Grow to fill available width (default is a fixed 220px pill). */
		grow?: boolean
		/** Fires on every change — for callers that can't two-way bind. */
		oninput?: (value: string) => void
	}

	let {
		value = $bindable(''),
		placeholder = 'Search…',
		grow = false,
		oninput,
	}: Props = $props()

	function set(v: string) {
		value = v
		oninput?.(v)
	}
</script>

<div class="search" class:grow class:filled={value.length > 0}>
	<Icon name="search" size={13} />
	<input
		type="text"
		{placeholder}
		{value}
		oninput={(e) => set(e.currentTarget.value)}
		spellcheck="false"
		autocorrect="off"
		autocapitalize="off"
	/>
	{#if value}
		<button
			class="clear"
			type="button"
			aria-label="Clear search"
			onclick={() => set('')}
		>
			<Icon name="close" size={11} />
		</button>
	{/if}
</div>

<style lang="scss">
	.search {
		display: inline-flex;
		align-items: center;
		gap: rem(6);
		width: rem(220);
		max-width: 100%;
		padding: rem(5) rem(9);
		color: var(--text-tertiary);
		background: var(--surface-2);
		border: 1px solid transparent;
		border-radius: var(--radius-sm);
		transition:
			border-color 0.12s ease,
			background-color 0.12s ease,
			box-shadow 0.12s ease;

		&:focus-within {
			color: var(--text-secondary);
			background: var(--surface);
			border-color: var(--accent);
			box-shadow: 0 0 0 3px
				color-mix(in srgb, var(--accent) 18%, transparent);
		}
		&.filled {
			color: var(--text-secondary);
		}
		&.grow {
			width: auto;
			flex: 1;
			max-width: rem(420);
		}
	}

	input {
		flex: 1;
		min-width: 0;
		color: var(--text);
		font-family: var(--font-sans);
		font-size: rem(12.5);
		background: transparent;
		border: none;
		outline: none;
		user-select: text;

		&::placeholder {
			color: var(--text-tertiary);
		}
	}

	.clear {
		display: flex;
		justify-content: center;
		align-items: center;
		width: rem(16);
		height: rem(16);
		flex-shrink: 0;
		color: var(--text-tertiary);
		background: var(--active);
		border: none;
		border-radius: 50%;
		transition: color 0.12s ease;

		&:hover {
			color: var(--text);
		}
	}
</style>
