<script lang="ts">
	import { onMount } from 'svelte'
	import Icon, { type IconName } from '$components/Icon.svelte'
	import { agentsStore } from '$features/agents/agents.svelte'
	import OverviewPanel from '$features/agents/components/OverviewPanel.svelte'
	import McpPanel from '$features/agents/components/McpPanel.svelte'
	import SkillsPanel from '$features/agents/components/SkillsPanel.svelte'
	import SymlinksPanel from '$features/agents/components/SymlinksPanel.svelte'
	import ContextPanel from '$features/agents/components/ContextPanel.svelte'

	type TabId = 'overview' | 'mcp' | 'skills' | 'symlinks' | 'context'

	const tabs: { id: TabId; label: string; icon: IconName }[] = [
		{ id: 'overview', label: 'Overview', icon: 'dashboard' },
		{ id: 'mcp', label: 'MCP', icon: 'plug' },
		{ id: 'skills', label: 'Skills', icon: 'ai' },
		{ id: 'symlinks', label: 'Symlinks', icon: 'link' },
		{ id: 'context', label: 'Context', icon: 'file' },
	]

	let active = $state<TabId>('overview')

	onMount(() => {
		void agentsStore.refresh()
	})
</script>

<div class="agents">
	<div class="tabbar">
		<div class="tabs">
			{#each tabs as tab (tab.id)}
				<button
					class="tab"
					class:active={active === tab.id}
					onclick={() => (active = tab.id)}
				>
					<Icon name={tab.icon} size={14} />
					{tab.label}
				</button>
			{/each}
		</div>
		<button
			class="refresh"
			class:spinning={agentsStore.loading}
			title="Rescan agents"
			aria-label="Rescan"
			onclick={() => agentsStore.refresh()}
		>
			<Icon name="refresh" size={15} />
		</button>
	</div>

	{#if agentsStore.error}
		<div class="banner error">{agentsStore.error}</div>
	{/if}

	<div class="panel">
		{#if agentsStore.loading && !agentsStore.inventory}
			<div class="state">Scanning your agents…</div>
		{:else if active === 'overview'}
			<OverviewPanel />
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

	.tabbar {
		display: flex;
		justify-content: space-between;
		align-items: center;
		gap: rem(12);
		flex-shrink: 0;
		padding: rem(10) rem(16);
		border-bottom: 1px solid var(--border);
	}

	.tabs {
		display: flex;
		gap: rem(2);
	}

	.tab {
		display: inline-flex;
		align-items: center;
		gap: rem(6);
		padding: rem(6) rem(12);
		color: var(--text-secondary);
		font-size: rem(13);
		font-weight: 500;
		background: transparent;
		border: none;
		border-radius: var(--radius-sm);
		transition: all 0.12s ease;

		&:hover {
			color: var(--text);
			background: var(--hover);
		}
		&.active {
			color: var(--accent);
			background: color-mix(in srgb, var(--accent) 12%, transparent);
		}
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
		transition: all 0.12s ease;

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
		flex-shrink: 0;
		padding: rem(8) rem(16);
		font-size: rem(12.5);

		&.error {
			color: var(--danger);
			background: color-mix(in srgb, var(--danger) 12%, transparent);
		}
	}

	.panel {
		flex: 1;
		min-height: 0;
	}

	.state {
		display: flex;
		justify-content: center;
		align-items: center;
		height: 100%;
		color: var(--text-tertiary);
		font-size: rem(13);
	}
</style>
