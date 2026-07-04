<script lang="ts">
	import { ask } from '@tauri-apps/plugin-dialog'
	import Icon from '$components/Icon.svelte'
	import { agentsStore } from '$features/agents/agents.svelte'
	import { notify } from '$lib/notify'
	import { TOOLS, type McpServer, type ToolId } from '$features/agents/types'
	import McpEditor from './McpEditor.svelte'

	let selected = $state<{ name: string; tool: ToolId } | null>(null)
	let editor = $state<{
		initial: Partial<McpServer> | null
		fixedTool: ToolId | null
	} | null>(null)

	const names = $derived(agentsStore.mcpNames)

	const sel = $derived(
		selected ? agentsStore.mcpCell(selected.name, selected.tool) : null,
	)

	// Any known definition of a name, used to seed a "copy here" edit.
	function anyDef(name: string): McpServer | null {
		return (
			agentsStore.mcpServers.find((s) => s.name === name) ??
			agentsStore.disabled.find((s) => s.name === name) ??
			null
		)
	}

	function openCell(name: string, tool: ToolId) {
		const cell = agentsStore.mcpCell(name, tool)
		if (cell.configured) {
			selected = { name, tool }
		} else {
			// Copy an existing definition into this tool (pre-filled, editable).
			editor = { initial: anyDef(name), fixedTool: tool }
		}
	}

	async function toggle() {
		if (!sel?.server) return
		try {
			await agentsStore.mcpSetEnabled(sel.server, !sel.on)
		} catch (e) {
			await notify(
				'MCP error',
				e instanceof Error ? e.message : String(e),
			)
		}
	}

	async function remove() {
		if (!selected || !sel?.server) return
		const confirmed = await ask(
			`Remove “${selected.name}” from ${selected.tool}?`,
			{ title: 'Remove MCP server', kind: 'warning', okLabel: 'Remove' },
		)
		if (!confirmed) return
		try {
			await agentsStore.mcpRemove(selected.tool, selected.name)
			selected = null
		} catch (e) {
			await notify(
				'MCP error',
				e instanceof Error ? e.message : String(e),
			)
		}
	}

	async function copyTo(tool: ToolId) {
		if (!sel?.server) return
		try {
			await agentsStore.mcpSync(sel.server, [tool])
		} catch (e) {
			await notify(
				'MCP error',
				e instanceof Error ? e.message : String(e),
			)
		}
	}

	const missingTools = $derived(
		sel?.server
			? TOOLS.filter(
					(t) =>
						!agentsStore.mcpCell(sel.server!.name, t.id).configured,
				)
			: [],
	)
</script>

