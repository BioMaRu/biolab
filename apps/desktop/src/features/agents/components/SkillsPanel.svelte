<script lang="ts">
	import { ask } from '@tauri-apps/plugin-dialog'
	import Icon from '$components/Icon.svelte'
	import { agentsStore } from '$features/agents/agents.svelte'
	import { skillRead } from '$features/agents/api'
	import { notify } from '$lib/notify'
	import { TOOLS, type Skill, type ToolId } from '$features/agents/types'
	import PanelToolbar from '$components/PanelToolbar.svelte'
	import SearchField from '$components/SearchField.svelte'
	import EmptyState from '$components/EmptyState.svelte'

	interface Group {
		name: string
		description: string | null
		byTool: Partial<Record<string, Skill>>
	}

	let query = $state('')

	const groups = $derived.by<Group[]>(() => {
		const map = new Map<string, Group>()
		for (const s of agentsStore.inventory?.skills ?? []) {
			const g = map.get(s.name) ?? {
				name: s.name,
				description: null,
				byTool: {},
			}
			g.byTool[s.tool] = s
			if (!g.description && s.description) g.description = s.description
			map.set(s.name, g)
		}
		return [...map.values()].sort((a, b) => a.name.localeCompare(b.name))
	})

	const filtered = $derived(
		groups.filter((g) => {
			const q = query.toLowerCase()
			return (
				g.name.toLowerCase().includes(q) ||
				(g.description?.toLowerCase().includes(q) ?? false)
			)
		}),
	)

	let viewing = $state<{ name: string; content: string } | null>(null)

	function status(s: Skill | undefined): { label: string; cls: string } {
		if (!s) return { label: '—', cls: 'none' }
		if (s.broken) return { label: 'broken', cls: 'broken' }
		if (s.isSymlink) return { label: 'linked', cls: 'linked' }
		return { label: 'folder', cls: 'folder' }
	}

	function pickSource(g: Group): Skill | null {
		for (const key of ['claude', 'codex', 'opencode', 'central']) {
			const s = g.byTool[key]
			if (s && !s.isSymlink && !s.broken) return s
		}
		return null
	}

	const isShared = (g: Group) =>
		!!g.byTool.central &&
		TOOLS.every((t) => g.byTool[t.id] && !g.byTool[t.id]!.broken)

	async function shareToAll(g: Group) {
		try {
			if (!g.byTool.central) {
				const src = pickSource(g)
				if (!src) {
					await notify(
						'Cannot share',
						'No real skill folder found to move.',
					)
					return
				}
				await agentsStore.skillShare(g.name, src.path)
			}
			const present = new Set(
				(agentsStore.inventory?.skills ?? [])
					.filter((s) => s.name === g.name)
					.map((s) => s.tool),
			)
			for (const t of TOOLS) {
				if (!present.has(t.id))
					await agentsStore.skillLink(t.id, g.name)
			}
			await notify(
				'Skill shared',
				`“${g.name}” is now shared across your agents.`,
			)
		} catch (e) {
			await notify(
				'Share failed',
				e instanceof Error ? e.message : String(e),
			)
		}
	}

	async function cellClick(g: Group, tool: ToolId) {
		const s = g.byTool[tool]
		if (!s) {
			if (!g.byTool.central) {
				await notify(
					'Not shared yet',
					'Use “Share to all” to create a central copy first.',
				)
				return
			}
			try {
				await agentsStore.skillLink(tool, g.name)
			} catch (e) {
				await notify(
					'Link failed',
					e instanceof Error ? e.message : String(e),
				)
			}
			return
		}
		if (s.isSymlink) {
			const ok = await ask(
				`Unlink “${g.name}” from ${tool}? The central copy is kept.`,
				{ title: 'Unlink skill', okLabel: 'Unlink' },
			)
			if (ok) {
				try {
					await agentsStore.symlinkRemove(s.path)
				} catch (e) {
					await notify(
						'Unlink failed',
						e instanceof Error ? e.message : String(e),
					)
				}
			}
		}
	}

	async function view(g: Group) {
		const src = (agentsStore.inventory?.skills ?? []).find(
			(s) => s.name === g.name && !s.broken,
		)
		if (!src) return
		try {
			viewing = { name: g.name, content: await skillRead(src.path) }
		} catch (e) {
			await notify(
				'Read failed',
				e instanceof Error ? e.message : String(e),
			)
		}
	}
</script>

