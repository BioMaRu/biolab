<script lang="ts">
	import { fly } from 'svelte/transition'
	import { ask } from '@tauri-apps/plugin-dialog'
	import Icon from '$components/Icon.svelte'
	import { agentsStore } from '$features/agents/agents.svelte'
	import { notify } from '$lib/notify'
	import { TOOLS, type McpServer, type ToolId } from '$features/agents/types'
	import McpEditor from './McpEditor.svelte'
	import PanelToolbar from '$components/PanelToolbar.svelte'
	import SearchField from '$components/SearchField.svelte'
	import EmptyState from '$components/EmptyState.svelte'

	let selected = $state<{ name: string; tool: ToolId } | null>(null)
	let editor = $state<{
		initial: Partial<McpServer> | null
		fixedTool: ToolId | null
	} | null>(null)
	let query = $state('')

	const names = $derived(agentsStore.mcpNames)
	const filtered = $derived(
		names.filter((n) => n.toLowerCase().includes(query.toLowerCase())),
	)

	const sel = $derived(
		selected ? agentsStore.mcpCell(selected.name, selected.tool) : null,
	)

	// How many agents run each server — shown as a small "reach" hint per row.
	const reachOf = (name: string) =>
		new Set(
			[...agentsStore.mcpServers, ...agentsStore.disabled]
				.filter((s) => s.name === name)
				.map((s) => s.tool),
		).size

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

	const toolName = (id: string) => TOOLS.find((t) => t.id === id)?.name ?? id
</script>

