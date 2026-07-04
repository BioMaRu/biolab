<script lang="ts">
	import { ask } from '@tauri-apps/plugin-dialog'
	import Icon from '$components/Icon.svelte'
	import { agentsStore } from '$features/agents/agents.svelte'
	import { notify } from '$lib/notify'
	import { tildePath } from '$features/agents/format'

	const links = $derived(agentsStore.inventory?.symlinks ?? [])
	const brokenCount = $derived(links.filter((l) => l.broken).length)

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
	<p class="hint">
		Every symlink across your agents' skill and agent folders.
		{#if brokenCount > 0}
			<span class="warn">
				<Icon name="alert" size={12} />
				{brokenCount} broken — the target no longer exists.
			</span>
		{/if}
	</p>

	{#if links.length === 0}
		<div class="empty">No symlinks found.</div>
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
					{#each links as l (l.path)}
						<tr class:broken={l.broken}>
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
		</div>
	{/if}
</div>

<style lang="scss">
	.symlinks {
		display: flex;
		flex-direction: column;
		height: 100%;
	}

	.hint {
		display: flex;
		align-items: center;
		gap: rem(10);
		flex-shrink: 0;
		padding: rem(12) rem(16);
		color: var(--text-tertiary);
		font-size: rem(12);
		border-bottom: 1px solid var(--border);
	}

	.warn {
		display: inline-flex;
		align-items: center;
		gap: rem(4);
		color: var(--danger);
		font-weight: 500;
	}

	.empty {
		display: flex;
		justify-content: center;
		align-items: center;
		flex: 1;
		color: var(--text-tertiary);
		font-size: rem(13);
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
		padding: rem(8) rem(16);
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
		padding: rem(7) rem(16);
		border-bottom: 1px solid var(--border);
		white-space: nowrap;
	}

	tbody tr:hover td {
		background: var(--hover);
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
</style>
