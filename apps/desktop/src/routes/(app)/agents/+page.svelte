<script lang="ts">
	import { onMount } from 'svelte'
	import Icon, { type IconName } from '$components/Icon.svelte'
	import { agentsStore } from '$features/agents/agents.svelte'
	import { TOOLS, type SectionId } from '$features/agents/types'
	import OverviewPanel from '$features/agents/components/OverviewPanel.svelte'
	import McpPanel from '$features/agents/components/McpPanel.svelte'
	import SkillsPanel from '$features/agents/components/SkillsPanel.svelte'
	import SymlinksPanel from '$features/agents/components/SymlinksPanel.svelte'
	import ContextPanel from '$features/agents/components/ContextPanel.svelte'

	const tabs: { id: SectionId; label: string; icon: IconName }[] = [
		{ id: 'overview', label: 'Overview', icon: 'dashboard' },
		{ id: 'mcp', label: 'MCP', icon: 'plug' },
		{ id: 'skills', label: 'Skills', icon: 'ai' },
		{ id: 'symlinks', label: 'Symlinks', icon: 'link' },
		{ id: 'context', label: 'Context', icon: 'file' },
	]

	let active = $state<SectionId>('overview')

	// A slowly-ticking clock so "scanned 2m ago" stays honest without a manual refresh.
	let now = $state(Date.now())

	const inv = $derived(agentsStore.inventory)

	const presence = $derived(
		TOOLS.map((t) => ({
			...t,
			installed:
				inv?.tools.find((x) => x.id === t.id)?.installed ?? false,
		})),
	)

	const scannedLabel = $derived.by(() => {
		const ts = agentsStore.lastUpdated
		if (!ts) return 'not scanned yet'
		const diff = Math.max(0, now - ts)
		if (diff < 5_000) return 'scanned just now'
		if (diff < 60_000) return `scanned ${Math.floor(diff / 1000)}s ago`
		if (diff < 3_600_000) return `scanned ${Math.floor(diff / 60_000)}m ago`
		return `scanned ${Math.floor(diff / 3_600_000)}h ago`
	})

	onMount(() => {
		void agentsStore.refresh()
		const timer = setInterval(() => (now = Date.now()), 15_000)
		return () => clearInterval(timer)
	})
</script>

<div class="agents">
	<header class="cc-header">
		<nav class="segmented" aria-label="Agent sections">
			{#each tabs as tab (tab.id)}
				<button
					class="seg"
					class:active={active === tab.id}
					aria-current={active === tab.id ? 'page' : undefined}
					onclick={() => (active = tab.id)}
				>
					<Icon name={tab.icon} size={14} />
					<span>{tab.label}</span>
				</button>
			{/each}
		</nav>

		<div class="status">
			<div class="presence" title="Detected agent CLIs on this Mac">
				{#each presence as p (p.id)}
					<span
						class="agent-chip"
						class:on={p.installed}
						title={p.installed
							? `${p.name} — installed`
							: `${p.name} — not found`}
					>
						<span class="dot"></span>
						{p.short}
					</span>
				{/each}
			</div>

			<span class="divider"></span>

			<span class="scanned">{scannedLabel}</span>
			<button
				class="refresh"
				class:spinning={agentsStore.loading}
				title="Rescan your agents"
				aria-label="Rescan"
				onclick={() => agentsStore.refresh()}
			>
				<Icon name="refresh" size={15} />
			</button>
		</div>
	</header>

	{#if agentsStore.error}
		<div class="banner error">
			<Icon name="alert" size={14} />
			<span>{agentsStore.error}</span>
			<button class="banner-retry" onclick={() => agentsStore.refresh()}>
				Retry
			</button>
		</div>
	{/if}

	<div class="panel">
		{#if agentsStore.loading && !inv}
			<div class="state">
				<span class="spinner"></span>
				Scanning your agents…
			</div>
		{:else if active === 'overview'}
			<OverviewPanel onNavigate={(s) => (active = s)} />
		{:else if active === 'mcp'}
			<McpPanel />
		{:else if active === 'skills'}
			<SkillsPanel />
		{:else if active === 'symlinks'}
			<SymlinksPanel />
		{:else if active === 'context'}
			<ContextPanel />
		{/if}
	</div>
</div>

<style lang="scss">
	.agents {
		display: flex;
		flex-direction: column;
		height: 100%;
	}

	.cc-header {
		display: flex;
		justify-content: space-between;
		align-items: center;
		gap: rem(12);
		flex-shrink: 0;
		flex-wrap: wrap;
		padding: rem(10) rem(16);
		border-bottom: 1px solid var(--border);
	}

	/* Native-style segmented control ---------------------------------------- */
	.segmented {
		display: inline-flex;
		gap: rem(2);
		padding: rem(3);
		background: var(--surface-2);
		border: 1px solid var(--border);
		border-radius: rem(9);
	}

	.seg {
		display: inline-flex;
		align-items: center;
		gap: rem(6);
		padding: rem(5) rem(12);
		color: var(--text-secondary);
		font-size: rem(12.5);
		font-weight: 500;
		background: transparent;
		border: none;
		border-radius: rem(6);
		transition:
			background-color 0.14s ease,
			color 0.14s ease,
			box-shadow 0.14s ease;

		:global(svg) {
			opacity: 0.85;
		}

		&:hover:not(.active) {
			color: var(--text);
			background: var(--hover);
		}

		&.active {
			color: var(--text);
			background: var(--surface);
			box-shadow:
				0 1px 2px rgba(0, 0, 0, 0.14),
				0 0 0 0.5px rgba(0, 0, 0, 0.04);

			:global(svg) {
				color: var(--accent-fg);
				opacity: 1;
			}
		}
	}

	/* Status cluster -------------------------------------------------------- */
	.status {
		display: flex;
		align-items: center;
		gap: rem(10);
	}

	.presence {
		display: flex;
		align-items: center;
		gap: rem(4);
	}

	.agent-chip {
		display: inline-flex;
		align-items: center;
		gap: rem(5);
		padding: rem(3) rem(9) rem(3) rem(7);
		color: var(--text-tertiary);
		font-size: rem(11);
		font-weight: 600;
		background: var(--surface-2);
		border: 1px solid var(--border);
		border-radius: 999px;

		.dot {
			width: rem(6);
			height: rem(6);
			border-radius: 50%;
			background: var(--text-tertiary);
			opacity: 0.5;
		}

		&.on {
			color: var(--text-secondary);
			.dot {
				background: var(--success);
				opacity: 1;
				box-shadow: 0 0 0 3px
					color-mix(in srgb, var(--success) 20%, transparent);
			}
		}
	}

	.divider {
		width: 1px;
		height: rem(18);
		background: var(--border);
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

	/* Error banner ---------------------------------------------------------- */
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

	.panel {
		display: flex;
		flex-direction: column;
		flex: 1;
		min-height: 0;
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