<div class="mcp">
	<PanelToolbar>
		{#snippet start()}
			<SearchField bind:value={query} placeholder="Filter servers…" />
			{#if names.length}
				<span class="count">
					{filtered.length} of {names.length}
				</span>
			{/if}
		{/snippet}
		{#snippet end()}
			<button
				class="add"
				onclick={() => (editor = { initial: null, fixedTool: null })}
			>
				<Icon name="plus" size={14} /> Add server
			</button>
		{/snippet}
	</PanelToolbar>

	{#if names.length === 0}
		<EmptyState
			icon="plug"
			title="No MCP servers yet"
			hint="Connect a Model Context Protocol server to give your agents new tools — filesystems, browsers, databases and more."
		>
			{#snippet action()}
				<button
					class="add"
					onclick={() =>
						(editor = { initial: null, fixedTool: null })}
				>
					<Icon name="plus" size={14} /> Add your first server
				</button>
			{/snippet}
		</EmptyState>
	{:else}
		<div class="mcp-body">
			<div class="matrix-wrap u-scroll">
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
						{#each filtered as name (name)}
							{@const reach = reachOf(name)}
							<tr>
								<td class="name-col">
									<div class="server-name">
										<span class="mono">{name}</span>
										<span class="reach">
											{reach}/{TOOLS.length} agents
										</span>
									</div>
								</td>
								{#each TOOLS as t (t.id)}
									{@const cell = agentsStore.mcpCell(
										name,
										t.id,
									)}
									<td class="tool-col">
										<button
											class="cell"
											class:on={cell.configured &&
												cell.on}
											class:off={cell.configured &&
												!cell.on}
											class:empty={!cell.configured}
											class:sel={selected?.name ===
												name && selected?.tool === t.id}
											title={cell.configured
												? cell.on
													? 'Enabled — click to manage'
													: 'Disabled — click to manage'
												: `Copy “${name}” to ${t.name}`}
											onclick={() => openCell(name, t.id)}
										>
											{#if cell.configured}
												<span class="dot"></span>
												{cell.on ? 'On' : 'Off'}
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

				{#if filtered.length === 0}
					<p class="no-match">No servers match “{query}”.</p>
				{/if}
			</div>

			{#if selected && sel?.server}
				{@const s = sel.server}
				<aside
					class="inspector"
					transition:fly={{ x: 16, duration: 150 }}
				>
					<div class="ins-head">
						<div class="ins-title">
							<span class="mono strong">{s.name}</span>
							<span class="ins-sub">
								in {toolName(selected.tool)}
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

					<div class="ins-body u-scroll">
						<div class="badges">
							<span class="badge soft">
								<Icon
									name={s.transport === 'http'
										? 'globe'
										: 'terminal'}
									size={11}
								/>
								{s.transport}
							</span>
							<span
								class="badge"
								class:good={sel.on}
								class:muted={!sel.on}
							>
								{sel.on ? 'enabled' : 'disabled'}
							</span>
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
										<code>
											{Object.keys(s.env).join(', ')}
										</code>
									</div>
								{/if}
							{/if}
						</div>

						<div class="ins-actions">
							<button
								class="switch"
								class:on={sel.on}
								role="switch"
								aria-checked={sel.on}
								onclick={toggle}
							>
								<span class="sw-label">
									{sel.on ? 'Enabled' : 'Disabled'}
								</span>
								<span class="sw-track">
									<span class="sw-knob"></span>
								</span>
							</button>

							<div class="btn-row">
								<button
									class="btn"
									onclick={() =>
										(editor = {
											initial: s,
											fixedTool: selected!.tool,
										})}
								>
									<Icon name="edit" size={13} /> Edit
								</button>
								<button class="btn danger" onclick={remove}>
									<Icon name="trash" size={13} /> Remove
								</button>
							</div>
						</div>

						{#if missingTools.length}
							<div class="copy-block">
								<span class="copy-title">
									Copy to other agents
								</span>
								{#each missingTools as t (t.id)}
									<button
										class="copy-row"
										onclick={() => copyTo(t.id)}
									>
										<Icon name="external" size={13} />
										<span>{t.name}</span>
										<Icon name="plus" size={13} />
									</button>
								{/each}
							</div>
						{/if}
					</div>
				</aside>
			{/if}
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

	.count {
		color: var(--text-tertiary);
		font-size: rem(11.5);
		font-variant-numeric: tabular-nums;
		white-space: nowrap;
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
		transition: background-color 0.12s ease;
		&:hover {
			background: var(--accent-hover);
		}
	}

	.mcp-body {
		display: flex;
		flex: 1;
		min-height: 0;
	}

	.matrix-wrap {
		flex: 1;
		min-width: 0;
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

	.tool-col {
		width: rem(104);
	}

	tbody td {
		padding: rem(7) rem(16);
		border-bottom: 1px solid var(--border);
	}

	tbody tr:hover td {
		background: var(--hover);
	}

	.server-name {
		display: flex;
		flex-direction: column;
		gap: rem(2);
	}

	.mono {
		font-family: var(--font-mono);
		font-size: rem(12.5);
		user-select: text;
	}

	.reach {
		color: var(--text-tertiary);
		font-size: rem(10.5);
	}

	.cell {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		gap: rem(5);
		min-width: rem(56);
		padding: rem(4) rem(10);
		font-size: rem(11.5);
		font-weight: 500;
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
				background: color-mix(in srgb, var(--accent) 10%, transparent);
			}
		}
		&.sel {
			box-shadow: 0 0 0 2px var(--accent);
		}
	}

	.no-match {
		padding: rem(28) rem(16);
		color: var(--text-tertiary);
		font-size: rem(12.5);
		text-align: center;
	}

	/* Inspector --------------------------------------------------------- */
	.inspector {
		display: flex;
		flex-direction: column;
		width: rem(304);
		flex-shrink: 0;
		background: var(--surface-2);
		border-left: 1px solid var(--border);
	}

	.ins-head {
		display: flex;
		justify-content: space-between;
		align-items: flex-start;
		gap: rem(8);
		flex-shrink: 0;
		padding: rem(13) rem(14);
		border-bottom: 1px solid var(--border);
	}

	.ins-title {
		display: flex;
		flex-direction: column;
		gap: rem(2);
		min-width: 0;

		.strong {
			overflow: hidden;
			font-weight: 600;
			text-overflow: ellipsis;
			white-space: nowrap;
		}
	}

	.ins-sub {
		color: var(--text-tertiary);
		font-size: rem(11.5);
	}

	.x {
		display: flex;
		flex-shrink: 0;
		color: var(--text-tertiary);
		background: transparent;
		border: none;
		&:hover {
			color: var(--text);
		}
	}

	.ins-body {
		display: flex;
		flex-direction: column;
		gap: rem(14);
		flex: 1;
		min-height: 0;
		padding: rem(14);
		overflow-y: auto;
	}

	.badges {
		display: flex;
		flex-wrap: wrap;
		gap: rem(6);
	}

	.badge {
		display: inline-flex;
		align-items: center;
		gap: rem(4);
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

	.def {
		display: flex;
		flex-direction: column;
		gap: rem(10);
	}

	.kv {
		display: flex;
		flex-direction: column;
		gap: rem(4);

		span {
			color: var(--text-tertiary);
			text-transform: uppercase;
			font-size: rem(10.5);
			font-weight: 600;
			letter-spacing: 0.03em;
		}
		code {
			padding: rem(7) rem(9);
			color: var(--text);
			font-family: var(--font-mono);
			font-size: rem(11.5);
			line-height: 1.45;
			background: var(--surface);
			border: 1px solid var(--border);
			border-radius: var(--radius-sm);
			word-break: break-all;
			user-select: text;
		}
	}

	.ins-actions {
		display: flex;
		flex-direction: column;
		gap: rem(8);
		padding-top: rem(12);
		border-top: 1px solid var(--border);
	}

	.switch {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: rem(8);
		padding: rem(8) rem(11);
		background: var(--surface);
		border: 1px solid var(--border);
		border-radius: var(--radius-sm);

		.sw-label {
			font-size: rem(12.5);
			font-weight: 500;
		}

		.sw-track {
			position: relative;
			width: rem(34);
			height: rem(20);
			flex-shrink: 0;
			background: var(--border-strong);
			border-radius: 999px;
			transition: background-color 0.16s ease;
		}
		.sw-knob {
			position: absolute;
			top: rem(2);
			left: rem(2);
			width: rem(16);
			height: rem(16);
			background: #fff;
			border-radius: 50%;
			box-shadow: 0 1px 2px rgba(0, 0, 0, 0.3);
			transition: transform 0.16s ease;
		}
		&.on .sw-track {
			background: var(--success);
		}
		&.on .sw-knob {
			transform: translateX(rem(14));
		}
	}

	.btn-row {
		display: flex;
		gap: rem(6);
	}

	.btn {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		gap: rem(5);
		flex: 1;
		padding: rem(7) rem(11);
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
	}

	.copy-block {
		display: flex;
		flex-direction: column;
		gap: rem(6);
		padding-top: rem(12);
		border-top: 1px solid var(--border);
	}

	.copy-title {
		color: var(--text-tertiary);
		font-size: rem(10.5);
		font-weight: 600;
		text-transform: uppercase;
		letter-spacing: 0.03em;
	}

	.copy-row {
		display: flex;
		align-items: center;
		gap: rem(8);
		padding: rem(7) rem(10);
		color: var(--text-secondary);
		font-size: rem(12.5);
		background: var(--surface);
		border: 1px solid var(--border);
		border-radius: var(--radius-sm);
		transition: all 0.12s ease;

		span {
			flex: 1;
			text-align: left;
		}
		:global(svg:last-child) {
			color: var(--text-tertiary);
		}
		&:hover {
			color: var(--accent);
			border-color: color-mix(in srgb, var(--accent) 40%, transparent);
			background: color-mix(in srgb, var(--accent) 8%, transparent);
			:global(svg:last-child) {
				color: var(--accent);
			}
		}
	}
</style>
