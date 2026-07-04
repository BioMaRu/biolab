<script lang="ts">
	import { onMount } from 'svelte'
	import Icon from '$components/Icon.svelte'
	import PanelToolbar from '$components/PanelToolbar.svelte'
	import { usageStore } from '$features/usage/usage.svelte'
	import { fmtUsd } from '$features/usage/format'
	import ProviderCard from '$features/usage/components/ProviderCard.svelte'

	// Ticking clock so session countdowns and "scanned Xm ago" stay live.
	let now = $state(Date.now())

	const tracked = $derived(usageStore.providers.filter((p) => p.tracked))
	const untracked = $derived(usageStore.providers.filter((p) => !p.tracked))

	const scannedLabel = $derived.by(() => {
		const ts = usageStore.lastUpdated
		if (!ts) return 'not scanned yet'
		const diff = Math.max(0, now - ts)
		if (diff < 5_000) return 'scanned just now'
		if (diff < 60_000) return `scanned ${Math.floor(diff / 1000)}s ago`
		if (diff < 3_600_000) return `scanned ${Math.floor(diff / 60_000)}m ago`
		return `scanned ${Math.floor(diff / 3_600_000)}h ago`
	})

	onMount(() => {
		void usageStore.refresh()
		const timer = setInterval(() => (now = Date.now()), 30_000)
		return () => clearInterval(timer)
	})
</script>

<div class="usage">
	<PanelToolbar>
		{#snippet start()}
			<span
				class="summary"
				title="Estimated spend, last 7 days (tracked agents)"
			>
				<Icon name="coin" size={13} />
				<strong>{fmtUsd(usageStore.weekCost)}</strong>
				<span>est. · 7 days</span>
			</span>
		{/snippet}
		{#snippet end()}
			<span class="scanned">{scannedLabel}</span>
			<button
				class="refresh"
				class:spinning={usageStore.loading}
				title="Rescan usage"
				aria-label="Rescan"
				onclick={() => usageStore.refresh()}
			>
				<Icon name="refresh" size={15} />
			</button>
		{/snippet}
	</PanelToolbar>

	{#if usageStore.error}
		<div class="banner error">
			<Icon name="alert" size={14} />
			<span>{usageStore.error}</span>
			<button class="banner-retry" onclick={() => usageStore.refresh()}>
				Retry
			</button>
		</div>
	{/if}

	<div class="body u-scroll">
		{#if usageStore.loading && !usageStore.report}
			<div class="state">
				<span class="spinner"></span>
				Reading usage logs…
			</div>
		{:else}
			<div class="cards">
				{#each tracked as p (p.id)}
					<ProviderCard
						provider={p}
						{now}
						limits={usageStore.limits}
						limitsError={usageStore.limitsError}
						limitsLoading={usageStore.limitsLoading}
						onRetryLimits={() => usageStore.refreshLimits()}
					/>
				{/each}
			</div>

			{#if untracked.length}
				<div class="cards untracked-grid">
					{#each untracked as p (p.id)}
						<ProviderCard provider={p} {now} />
					{/each}
				</div>
			{/if}

			<p class="disclaimer">
				Token counts come from each agent's local logs. Costs are
				estimates from public model pricing and may differ from your
				actual bill.
			</p>
		{/if}
	</div>
</div>

<style lang="scss">
	.usage {
		display: flex;
		flex-direction: column;
		height: 100%;
	}

	.summary {
		display: inline-flex;
		align-items: baseline;
		gap: rem(6);
		color: var(--text-tertiary);
		font-size: rem(12);

		:global(svg) {
			align-self: center;
			color: var(--accent-fg);
		}
		strong {
			color: var(--text);
			font-size: rem(15);
			font-weight: 650;
			font-variant-numeric: tabular-nums;
		}
	}

	.scanned {
		color: var(--text-tertiary);
		font-size: rem(11.5);
		font-variant-numeric: tabular-nums;
	}

	.refresh {
		display: flex;
		justify-content: center;
		align-items: center;
		width: rem(30);
		height: rem(30);
		flex-shrink: 0;
		color: var(--text-secondary);
		background: transparent;
		border: none;
		border-radius: var(--radius-sm);
		transition:
			background-color 0.12s ease,
			color 0.12s ease;

		&:hover {
			color: var(--text);
			background: var(--hover);
		}
		&.spinning :global(svg) {
			animation: spin 0.7s linear infinite;
		}
	}

	@keyframes spin {
		to {
			transform: rotate(360deg);
		}
	}

	.banner {
		display: flex;
		align-items: center;
		gap: rem(8);
		flex-shrink: 0;
		padding: rem(9) rem(16);
		font-size: rem(12.5);

		&.error {
			color: var(--danger);
			background: color-mix(in srgb, var(--danger) 12%, transparent);
			border-bottom: 1px solid
				color-mix(in srgb, var(--danger) 24%, transparent);
		}
	}

	.banner-retry {
		margin-left: auto;
		padding: rem(3) rem(10);
		color: var(--danger);
		font-size: rem(12);
		font-weight: 600;
		background: transparent;
		border: 1px solid color-mix(in srgb, var(--danger) 40%, transparent);
		border-radius: var(--radius-sm);
		&:hover {
			background: color-mix(in srgb, var(--danger) 14%, transparent);
		}
	}

	.body {
		flex: 1;
		min-height: 0;
		padding: rem(16);
	}

	.cards {
		display: flex;
		flex-direction: column;
		gap: rem(12);
		max-width: rem(760);
	}

	.untracked-grid {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(rem(300), 1fr));
		gap: rem(12);
		margin-top: rem(12);
	}

	.disclaimer {
		max-width: rem(760);
		margin-top: rem(16);
		color: var(--text-tertiary);
		font-size: rem(11.5);
		line-height: 1.5;
	}

	.state {
		display: flex;
		justify-content: center;
		align-items: center;
		gap: rem(10);
		height: 100%;
		color: var(--text-tertiary);
		font-size: rem(13);
	}

	.spinner {
		width: rem(15);
		height: rem(15);
		border: 2px solid var(--border-strong);
		border-top-color: var(--accent);
		border-radius: 50%;
		animation: spin 0.7s linear infinite;
	}
</style>
