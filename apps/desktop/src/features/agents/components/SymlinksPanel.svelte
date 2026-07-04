<script lang="ts">
	import { ask } from '@tauri-apps/plugin-dialog'
	import Icon from '$components/Icon.svelte'
	import { agentsStore } from '$features/agents/agents.svelte'
	import { notify } from '$lib/notify'
	import { tildePath } from '$features/agents/format'
	import PanelToolbar from '$components/PanelToolbar.svelte'
	import SearchField from '$components/SearchField.svelte'
	import EmptyState from '$components/EmptyState.svelte'

	const links = $derived(agentsStore.inventory?.symlinks ?? [])
	const brokenCount = $derived(links.filter((l) => l.broken).length)

	let query = $state('')
	let brokenOnly = $state(false)

	const filtered = $derived(
		links.filter((l) => {
			if (brokenOnly && !l.broken) return false
			const q = query.toLowerCase()
			if (!q) return true
			return (
				l.path.toLowerCase().includes(q) ||
				l.resolved.toLowerCase().includes(q) ||
				l.tool.toLowerCase().includes(q) ||
				l.category.toLowerCase().includes(q)
			)
		}),
	)

	let repairing = $state<string | null>(null)
	let repairTarget = $state('')

	function startRepair(path: string, current: string) {
		repairing = path
		repairTarget = current
	}

	async function commitRepair(path: string) {
		if (!repairTarget.trim()) return
		try {
			await agentsStore.symlinkRepair(path, repairTarget.trim())
			repairing = null
		} catch (e) {
			await notify(
				'Repair failed',
				e instanceof Error ? e.message : String(e),
			)
		}
	}

	async function remove(path: string) {
		const ok = await ask(`Remove this symlink?\n${tildePath(path)}`, {
			title: 'Remove symlink',
			kind: 'warning',
			okLabel: 'Remove',
		})
		if (!ok) return
		try {
			await agentsStore.symlinkRemove(path)
		} catch (e) {
			await notify(
				'Remove failed',
				e instanceof Error ? e.message : String(e),
			)
		}
	}
</script>

