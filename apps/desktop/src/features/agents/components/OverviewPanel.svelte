<script lang="ts">
	import Icon, { type IconName } from '$components/Icon.svelte'
	import BrandGlyph from '$components/BrandGlyph.svelte'
	import { agentsStore } from '$features/agents/agents.svelte'
	import { tildePath } from '$features/agents/format'
	import { copyText } from '$lib/clipboard'
	import { TOOLS, type SectionId, type ToolId } from '$features/agents/types'

	interface Props {
		onNavigate: (section: SectionId) => void
	}
	let { onNavigate }: Props = $props()

	const inv = $derived(agentsStore.inventory)

	// Present the three known CLIs in a stable order, whether detected or not.
	const fleet = $derived(
		TOOLS.map((t) => {
			const found = inv?.tools.find((x) => x.id === t.id)
			return {
				id: t.id,
				name: t.name,
				installed: found?.installed ?? false,
				configPath: found?.configPath ?? '',
				mcp: agentsStore.mcpServers.filter((s) => s.tool === t.id)
					.length,
				skills: (inv?.skills ?? []).filter((s) => s.tool === t.id)
					.length,
			}
		}),
	)

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

	interface Stat {
		label: string
		value: number
		icon: IconName
		to: SectionId
		danger?: boolean
	}

	const stats = $derived<Stat[]>([
		{ label: 'MCP servers', value: uniqueMcp, icon: 'plug', to: 'mcp' },
		{
			label: 'Shared across agents',
			value: sharedMcp,
			icon: 'link',
			to: 'mcp',
		},
		{ label: 'Disabled', value: disabledMcp, icon: 'power', to: 'mcp' },
		{ label: 'Skills', value: skillCount, icon: 'ai', to: 'skills' },
		{
			label: 'Symlinks',
			value: linkCount,
			icon: 'link',
			to: 'symlinks',
		},
		{
			label: 'Context files',
			value: contextCount,
			icon: 'file',
			to: 'context',
		},
	])

	let copied = $state<string | null>(null)
	let copyTimer: ReturnType<typeof setTimeout> | null = null

	async function copyPath(path: string, key: string) {
		if (!path) return
		await copyText(path)
		copied = key
		if (copyTimer) clearTimeout(copyTimer)
		copyTimer = setTimeout(() => (copied = null), 1400)
	}

	const centralDir = $derived(inv?.centralSkillsDir ?? '~/.agents/skills')
	const installedCount = $derived(fleet.filter((f) => f.installed).length)
</script>