<div class="mcp">
	<div class="bar">
		<p class="hint">
			Each row is one MCP server; each column an agent. Click a cell to
			manage it, or an empty cell to copy the server there.
		</p>
		<button
			class="add"
			onclick={() => (editor = { initial: null, fixedTool: null })}
		>
			<Icon name="plus" size={14} /> Add server
		</button>
	</div>

	{#if names.length === 0}
		<div class="empty">No MCP servers configured in any agent yet.</div>
	{:else}
		<div class="table-wrap u-scroll">
			<table>
				<thead>
					<tr>
						<th class="name-col">Server</th>
						{#each TOOLS as t (t.id)}
							<th class="tool-col">{t.short}</th>
						{/each}
					</tr>
				</thead>
				<tbody>
					{#each names as name (name)}
						<tr>
							<td class="name-col mono">{name}</td>
							{#each TOOLS as t (t.id)}
								{@const cell = agentsStore.mcpCell(name, t.id)}
								<td class="tool-col">
									<button
										class="cell"
										class:on={cell.configured && cell.on}
										class:off={cell.configured && !cell.on}
										class:empty={!cell.configured}
										class:sel={selected?.name === name &&
											selected?.tool === t.id}
										title={cell.configured
											? cell.on
												? 'Enabled — click to manage'
												: 'Disabled — click to manage'
											: `Copy “${name}” to ${t.name}`}
										onclick={() => openCell(name, t.id)}
									>
										{#if cell.configured}
											<span class="dot"></span>
											{cell.on ? 'on' : 'off'}
										{:else}
											<Icon name="plus" size={12} />
										{/if}
									</button>
								</td>
							{/each}
						</tr>
					{/each}
				</tbody>
			</table>
		</div>
	{/if}

	{#if selected && sel?.server}
		{@const s = sel.server}
		<div class="drawer">
			<div class="drawer-head">
				<div class="title">
					<span class="mono strong">{s.name}</span>
					<span class="badge">{selected.tool}</span>
					<span class="badge soft">{s.transport}</span>
					<span
						class="badge"
						class:good={sel.on}
						class:muted={!sel.on}
					>
						{sel.on ? 'enabled' : 'disabled'}
					</span>
				</div>
				<button
					class="x"
					aria-label="Close"
					onclick={() => (selected = null)}
				>
					<Icon name="close" size={15} />
				</button>
			</div>

			<div class="def">
				{#if s.transport === 'http'}
					<div class="kv">
						<span>URL</span>
						<code>{s.url}</code>
					</div>
				{:else}
					<div class="kv">
						<span>Command</span>
						<code>{s.command} {s.args.join(' ')}</code>
					</div>
					{#if Object.keys(s.env).length}
						<div class="kv">
							<span>Env</span>
							<code>{Object.keys(s.env).join(', ')}</code>
						</div>
					{/if}
				{/if}
			</div>

			<div class="actions">
				<button class="btn" onclick={toggle}>
					<Icon name={sel.on ? 'close' : 'check'} size={13} />
					{sel.on ? 'Disable' : 'Enable'}
				</button>
				<button
					class="btn"
					onclick={() =>
						(editor = { initial: s, fixedTool: selected!.tool })}
				>
					<Icon name="edit" size={13} /> Edit
				</button>
				<button class="btn danger" onclick={remove}>
					<Icon name="trash" size={13} /> Remove
				</button>
				{#if missingTools.length}
					<span class="copy-label">Copy to:</span>
					{#each missingTools as t (t.id)}
						<button class="btn ghost" onclick={() => copyTo(t.id)}>
							<Icon name="external" size={12} />
							{t.short}
						</button>
					{/each}
				{/if}
			</div>
		</div>
	{/if}
</div>

{#if editor}
	<McpEditor
		initial={editor.initial}
		fixedTool={editor.fixedTool}
		onClose={() => (editor = null)}
	/>
{/if}

<style lang="scss">
	.mcp {
		display: flex;
		flex-direction: column;
		height: 100%;
	}

	.bar {
		display: flex;
		justify-content: space-between;
		align-items: center;
		gap: rem(12);
		flex-shrink: 0;
		padding: rem(12) rem(16);
		border-bottom: 1px solid var(--border);
	}

	.hint {
		color: var(--text-tertiary);
		font-size: rem(12);
		max-width: rem(520);
	}

	.add {
		display: inline-flex;
		align-items: center;
		gap: rem(5);
		flex-shrink: 0;
		padding: rem(6) rem(12);
		color: var(--accent-text);
		font-size: rem(12.5);
		font-weight: 500;
		background: var(--accent);
		border: none;
		border-radius: var(--radius-sm);
		&:hover {
			background: var(--accent-hover);
		}
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

	.tool-col {
		width: rem(110);
	}

	tbody td {
		padding: rem(6) rem(16);
		border-bottom: 1px solid var(--border);
	}

	tbody tr:hover td {
		background: var(--hover);
	}

	.name-col {
		font-weight: 500;
	}

	.mono {
		font-family: var(--font-mono);
		font-size: rem(12.5);
	}

	.cell {
		display: inline-flex;
		align-items: center;
		gap: rem(5);
		min-width: rem(52);
		padding: rem(3) rem(9);
		font-size: rem(11.5);
		background: transparent;
		border: 1px solid transparent;
		border-radius: 999px;
		transition: all 0.12s ease;

		.dot {
			width: rem(6);
			height: rem(6);
			border-radius: 50%;
			background: currentColor;
		}

		&.on {
			color: var(--success);
			background: color-mix(in srgb, var(--success) 12%, transparent);
			border-color: color-mix(in srgb, var(--success) 30%, transparent);
		}
		&.off {
			color: var(--text-tertiary);
			background: var(--surface-2);
			border-color: var(--border);
		}
		&.empty {
			color: var(--text-tertiary);
			opacity: 0.4;
			&:hover {
				opacity: 1;
				color: var(--accent);
			}
		}
		&.sel {
			outline: 2px solid var(--accent);
			outline-offset: 1px;
		}
	}

	.drawer {
		flex-shrink: 0;
		padding: rem(12) rem(16) rem(14);
		background: var(--surface-2);
		border-top: 1px solid var(--border);
	}

	.drawer-head {
		display: flex;
		justify-content: space-between;
		align-items: center;
		margin-bottom: rem(10);
	}

	.title {
		display: flex;
		align-items: center;
		gap: rem(8);
		flex-wrap: wrap;
	}

	.strong {
		font-weight: 600;
	}

	.badge {
		padding: rem(2) rem(8);
		color: var(--text-secondary);
		font-size: rem(10.5);
		font-weight: 600;
		text-transform: uppercase;
		letter-spacing: 0.03em;
		background: var(--surface);
		border: 1px solid var(--border);
		border-radius: 999px;

		&.soft {
			color: var(--text-tertiary);
		}
		&.good {
			color: var(--success);
			border-color: color-mix(in srgb, var(--success) 35%, transparent);
		}
		&.muted {
			color: var(--text-tertiary);
		}
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

	.def {
		display: flex;
		flex-direction: column;
		gap: rem(6);
		margin-bottom: rem(12);
	}

	.kv {
		display: flex;
		gap: rem(10);
		font-size: rem(12);

		span {
			flex-shrink: 0;
			width: rem(64);
			color: var(--text-tertiary);
			text-transform: uppercase;
			font-size: rem(10.5);
			font-weight: 600;
			padding-top: rem(2);
		}
		code {
			font-family: var(--font-mono);
			font-size: rem(12);
			color: var(--text);
			word-break: break-all;
			user-select: text;
		}
	}

	.actions {
		display: flex;
		align-items: center;
		flex-wrap: wrap;
		gap: rem(6);
	}

	.copy-label {
		margin-left: rem(6);
		color: var(--text-tertiary);
		font-size: rem(11.5);
	}

	.btn {
		display: inline-flex;
		align-items: center;
		gap: rem(5);
		padding: rem(5) rem(11);
		color: var(--text-secondary);
		font-size: rem(12);
		background: var(--surface);
		border: 1px solid var(--border);
		border-radius: var(--radius-sm);
		transition: all 0.12s ease;

		&:hover {
			color: var(--text);
			border-color: var(--border-strong);
		}
		&.danger:hover {
			color: var(--danger);
			border-color: color-mix(in srgb, var(--danger) 40%, transparent);
		}
		&.ghost {
			color: var(--text-tertiary);
		}
	}
</style>
