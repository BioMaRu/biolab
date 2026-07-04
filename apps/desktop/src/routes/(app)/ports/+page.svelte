<script lang="ts">
	import { onMount } from 'svelte'
	import { ask } from '@tauri-apps/plugin-dialog'
	import Icon from '$components/Icon.svelte'
	import PanelToolbar from '$components/PanelToolbar.svelte'
	import SearchField from '$components/SearchField.svelte'
	import EmptyState from '$components/EmptyState.svelte'
	import { portsStore } from '$features/ports/ports.svelte'
	import { killProcess } from '$features/ports/api'
	import { notify } from '$lib/notify'
	import { copyText } from '$lib/clipboard'
	import { COMMON_PORTS } from '$constants/common-ports'
	import { configStore } from '$features/settings/config.svelte'
	import type { PortInfo } from '$features/ports/types'

	let busyPid = $state<number | null>(null)
	let expandedKey = $state<string | null>(null)
	let copied = $state<string | null>(null)
	let addingPort = $state(false)
	let newQuickPort = $state('')

	const rowKey = (p: PortInfo) => `${p.pid}:${p.port}:${p.address}`

	// A quick-kill chip is a user favorite (removable) if it isn't a built-in port.
	const isCustom = (port: number) => !COMMON_PORTS.includes(port)

	function commitAddPort() {
		const n = parseInt(newQuickPort.trim(), 10)
		if (!Number.isNaN(n)) configStore.addFavorite(n)
		newQuickPort = ''
		addingPort = false
	}

	function cancelAddPort() {
		newQuickPort = ''
		addingPort = false
	}

	function focusOnMount(node: HTMLInputElement) {
		node.focus()
	}

	const quickKillPorts = $derived(
		[...new Set([...COMMON_PORTS, ...configStore.favoritePorts])].sort(
			(a, b) => a - b,
		),
	)

	onMount(() => {
		void portsStore.refresh()
	})

	// Auto-refresh follows the user's config (toggle + interval), reactively.
	$effect(() => {
		if (configStore.autoRefresh) {
			portsStore.startAutoRefresh(configStore.refreshIntervalMs)
		} else {
			portsStore.stopAutoRefresh()
		}
		return () => portsStore.stopAutoRefresh()
	})

	async function killPort(p: PortInfo, force: boolean) {
		const label = `${p.processName} (PID ${p.pid}) on port ${p.port}`
		const confirmed = await ask(
			`${force ? 'Force kill' : 'Kill'} ${label}?`,
			{
				title: force ? 'Force Kill Process' : 'Kill Process',
				kind: 'warning',
				okLabel: force ? 'Force Kill' : 'Kill',
				cancelLabel: 'Cancel',
			},
		)
		if (!confirmed) return

		busyPid = p.pid
		try {
			await killProcess(p.pid, force)
			await portsStore.refresh()
			await notify('Port freed', `Killed ${label}`)
		} catch (e) {
			await notify(
				'Kill failed',
				e instanceof Error ? e.message : String(e),
			)
		} finally {
			busyPid = null
		}
	}

	async function quickKill(port: number) {
		const matches = portsStore.ports.filter((p) => p.port === port)
		if (matches.length === 0) return

		const names = [...new Set(matches.map((m) => m.processName))].join(', ')
		const what = matches.length > 1 ? `${matches.length} processes` : names
		const confirmed = await ask(`Kill ${what} on port ${port}?`, {
			title: 'Kill Process',
			kind: 'warning',
			okLabel: 'Kill',
			cancelLabel: 'Cancel',
		})
		if (!confirmed) return

		try {
			for (const m of matches) {
				await killProcess(m.pid, false)
			}
			await portsStore.refresh()
			await notify('Port freed', `Freed port ${port} (${names})`)
		} catch (e) {
			await notify(
				'Kill failed',
				e instanceof Error ? e.message : String(e),
			)
		}
	}

	function toggleDetails(p: PortInfo) {
		const k = rowKey(p)
		expandedKey = expandedKey === k ? null : k
	}

	async function copyField(id: string, value: string) {
		await copyText(value)
		copied = id
		setTimeout(() => {
			if (copied === id) copied = null
		}, 1200)
	}