<div class="overview u-scroll">
	<!-- Fleet ------------------------------------------------------------- -->
	<section class="block">
		<h2 class="block-title">Your agents</h2>
		<div class="fleet">
			{#each fleet as t (t.id)}
				<div class="agent-card" class:off={!t.installed}>
					<div class="ac-head">
						<div class="ac-id">
							<span class="ac-glyph">
								<BrandGlyph
									tool={t.id}
									label={t.name}
									size={16}
								/>
							</span>
							<span class="ac-name">{t.name}</span>
						</div>
						<span class="ac-state" class:on={t.installed}>
							<span class="s-dot"></span>
							{t.installed ? 'Installed' : 'Not found'}
						</span>
					</div>

					{#if t.installed}
						<div class="ac-metrics">
							<button
								class="ac-metric"
								onclick={() => onNavigate('mcp')}
							>
								<strong>{t.mcp}</strong>
								<span>MCP</span>
							</button>
							<span class="ac-sep"></span>
							<button
								class="ac-metric"
								onclick={() => onNavigate('skills')}
							>
								<strong>{t.skills}</strong>
								<span>skills</span>
							</button>
						</div>
						<button
							class="ac-path"
							title="Copy config path"
							onclick={() => copyPath(t.configPath, t.id)}
						>
							<code>{tildePath(t.configPath)}</code>
							<Icon
								name={copied === t.id ? 'check' : 'copy'}
								size={12}
							/>
						</button>
					{:else}
						<p class="ac-empty">
							Not detected on this Mac. Install {t.name} to manage it
							here.
						</p>
					{/if}
				</div>
			{/each}
		</div>
	</section>

	<!-- Health ------------------------------------------------------------ -->
	<section class="block">
		{#if brokenLinks > 0}
			<button class="health warn" onclick={() => onNavigate('symlinks')}>
				<div class="h-icon"><Icon name="alert" size={16} /></div>
				<div class="h-text">
					<strong>
						{brokenLinks} broken symlink{brokenLinks > 1 ? 's' : ''}
					</strong>
					<span>The target no longer exists — repair or remove.</span>
				</div>
				<span class="h-cta">
					Fix in Symlinks
					<Icon name="chevron" size={13} />
				</span>
			</button>
		{:else}
			<div class="health ok">
				<div class="h-icon"><Icon name="shield" size={16} /></div>
				<div class="h-text">
					<strong>Everything's in sync</strong>
					<span>
						{installedCount} of {fleet.length} agents installed · no broken
						links.
					</span>
				</div>
			</div>
		{/if}
	</section>

	<!-- Stats ------------------------------------------------------------- -->
	<section class="block">
		<h2 class="block-title">At a glance</h2>
		<div class="grid">
			{#each stats as s (s.label)}
				<button
					class="stat"
					class:danger={s.danger && s.value > 0}
					onclick={() => onNavigate(s.to)}
				>
					<div class="stat-icon">
						<Icon name={s.icon} size={16} />
					</div>
					<div class="stat-text">
						<strong>{s.value}</strong>
						<span>{s.label}</span>
					</div>
					<Icon name="chevron" size={14} />
				</button>
			{/each}
		</div>
	</section>

	<!-- Central store ----------------------------------------------------- -->
	<button
		class="central"
		title="Copy path"
		onclick={() => copyPath(centralDir, 'central')}
	>
		<div class="c-icon"><Icon name="folder" size={14} /></div>
		<div class="c-text">
			<span class="c-label">Central skill store</span>
			<code>{tildePath(centralDir)}</code>
		</div>
		<Icon name={copied === 'central' ? 'check' : 'copy'} size={13} />
	</button>
</div>

<style lang="scss">
	.overview {
		height: 100%;
		padding: rem(18) rem(16) rem(24);
		overflow-y: auto;
	}

	.block {
		margin-bottom: rem(22);
	}

	.block-title {
		margin-bottom: rem(10);
		color: var(--text-secondary);
		font-size: rem(11.5);
		font-weight: 600;
		text-transform: uppercase;
		letter-spacing: 0.05em;
	}

	/* Fleet ------------------------------------------------------------- */
	.fleet {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(rem(220), 1fr));
		gap: rem(12);
	}

	.agent-card {
		display: flex;
		flex-direction: column;
		padding: rem(14) rem(15);
		background: var(--surface);
		border: 1px solid var(--border);
		border-radius: var(--radius-lg);
		transition: border-color 0.14s ease;

		&.off {
			background: var(--surface-2);
		}
	}

	.ac-head {
		display: flex;
		justify-content: space-between;
		align-items: center;
		gap: rem(8);
		margin-bottom: rem(14);
	}

	.ac-id {
		display: flex;
		align-items: center;
		gap: rem(9);
		min-width: 0;
	}

	.ac-glyph {
		display: flex;
		justify-content: center;
		align-items: center;
		width: rem(26);
		height: rem(26);
		flex-shrink: 0;
		color: var(--text);
		background: var(--surface-2);
		border: 1px solid var(--border);
		border-radius: var(--radius-sm);
	}

	.off .ac-glyph {
		color: var(--text-tertiary);
	}

	.ac-name {
		overflow: hidden;
		font-size: rem(14);
		font-weight: 600;
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	.ac-state {
		display: inline-flex;
		align-items: center;
		gap: rem(5);
		flex-shrink: 0;
		padding: rem(3) rem(8);
		color: var(--text-tertiary);
		font-size: rem(10.5);
		font-weight: 600;
		background: var(--surface-2);
		border-radius: 999px;

		.s-dot {
			width: rem(6);
			height: rem(6);
			border-radius: 50%;
			background: currentColor;
			opacity: 0.6;
		}
		&.on {
			color: var(--success);
			background: color-mix(in srgb, var(--success) 12%, transparent);
			.s-dot {
				opacity: 1;
			}
		}
	}

	.ac-metrics {
		display: flex;
		align-items: center;
		gap: rem(4);
		margin-bottom: rem(12);
	}

	.ac-metric {
		display: flex;
		align-items: baseline;
		gap: rem(5);
		padding: rem(2) rem(6);
		color: var(--text);
		background: transparent;
		border: none;
		border-radius: var(--radius-sm);
		transition: background-color 0.12s ease;

		&:hover {
			background: var(--hover);
		}

		strong {
			font-size: rem(21);
			font-weight: 650;
			font-variant-numeric: tabular-nums;
		}
		span {
			color: var(--text-tertiary);
			font-size: rem(11.5);
		}
	}

	.ac-sep {
		width: 1px;
		height: rem(20);
		margin: 0 rem(8);
		background: var(--border);
	}

	.ac-path {
		display: flex;
		align-items: center;
		gap: rem(8);
		width: 100%;
		margin-top: auto;
		padding: rem(6) rem(8);
		color: var(--text-tertiary);
		background: var(--surface-2);
		border: none;
		border-radius: var(--radius-sm);
		transition: color 0.12s ease;

		code {
			flex: 1;
			overflow: hidden;
			font-family: var(--font-mono);
			font-size: rem(11);
			text-align: left;
			text-overflow: ellipsis;
			white-space: nowrap;
		}

		&:hover {
			color: var(--text-secondary);
		}
	}

	.ac-empty {
		margin-top: auto;
		color: var(--text-tertiary);
		font-size: rem(12);
		line-height: 1.45;
	}

	/* Health ------------------------------------------------------------ */
	.health {
		display: flex;
		align-items: center;
		gap: rem(12);
		width: 100%;
		padding: rem(12) rem(14);
		text-align: left;
		border-radius: var(--radius);
		border: 1px solid transparent;

		.h-icon {
			display: flex;
			justify-content: center;
			align-items: center;
			width: rem(32);
			height: rem(32);
			flex-shrink: 0;
			border-radius: var(--radius-sm);
		}

		.h-text {
			display: flex;
			flex-direction: column;
			gap: rem(1);
			min-width: 0;
			strong {
				font-size: rem(13);
				font-weight: 600;
			}
			span {
				color: var(--text-tertiary);
				font-size: rem(12);
			}
		}

		&.ok {
			background: color-mix(in srgb, var(--success) 8%, transparent);
			border-color: color-mix(in srgb, var(--success) 22%, transparent);
			.h-icon {
				color: var(--success);
				background: color-mix(in srgb, var(--success) 14%, transparent);
			}
		}

		&.warn {
			background: color-mix(in srgb, var(--danger) 9%, transparent);
			border-color: color-mix(in srgb, var(--danger) 26%, transparent);
			.h-icon {
				color: var(--danger);
				background: color-mix(in srgb, var(--danger) 14%, transparent);
			}
			.h-text strong {
				color: var(--danger);
			}
			&:hover {
				background: color-mix(in srgb, var(--danger) 14%, transparent);
			}
		}
	}

	.h-cta {
		display: inline-flex;
		align-items: center;
		gap: rem(3);
		margin-left: auto;
		flex-shrink: 0;
		color: var(--danger);
		font-size: rem(12);
		font-weight: 600;
	}

	/* Stats ------------------------------------------------------------- */
	.grid {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(rem(168), 1fr));
		gap: rem(10);
	}

	.stat {
		display: flex;
		align-items: center;
		gap: rem(11);
		padding: rem(12) rem(13);
		color: var(--text);
		text-align: left;
		background: var(--surface);
		border: 1px solid var(--border);
		border-radius: var(--radius);
		transition:
			border-color 0.14s ease,
			background-color 0.14s ease;

		& > :global(svg) {
			margin-left: auto;
			color: var(--text-tertiary);
			opacity: 0;
			transform: translateX(rem(-4));
			transition:
				opacity 0.14s ease,
				transform 0.14s ease;
		}

		&:hover {
			border-color: color-mix(in srgb, var(--accent) 45%, var(--border));
			background: color-mix(in srgb, var(--accent) 7%, var(--surface));

			.stat-icon {
				background: color-mix(in srgb, var(--accent) 20%, transparent);
			}
			& > :global(svg) {
				color: var(--accent-fg);
				opacity: 1;
				transform: translateX(0);
			}
		}

		&.danger .stat-icon {
			color: var(--danger);
			background: color-mix(in srgb, var(--danger) 14%, transparent);
		}
	}

	.stat-icon {
		display: flex;
		justify-content: center;
		align-items: center;
		width: rem(34);
		height: rem(34);
		flex-shrink: 0;
		color: var(--accent-fg);
		background: color-mix(in srgb, var(--accent) 15%, transparent);
		border-radius: var(--radius-sm);
		transition: background-color 0.14s ease;
	}

	.stat-text {
		display: flex;
		flex-direction: column;
		min-width: 0;

		strong {
			font-size: rem(18);
			font-weight: 650;
			font-variant-numeric: tabular-nums;
		}
		span {
			overflow: hidden;
			color: var(--text-tertiary);
			font-size: rem(11.5);
			text-overflow: ellipsis;
			white-space: nowrap;
		}
	}

	/* Central store ----------------------------------------------------- */
	.central {
		display: flex;
		align-items: center;
		gap: rem(11);
		width: 100%;
		padding: rem(11) rem(14);
		color: var(--text-tertiary);
		text-align: left;
		background: var(--surface-2);
		border: 1px solid var(--border);
		border-radius: var(--radius);
		transition: border-color 0.12s ease;

		&:hover {
			border-color: var(--border-strong);
			color: var(--text-secondary);
		}
	}

	.c-icon {
		display: flex;
		justify-content: center;
		align-items: center;
		width: rem(30);
		height: rem(30);
		flex-shrink: 0;
		color: var(--text-secondary);
		background: var(--surface);
		border: 1px solid var(--border);
		border-radius: var(--radius-sm);
	}

	.c-text {
		display: flex;
		flex-direction: column;
		gap: rem(1);
		min-width: 0;

		.c-label {
			color: var(--text-secondary);
			font-size: rem(12.5);
			font-weight: 500;
		}
		code {
			overflow: hidden;
			font-family: var(--font-mono);
			font-size: rem(11);
			text-overflow: ellipsis;
			white-space: nowrap;
		}
	}
</style>