<div class="symlinks">
	<PanelToolbar>
		{#snippet start()}
			<SearchField bind:value={query} placeholder="Filter links…" />
			{#if brokenCount > 0}
				<button
					class="filter"
					class:on={brokenOnly}
					onclick={() => (brokenOnly = !brokenOnly)}
				>
					<Icon name="alert" size={12} />
					{brokenCount} broken
				</button>
			{/if}
		{/snippet}
		{#snippet end()}
			{#if links.length}
				<span class="count">{filtered.length} of {links.length}</span>
			{/if}
		{/snippet}
	</PanelToolbar>

	{#if links.length === 0}
		<EmptyState
			icon="link"
			title="No symlinks found"
			hint="Symlinks across your agents' skill and command folders show up here — including any that have gone stale."
		/>
	{:else}
		<div class="table-wrap u-scroll">
			<table>
				<thead>
					<tr>
						<th>Link</th>
						<th>Target</th>
						<th class="col-tool">Where</th>
						<th class="col-status">Status</th>
						<th class="col-actions"></th>
					</tr>
				</thead>
				<tbody>
					{#each filtered as l (l.path)}
						<tr class:is-broken={l.broken}>
							<td class="mono">{tildePath(l.path)}</td>
							<td class="mono muted">
								{#if repairing === l.path}
									<input
										class="repair-input"
										bind:value={repairTarget}
										spellcheck="false"
										autocorrect="off"
										onkeydown={(e) => {
											if (e.key === 'Enter')
												commitRepair(l.path)
											else if (e.key === 'Escape')
												repairing = null
										}}
									/>
								{:else}
									→ {tildePath(l.resolved)}
								{/if}
							</td>
							<td class="col-tool">
								<span class="chip">{l.tool}</span>
								<span class="cat">{l.category}</span>
							</td>
							<td class="col-status">
								{#if l.broken}
									<span class="tag broken">broken</span>
								{:else}
									<span class="tag ok">ok</span>
								{/if}
							</td>
							<td class="col-actions">
								<div class="row-actions">
									{#if repairing === l.path}
										<button
											class="act"
											title="Save"
											onclick={() => commitRepair(l.path)}
										>
											<Icon name="check" size={14} />
										</button>
										<button
											class="act"
											title="Cancel"
											onclick={() => (repairing = null)}
										>
											<Icon name="close" size={14} />
										</button>
									{:else}
										<button
											class="act"
											title="Repair (repoint)"
											onclick={() =>
												startRepair(l.path, l.resolved)}
										>
											<Icon name="edit" size={14} />
										</button>
										<button
											class="act danger"
											title="Remove"
											onclick={() => remove(l.path)}
										>
											<Icon name="trash" size={14} />
										</button>
									{/if}
								</div>
							</td>
						</tr>
					{/each}
				</tbody>
			</table>

			{#if filtered.length === 0}
				<p class="no-match">
					{brokenOnly
						? 'No broken links — nice.'
						: `No links match “${query}”.`}
				</p>
			{/if}
		</div>
	{/if}
</div>

<style lang="scss">
	.symlinks {
		display: flex;
		flex-direction: column;
		height: 100%;
	}

	.filter {
		display: inline-flex;
		align-items: center;
		gap: rem(5);
		padding: rem(5) rem(10);
		color: var(--danger);
		font-size: rem(12);
		font-weight: 500;
		background: color-mix(in srgb, var(--danger) 10%, transparent);
		border: 1px solid color-mix(in srgb, var(--danger) 26%, transparent);
		border-radius: var(--radius-sm);
		transition: all 0.12s ease;

		&:hover {
			background: color-mix(in srgb, var(--danger) 16%, transparent);
		}
		&.on {
			color: var(--accent-text);
			background: var(--danger);
			border-color: var(--danger);
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

	.col-tool {
		width: rem(140);
	}
	.col-status {
		width: rem(80);
	}
	.col-actions {
		width: rem(84);
		text-align: right;
	}

	tbody td {
		padding: rem(8) rem(16);
		border-bottom: 1px solid var(--border);
		white-space: nowrap;
	}

	tbody tr:hover td {
		background: var(--hover);
	}

	tbody tr.is-broken .mono:first-child {
		color: var(--danger);
	}

	.mono {
		font-family: var(--font-mono);
		font-size: rem(12);
		user-select: text;
	}
	.muted {
		color: var(--text-secondary);
	}

	.chip {
		padding: rem(2) rem(8);
		color: var(--text-secondary);
		font-size: rem(10.5);
		font-weight: 600;
		text-transform: uppercase;
		background: var(--surface-2);
		border: 1px solid var(--border);
		border-radius: 999px;
	}

	.cat {
		margin-left: rem(6);
		color: var(--text-tertiary);
		font-size: rem(11);
	}

	.tag {
		padding: rem(2) rem(9);
		font-size: rem(11);
		font-weight: 500;
		border-radius: 999px;

		&.ok {
			color: var(--success);
			background: color-mix(in srgb, var(--success) 12%, transparent);
		}
		&.broken {
			color: var(--danger);
			background: color-mix(in srgb, var(--danger) 12%, transparent);
		}
	}

	.repair-input {
		width: 100%;
		padding: rem(4) rem(8);
		color: var(--text);
		font-family: var(--font-mono);
		font-size: rem(12);
		background: var(--surface-2);
		border: 1px solid var(--accent);
		border-radius: var(--radius-sm);
		outline: none;
		user-select: text;
	}

	.row-actions {
		display: flex;
		justify-content: flex-end;
		gap: rem(4);
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
		&.danger:hover {
			color: var(--danger);
		}
	}

	.no-match {
		padding: rem(28) rem(16);
		color: var(--text-tertiary);
		font-size: rem(12.5);
		text-align: center;
	}
</style>