</script>

<div class="ports">
	<PanelToolbar>
		{#snippet start()}
			<SearchField
				grow
				value={portsStore.query}
				oninput={(v) => (portsStore.query = v)}
				placeholder="Filter by port, process, PID, address…"
			/>
		{/snippet}
		{#snippet end()}
			<span class="count">
				{#if portsStore.query.trim()}
					{portsStore.filtered.length} of {portsStore.ports.length}
				{:else}
					{portsStore.ports.length} listening
				{/if}
			</span>
			<button
				class="icon-btn"
				class:spinning={portsStore.refreshing}
				title="Refresh"
				aria-label="Refresh"
				onclick={() => portsStore.refresh()}
			>
				<Icon name="refresh" size={15} />
			</button>
		{/snippet}
	</PanelToolbar>

	<div class="quick-kill u-scroll">
		<span class="qk-label"><Icon name="zap" size={13} /> Quick-kill</span>
		{#each quickKillPorts as port (port)}
			{@const active = portsStore.ports.some((p) => p.port === port)}
			<span class="chip-wrap">
				<button
					class="chip"
					class:active
					disabled={!active}
					title={active
						? `Kill process on port ${port}`
						: `Port ${port} is free`}
					onclick={() => quickKill(port)}
				>
					{port}
				</button>
				{#if isCustom(port)}
					<button
						class="chip-remove"
						title="Remove favorite"
						aria-label={`Remove favorite port ${port}`}
						onclick={() => configStore.removeFavorite(port)}
					>
						×
					</button>
				{/if}
			</span>
		{/each}

		{#if addingPort}
			<input
				class="qk-input"
				type="text"
				inputmode="numeric"
				placeholder="port"
				bind:value={newQuickPort}
				use:focusOnMount
				onkeydown={(e) => {
					if (e.key === 'Enter') commitAddPort()
					else if (e.key === 'Escape') cancelAddPort()
				}}
				onblur={commitAddPort}
			/>
		{:else}
			<button
				class="qk-add"
				title="Add a custom quick-kill port"
				aria-label="Add custom port"
				onclick={() => (addingPort = true)}
			>
				+
			</button>
		{/if}
	</div>

	{#if portsStore.error}
		<div class="banner error">
			<Icon name="alert" size={14} />
			<span>{portsStore.error}</span>
			<button class="banner-retry" onclick={() => portsStore.refresh()}>
				Retry
			</button>
		</div>
	{/if}

	<div class="table-wrap u-scroll">
		{#if portsStore.loading}
			<div class="state">
				<span class="spinner"></span>
				Loading ports…
			</div>
		{:else if portsStore.filtered.length === 0}
			{#if portsStore.query.trim()}
				<EmptyState
					icon="search"
					title="No matching ports"
					hint={`Nothing matches “${portsStore.query}”. Try a different port, process, PID, or address.`}
				/>
			{:else}
				<EmptyState
					icon="ports"
					title="No listening ports"
					hint="Nothing is bound right now. Start a dev server and hit refresh to see it here."
				/>
			{/if}
		{:else}
			<table>
				<thead>
					<tr>
						<th class="col-port">Port</th>
						<th>Process</th>
						<th class="col-pid">PID</th>
						<th class="col-proto">Proto</th>
						<th>Address</th>
						<th class="col-actions"></th>
					</tr>
				</thead>
				<tbody>
					{#each portsStore.filtered as p (rowKey(p))}
						<tr class:busy={busyPid === p.pid}>
							<td class="col-port mono">{p.port}</td>
							<td class="proc" title={p.command}>
								{p.processName}
							</td>
							<td class="col-pid mono">{p.pid}</td>
							<td class="col-proto">{p.protocol}</td>
							<td class="mono addr">{p.address}</td>
							<td class="col-actions">
								<div
									class="row-actions"
									class:pinned={expandedKey === rowKey(p)}
								>
									<button
										class="act"
										class:on={expandedKey === rowKey(p)}
										title="Details"
										aria-label="Details"
										onclick={() => toggleDetails(p)}
									>
										<Icon name="info" size={14} />
									</button>
									<button
										class="act kill"
										title="Kill (SIGTERM)"
										aria-label="Kill process"
										disabled={busyPid !== null}
										onclick={() => killPort(p, false)}
									>
										<Icon name="trash" size={14} />
									</button>
									<button
										class="act force"
										title="Force kill (SIGKILL)"
										aria-label="Force kill process"
										disabled={busyPid !== null}
										onclick={() => killPort(p, true)}
									>
										<Icon name="zap" size={14} />
									</button>
								</div>
							</td>
						</tr>
						{#if expandedKey === rowKey(p)}
							<tr class="detail-row">
								<td colspan="6">
									<div class="detail">
										<div class="field">
											<span class="label">Command</span>
											<code class="value">
												{p.command}
											</code>
										</div>
										<div class="field-row">
											<div class="field">
												<span class="label">User</span>
												<span class="value">
													{p.user || '—'}
												</span>
											</div>
											<div class="copy-actions">
												<button
													class="copy-btn"
													onclick={() =>
														copyField(
															rowKey(p) + ':pid',
															String(p.pid),
														)}
												>
													<Icon
														name="copy"
														size={13}
													/>
													{copied ===
													rowKey(p) + ':pid'
														? 'Copied'
														: 'Copy PID'}
												</button>
												<button
													class="copy-btn"
													onclick={() =>
														copyField(
															rowKey(p) + ':cmd',
															p.command,
														)}
												>
													<Icon
														name="copy"
														size={13}
													/>
													{copied ===
													rowKey(p) + ':cmd'
														? 'Copied'
														: 'Copy command'}
												</button>
											</div>
										</div>
									</div>
								</td>
							</tr>
						{/if}
					{/each}
				</tbody>
			</table>
		{/if}
	</div>
</div>

<style lang="scss">
	.ports {
		display: flex;
		flex-direction: column;
		height: 100%;
	}

	.count {
		color: var(--text-secondary);
		font-size: rem(12.5);
		font-variant-numeric: tabular-nums;
	}

	.icon-btn {
		display: flex;
		justify-content: center;
		align-items: center;
		width: rem(30);
		height: rem(30);
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

	.quick-kill {
		display: flex;
		align-items: center;
		gap: rem(6);
		flex-shrink: 0;
		padding: rem(10) rem(16);
		overflow-x: auto;
		white-space: nowrap;
		border-bottom: 1px solid var(--border);
	}

	.qk-label {
		display: inline-flex;
		align-items: center;
		gap: rem(4);
		margin-right: rem(4);
		color: var(--text-tertiary);
		font-size: rem(11.5);
		font-weight: 600;
		text-transform: uppercase;
		letter-spacing: 0.04em;
	}

	.chip {
		flex-shrink: 0;
		padding: rem(4) rem(10);
		color: var(--text-tertiary);
		font-family: var(--font-mono);
		font-size: rem(12);
		font-variant-numeric: tabular-nums;
		background: var(--surface-2);
		border: 1px solid var(--border);
		border-radius: 999px;
		transition: all 0.12s ease;

		&.active {
			color: var(--danger);
			background: color-mix(in srgb, var(--danger) 12%, transparent);
			border-color: color-mix(in srgb, var(--danger) 35%, transparent);

			&:hover {
				color: var(--accent-text);
				background: var(--danger);
			}
		}

		&:disabled {
			cursor: default;
			opacity: 0.55;
		}
	}

	.chip-wrap {
		position: relative;
		flex-shrink: 0;
	}

	.chip-remove {
		position: absolute;
		top: rem(-5);
		right: rem(-5);
		display: flex;
		justify-content: center;
		align-items: center;
		width: rem(15);
		height: rem(15);
		color: var(--text);
		font-size: rem(11);
		line-height: 1;
		background: var(--border-strong);
		border: 1px solid var(--content-bg);
		border-radius: 50%;
		opacity: 0;
		transition: opacity 0.12s ease;
	}

	.chip-wrap:hover .chip-remove {
		opacity: 1;
	}

	.chip-remove:hover {
		color: #fff;
		background: var(--danger);
	}

	.qk-add {
		flex-shrink: 0;
		padding: rem(4) rem(11);
		color: var(--text-tertiary);
		font-size: rem(14);
		line-height: 1;
		background: var(--surface-2);
		border: 1px dashed var(--border-strong);
		border-radius: 999px;
		transition: color 0.12s ease;

		&:hover {
			color: var(--text);
		}
	}

	.qk-input {
		flex-shrink: 0;
		width: rem(70);
		padding: rem(4) rem(10);
		color: var(--text);
		font-family: var(--font-mono);
		font-size: rem(12);
		background: var(--surface-2);
		border: 1px solid var(--accent);
		border-radius: 999px;
		outline: none;
		user-select: text;
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

	.table-wrap {
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
		white-space: nowrap;
		background: var(--content-bg);
		backdrop-filter: blur(12px);
		border-bottom: 1px solid var(--border);
	}

	tbody td {
		padding: rem(7) rem(16);
		border-bottom: 1px solid var(--border);
		white-space: nowrap;
	}

	tbody tr:not(.detail-row):hover td {
		background: var(--hover);
	}

	tbody tr.busy {
		opacity: 0.5;
	}

	.mono {
		font-family: var(--font-mono);
		font-size: rem(12);
		font-variant-numeric: tabular-nums;
	}

	.col-port {
		width: rem(80);
		font-weight: 600;
	}

	.col-pid {
		width: rem(90);
		color: var(--text-secondary);
	}

	.col-proto {
		width: rem(70);
		color: var(--text-secondary);
	}

	.proc {
		max-width: rem(240);
		overflow: hidden;
		text-overflow: ellipsis;
		font-weight: 500;
	}

	.addr {
		color: var(--text-secondary);
	}

	.col-actions {
		width: rem(112);
		text-align: right;
	}

	.row-actions {
		display: flex;
		justify-content: flex-end;
		gap: rem(4);
		opacity: 0;
		transition: opacity 0.12s ease;

		&.pinned {
			opacity: 1;
		}
	}

	tbody tr:hover .row-actions {
		opacity: 1;
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
		transition:
			background-color 0.12s ease,
			color 0.12s ease;

		&:hover {
			background: var(--hover);
		}

		&.on {
			color: var(--accent);
			background: var(--hover);
		}

		&.kill:hover {
			color: var(--danger);
		}

		&.force:hover {
			color: var(--warning);
		}

		&:disabled {
			opacity: 0.4;
		}
	}

	.detail-row td {
		padding: 0;
		background: var(--surface-2);
	}

	.detail {
		display: flex;
		flex-direction: column;
		gap: rem(10);
		padding: rem(12) rem(16);
	}

	.field {
		display: flex;
		flex-direction: column;
		gap: rem(3);
		min-width: 0;
	}

	.field .label {
		color: var(--text-tertiary);
		font-size: rem(10.5);
		font-weight: 600;
		text-transform: uppercase;
		letter-spacing: 0.04em;
	}

	.field .value {
		color: var(--text);
		font-size: rem(12.5);
		white-space: normal;
		word-break: break-all;
		user-select: text;
	}

	code.value {
		font-family: var(--font-mono);
		font-size: rem(12);
	}

	.field-row {
		display: flex;
		justify-content: space-between;
		align-items: flex-end;
		gap: rem(16);
	}

	.copy-actions {
		display: flex;
		gap: rem(6);
		flex-shrink: 0;
	}

	.copy-btn {
		display: inline-flex;
		align-items: center;
		gap: rem(5);
		padding: rem(5) rem(10);
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
	}
</style>