<div class="skills">
	<PanelToolbar>
		{#snippet start()}
			<SearchField bind:value={query} placeholder="Filter skills…" />
			<span class="legend">
				One source in <code>~/.agents/skills</code>
				, linked everywhere.
			</span>
		{/snippet}
		{#snippet end()}
			{#if groups.length}
				<span class="count">
					{filtered.length} of {groups.length}
				</span>
			{/if}
		{/snippet}
	</PanelToolbar>

	{#if groups.length === 0}
		<EmptyState
			icon="ai"
			title="No skills found"
			hint="Skills are reusable instruction folders your agents can load. Add one under an agent, then share it across all of them from here."
		/>
	{:else}
		<div class="table-wrap u-scroll">
			<table>
				<thead>
					<tr>
						<th>Skill</th>
						<th class="s-col">Central</th>
						{#each TOOLS as t (t.id)}<th class="s-col">
								{t.short}
							</th>{/each}
						<th class="act-col"></th>
					</tr>
				</thead>
				<tbody>
					{#each filtered as g (g.name)}
						{@const central = status(g.byTool.central)}
						<tr>
							<td>
								<div class="skill-name">
									<span class="mono strong">{g.name}</span>
									{#if g.description}<span class="desc">
											{g.description}
										</span>{/if}
								</div>
							</td>
							<td class="s-col">
								<span class="tag {central.cls}">
									{central.label}
								</span>
							</td>
							{#each TOOLS as t (t.id)}
								{@const st = status(g.byTool[t.id])}
								<td class="s-col">
									<button
										class="tag btn-tag {st.cls}"
										title={g.byTool[t.id]
											? g.byTool[t.id]!.isSymlink
												? 'Symlinked — click to unlink'
												: 'Real folder here'
											: 'Click to link from central'}
										onclick={() => cellClick(g, t.id)}
									>
										{st.label}
									</button>
								</td>
							{/each}
							<td class="act-col">
								<div class="row-actions">
									<button
										class="act"
										title="View SKILL.md"
										onclick={() => view(g)}
									>
										<Icon name="info" size={14} />
									</button>
									<button
										class="share"
										disabled={isShared(g)}
										title={isShared(g)
											? 'Already shared everywhere'
											: 'Share to all agents'}
										onclick={() => shareToAll(g)}
									>
										<Icon
											name={isShared(g)
												? 'check'
												: 'link'}
											size={13}
										/>
										{isShared(g)
											? 'Shared'
											: 'Share to all'}
									</button>
								</div>
							</td>
						</tr>
					{/each}
				</tbody>
			</table>

			{#if filtered.length === 0}
				<p class="no-match">No skills match “{query}”.</p>
			{/if}
		</div>
	{/if}
</div>

{#if viewing}
	<div
		class="overlay"
		role="button"
		tabindex="-1"
		onclick={() => (viewing = null)}
		onkeydown={(e) => e.key === 'Escape' && (viewing = null)}
	>
		<!-- svelte-ignore a11y_click_events_have_key_events, a11y_no_static_element_interactions -->
		<div
			class="viewer"
			role="dialog"
			tabindex="-1"
			onclick={(e) => e.stopPropagation()}
		>
			<header>
				<div class="v-title">
					<Icon name="file" size={14} />
					<span class="mono strong">{viewing.name}/SKILL.md</span>
				</div>
				<button
					class="x"
					aria-label="Close"
					onclick={() => (viewing = null)}
				>
					<Icon name="close" size={16} />
				</button>
			</header>
			<pre class="u-scroll">{viewing.content}</pre>
		</div>
	</div>
{/if}

<style lang="scss">
	.skills {
		display: flex;
		flex-direction: column;
		height: 100%;
	}

	.legend {
		color: var(--text-tertiary);
		font-size: rem(11.5);
		white-space: nowrap;

		code {
			font-family: var(--font-mono);
			font-size: rem(11);
			color: var(--text-secondary);
		}
	}

	.count {
		color: var(--text-tertiary);
		font-size: rem(11.5);
		font-variant-numeric: tabular-nums;
		white-space: nowrap;
	}

	.table-wrap {
		flex: 1;
		min-height: 0;
	}

	table {
		width: 100%;
		border-collapse: collapse;
		font-size: rem(13);
	}

	thead th {
		position: sticky;
		top: 0;
		z-index: 1;
		padding: rem(9) rem(16);
		color: var(--text-tertiary);
		font-size: rem(11);
		font-weight: 600;
		text-align: left;
		text-transform: uppercase;
		letter-spacing: 0.04em;
		background: var(--content-bg);
		backdrop-filter: blur(12px);
		border-bottom: 1px solid var(--border);
	}

	.s-col {
		width: rem(88);
	}
	.act-col {
		width: rem(170);
		text-align: right;
	}

	tbody td {
		padding: rem(8) rem(16);
		border-bottom: 1px solid var(--border);
		vertical-align: middle;
	}

	tbody tr:hover td {
		background: var(--hover);
	}

	.skill-name {
		display: flex;
		flex-direction: column;
		gap: rem(2);
	}

	.mono {
		font-family: var(--font-mono);
		font-size: rem(12.5);
		user-select: text;
	}
	.strong {
		font-weight: 600;
	}

	.desc {
		max-width: rem(340);
		overflow: hidden;
		color: var(--text-tertiary);
		font-size: rem(11.5);
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	.tag {
		display: inline-block;
		padding: rem(2) rem(9);
		font-size: rem(11);
		font-weight: 500;
		border-radius: 999px;
		border: 1px solid transparent;

		&.none {
			color: var(--text-tertiary);
			opacity: 0.5;
		}
		&.folder {
			color: var(--text-secondary);
			background: var(--surface-2);
			border-color: var(--border);
		}
		&.linked {
			color: var(--accent);
			background: color-mix(in srgb, var(--accent) 12%, transparent);
			border-color: color-mix(in srgb, var(--accent) 30%, transparent);
		}
		&.broken {
			color: var(--danger);
			background: color-mix(in srgb, var(--danger) 12%, transparent);
			border-color: color-mix(in srgb, var(--danger) 30%, transparent);
		}
	}

	.btn-tag {
		cursor: default;
		transition: filter 0.12s ease;
		&:hover {
			filter: brightness(1.15);
		}
		&.none:hover {
			opacity: 1;
			color: var(--accent);
		}
	}

	.row-actions {
		display: flex;
		justify-content: flex-end;
		align-items: center;
		gap: rem(6);
	}

	.act {
		display: flex;
		justify-content: center;
		align-items: center;
		width: rem(26);
		height: rem(26);
		color: var(--text-secondary);
		background: transparent;
		border: none;
		border-radius: var(--radius-sm);
		&:hover {
			background: var(--hover);
			color: var(--text);
		}
	}

	.share {
		display: inline-flex;
		align-items: center;
		gap: rem(5);
		padding: rem(5) rem(11);
		color: var(--accent);
		font-size: rem(12);
		background: color-mix(in srgb, var(--accent) 10%, transparent);
		border: 1px solid color-mix(in srgb, var(--accent) 28%, transparent);
		border-radius: var(--radius-sm);
		transition: all 0.12s ease;

		&:hover:not(:disabled) {
			background: color-mix(in srgb, var(--accent) 18%, transparent);
		}
		&:disabled {
			color: var(--success);
			background: color-mix(in srgb, var(--success) 10%, transparent);
			border-color: color-mix(in srgb, var(--success) 28%, transparent);
		}
	}

	.no-match {
		padding: rem(28) rem(16);
		color: var(--text-tertiary);
		font-size: rem(12.5);
		text-align: center;
	}

	/* Viewer ------------------------------------------------------------ */
	.overlay {
		position: fixed;
		inset: 0;
		z-index: 50;
		display: flex;
		justify-content: center;
		align-items: center;
		padding: rem(24);
		background: rgba(0, 0, 0, 0.35);
		backdrop-filter: blur(3px);
	}

	.viewer {
		display: flex;
		flex-direction: column;
		width: 100%;
		max-width: rem(640);
		max-height: 100%;
		background: var(--content-bg);
		backdrop-filter: blur(30px);
		border: 1px solid var(--border-strong);
		border-radius: var(--radius-lg);
		box-shadow: 0 20px 60px rgba(0, 0, 0, 0.4);

		header {
			display: flex;
			justify-content: space-between;
			align-items: center;
			padding: rem(12) rem(16);
			border-bottom: 1px solid var(--border);
		}

		pre {
			margin: 0;
			padding: rem(16);
			overflow: auto;
			color: var(--text-secondary);
			font-family: var(--font-mono);
			font-size: rem(12);
			line-height: 1.55;
			white-space: pre-wrap;
			word-break: break-word;
			user-select: text;
		}
	}

	.v-title {
		display: flex;
		align-items: center;
		gap: rem(8);
		color: var(--text-secondary);
	}

	.x {
		display: flex;
		color: var(--text-tertiary);
		background: transparent;
		border: none;
		&:hover {
			color: var(--text);
		}
	}
</style>
