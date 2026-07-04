<script lang="ts">
	import Icon from '$components/Icon.svelte'
	import { agentsStore } from '$features/agents/agents.svelte'
	import { tildePath } from '$features/agents/format'
	import type { ToolId } from '$features/agents/types'

	const inv = $derived(agentsStore.inventory)
	const tools = $derived(inv?.tools ?? [])

	const mcpCountFor = (tool: string) =>
		agentsStore.mcpServers.filter((s) => s.tool === tool).length
	const skillCountFor = (tool: string) =>
		(inv?.skills ?? []).filter((s) => s.tool === tool).length

	const uniqueMcp = $derived(agentsStore.mcpNames.length)
	const sharedMcp = $derived(
		agentsStore.mcpNames.filter((n) => {
			const set = new Set(
				[...agentsStore.mcpServers, ...agentsStore.disabled]
					.filter((s) => s.name === n)
					.map((s) => s.tool),
			)
			return set.size >= 2
		}).length,
	)
	const disabledMcp = $derived(
		agentsStore.disabled.length +
			agentsStore.mcpServers.filter((s) => !s.enabled).length,
	)
	const skillCount = $derived(
		new Set((inv?.skills ?? []).map((s) => s.name)).size,
	)
	const linkCount = $derived(inv?.symlinks.length ?? 0)
	const brokenLinks = $derived(
		(inv?.symlinks ?? []).filter((l) => l.broken).length,
	)
	const contextCount = $derived(
		(inv?.contextFiles ?? []).filter((f) => f.exists).length,
	)

	const stats = $derived([
		{ label: 'MCP servers', value: uniqueMcp, icon: 'plug' as const },
		{
			label: 'Shared across agents',
			value: sharedMcp,
			icon: 'link' as const,
		},
		{ label: 'Disabled', value: disabledMcp, icon: 'close' as const },
		{ label: 'Skills', value: skillCount, icon: 'ai' as const },
		{ label: 'Symlinks', value: linkCount, icon: 'link' as const },
		{ label: 'Context files', value: contextCount, icon: 'file' as const },
	])
</script>

<div class="overview u-scroll">
	<div class="tools">
		{#each tools as t (t.id)}
			<div class="tool-card" class:off={!t.installed}>
				<div class="tc-head">
					<span class="tc-name">{t.name}</span>
					<span class="tc-state" class:on={t.installed}>
						{t.installed ? 'installed' : 'not found'}
					</span>
				</div>
				<div class="tc-body">
					<div class="tc-metric">
						<strong>{mcpCountFor(t.id as ToolId)}</strong>
						<span>MCP</span>
					</div>
					<div class="tc-metric">
						<strong>{skillCountFor(t.id as ToolId)}</strong>
						<span>skills</span>
					</div>
				</div>
				<code class="tc-path">{tildePath(t.configPath)}</code>
			</div>
		{/each}
	</div>

	<div class="grid">
		{#each stats as s (s.label)}
			<div class="stat">
				<div class="stat-icon"><Icon name={s.icon} size={16} /></div>
				<div class="stat-text">
					<strong>{s.value}</strong>
					<span>{s.label}</span>
				</div>
			</div>
		{/each}
	</div>

	{#if brokenLinks > 0}
		<div class="callout">
			<Icon name="alert" size={15} />
			<span>
				{brokenLinks} broken symlink{brokenLinks > 1 ? 's' : ''} — check the
				Symlinks tab to repair or remove {brokenLinks > 1
					? 'them'
					: 'it'}.
			</span>
		</div>
	{/if}

	<div class="central">
		<Icon name="link" size={14} />
		<span>Central skill store</span>
		<code>{tildePath(inv?.centralSkillsDir ?? '~/.agents/skills')}</code>
	</div>
</div>

<style lang="scss">
	.overview {
		height: 100%;
		padding: rem(16);
		overflow-y: auto;
	}

	.tools {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(rem(200), 1fr));
		gap: rem(12);
		margin-bottom: rem(16);
	}

	.tool-card {
		padding: rem(14);
		background: var(--surface);
		border: 1px solid var(--border);
		border-radius: var(--radius-lg);

		&.off {
			opacity: 0.6;
		}
	}

	.tc-head {
		display: flex;
		justify-content: space-between;
		align-items: center;
		margin-bottom: rem(12);
	}

	.tc-name {
		font-size: rem(14);
		font-weight: 600;
	}

	.tc-state {
		padding: rem(2) rem(8);
		color: var(--text-tertiary);
		font-size: rem(10.5);
		font-weight: 600;
		text-transform: uppercase;
		background: var(--surface-2);
		border-radius: 999px;

		&.on {
			color: var(--success);
			background: color-mix(in srgb, var(--success) 12%, transparent);
		}
	}

	.tc-body {
		display: flex;
		gap: rem(20);
		margin-bottom: rem(12);
	}

	.tc-metric {
		display: flex;
		align-items: baseline;
		gap: rem(5);

		strong {
			font-size: rem(20);
			font-weight: 600;
			font-variant-numeric: tabular-nums;
		}
		span {
			color: var(--text-tertiary);
			font-size: rem(11.5);
		}
	}

	.tc-path {
		display: block;
		overflow: hidden;
		color: var(--text-tertiary);
		font-family: var(--font-mono);
		font-size: rem(11);
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	.grid {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(rem(150), 1fr));
		gap: rem(10);
		margin-bottom: rem(16);
	}

	.stat {
		display: flex;
		align-items: center;
		gap: rem(11);
		padding: rem(12) rem(14);
		background: var(--surface-2);
		border: 1px solid var(--border);
		border-radius: var(--radius);
	}

	.stat-icon {
		display: flex;
		justify-content: center;
		align-items: center;
		width: rem(34);
		height: rem(34);
		flex-shrink: 0;
		color: var(--accent);
		background: color-mix(in srgb, var(--accent) 12%, transparent);
		border-radius: var(--radius-sm);
	}

	.stat-text {
		display: flex;
		flex-direction: column;

		strong {
			font-size: rem(18);
			font-weight: 600;
			font-variant-numeric: tabular-nums;
		}
		span {
			color: var(--text-tertiary);
			font-size: rem(11.5);
		}
	}

	.callout {
		display: flex;
		align-items: center;
		gap: rem(8);
		padding: rem(10) rem(14);
		margin-bottom: rem(16);
		color: var(--danger);
		font-size: rem(12.5);
		background: color-mix(in srgb, var(--danger) 10%, transparent);
		border: 1px solid color-mix(in srgb, var(--danger) 25%, transparent);
		border-radius: var(--radius);
	}

	.central {
		display: flex;
		align-items: center;
		gap: rem(8);
		padding: rem(10) rem(14);
		color: var(--text-secondary);
		font-size: rem(12.5);
		background: var(--surface-2);
		border: 1px solid var(--border);
		border-radius: var(--radius);

		code {
			margin-left: auto;
			color: var(--text-tertiary);
			font-family: var(--font-mono);
			font-size: rem(11.5);
		}
	}
</style>
