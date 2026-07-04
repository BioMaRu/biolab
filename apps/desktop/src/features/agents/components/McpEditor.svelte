<script lang="ts">
	import { untrack } from 'svelte'
	import Icon from '$components/Icon.svelte'
	import { agentsStore } from '$features/agents/agents.svelte'
	import { TOOLS, type McpServer, type ToolId } from '$features/agents/types'

	interface Props {
		/** Prefill values (editing an existing server, or copying one). */
		initial: Partial<McpServer> | null
		/** When set, the server is bound to this single tool (edit / copy-here). */
		fixedTool: ToolId | null
		onClose: () => void
	}

	let { initial, fixedTool, onClose }: Props = $props()

	// The editor is mounted fresh per open, so seed the form once and don't react.
	const seed = untrack(() => initial ?? {})
	const lockedTool = untrack(() => fixedTool)

	let name = $state(seed.name ?? '')
	let transport = $state<'stdio' | 'http'>(seed.transport ?? 'stdio')
	let command = $state(seed.command ?? '')
	let argsText = $state((seed.args ?? []).join('\n'))
	let envText = $state(
		Object.entries(seed.env ?? {})
			.map(([k, v]) => `${k}=${v}`)
			.join('\n'),
	)
	let url = $state(seed.url ?? '')
	let targets = $state<ToolId[]>(lockedTool ? [lockedTool] : ['claude'])
	let saving = $state(false)
	let err = $state<string | null>(null)

	const editing = seed.name != null && lockedTool != null

	function toggleTarget(id: ToolId) {
		targets = targets.includes(id)
			? targets.filter((t) => t !== id)
			: [...targets, id]
	}

	function parseArgs(): string[] {
		return argsText
			.split('\n')
			.map((s) => s.trim())
			.filter(Boolean)
	}

	function parseEnv(): Record<string, string> {
		const env: Record<string, string> = {}
		for (const line of envText.split('\n')) {
			const t = line.trim()
			if (!t) continue
			const i = t.indexOf('=')
			if (i > 0) env[t.slice(0, i).trim()] = t.slice(i + 1).trim()
		}
		return env
	}

	async function save() {
		if (!name.trim()) {
			err = 'Name is required.'
			return
		}
		if (targets.length === 0) {
			err = 'Pick at least one agent.'
			return
		}
		const base: McpServer = {
			name: name.trim(),
			tool: targets[0],
			transport,
			command: transport === 'stdio' ? command.trim() || null : null,
			args: transport === 'stdio' ? parseArgs() : [],
			env: transport === 'stdio' ? parseEnv() : {},
			url: transport === 'http' ? url.trim() || null : null,
			enabled: true,
			source: '',
		}
		saving = true
		err = null
		try {
			if (targets.length > 1) {
				await agentsStore.mcpSync(base, targets)
			} else {
				await agentsStore.mcpUpsert({ ...base, tool: targets[0] })
			}
			onClose()
		} catch (e) {
			err = e instanceof Error ? e.message : String(e)
		} finally {
			saving = false
		}
	}
</script>

<div
	class="overlay"
	role="button"
	tabindex="-1"
	onclick={onClose}
	onkeydown={(e) => e.key === 'Escape' && onClose()}
>
	<!-- svelte-ignore a11y_click_events_have_key_events, a11y_no_static_element_interactions -->
	<div
		class="card"
		role="dialog"
		tabindex="-1"
		onclick={(e) => e.stopPropagation()}
	>
		<header>
			<h3>{editing ? 'Edit MCP server' : 'Add MCP server'}</h3>
			<button class="x" aria-label="Close" onclick={onClose}>
				<Icon name="close" size={16} />
			</button>
		</header>

		<div class="body">
			<label class="field">
				<span>Name</span>
				<input
					bind:value={name}
					readonly={editing}
					placeholder="my-server"
					spellcheck="false"
					autocorrect="off"
				/>
			</label>

			{#if !lockedTool}
				<div class="field">
					<span>Add to</span>
					<div class="chips">
						{#each TOOLS as t (t.id)}
							<button
								type="button"
								class="chip"
								class:on={targets.includes(t.id)}
								onclick={() => toggleTarget(t.id)}
							>
								{#if targets.includes(t.id)}<Icon
										name="check"
										size={12}
									/>{/if}
								{t.short}
							</button>
						{/each}
					</div>
				</div>
			{/if}

			<div class="field">
				<span>Transport</span>
				<div class="chips">
					<button
						type="button"
						class="chip"
						class:on={transport === 'stdio'}
						onclick={() => (transport = 'stdio')}
					>
						stdio (local)
					</button>
					<button
						type="button"
						class="chip"
						class:on={transport === 'http'}
						onclick={() => (transport = 'http')}
					>
						http (remote)
					</button>
				</div>
			</div>

			{#if transport === 'stdio'}
				<label class="field">
					<span>Command</span>
					<input
						bind:value={command}
						placeholder="npx"
						spellcheck="false"
						autocorrect="off"
					/>
				</label>
				<label class="field">
					<span>
						Arguments <em>(one per line)</em>
					</span>
					<textarea
						bind:value={argsText}
						rows="3"
						placeholder={'-y\n@scope/package'}
						spellcheck="false"></textarea>
				</label>
				<label class="field">
					<span>
						Environment <em>(KEY=value per line)</em>
					</span>
					<textarea
						bind:value={envText}
						rows="2"
						placeholder="API_KEY=..."
						spellcheck="false"></textarea>
				</label>
			{:else}
				<label class="field">
					<span>URL</span>
					<input
						bind:value={url}
						placeholder="https://example.com/mcp"
						spellcheck="false"
						autocorrect="off"
					/>
				</label>
			{/if}

			{#if err}<div class="err">{err}</div>{/if}
		</div>

		<footer>
			<button class="btn ghost" onclick={onClose}>Cancel</button>
			<button class="btn primary" disabled={saving} onclick={save}>
				{saving ? 'Saving…' : editing ? 'Save' : 'Add'}
			</button>
		</footer>
	</div>
</div>

<style lang="scss">
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

	.card {
		display: flex;
		flex-direction: column;
		width: 100%;
		max-width: rem(460);
		max-height: 100%;
		background: var(--content-bg);
		backdrop-filter: blur(30px);
		border: 1px solid var(--border-strong);
		border-radius: var(--radius-lg);
		box-shadow: 0 20px 60px rgba(0, 0, 0, 0.4);
	}

	header {
		display: flex;
		justify-content: space-between;
		align-items: center;
		padding: rem(14) rem(16);
		border-bottom: 1px solid var(--border);

		h3 {
			font-size: rem(14);
			font-weight: 600;
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

	.body {
		display: flex;
		flex-direction: column;
		gap: rem(12);
		padding: rem(16);
		overflow-y: auto;
	}

	.field {
		display: flex;
		flex-direction: column;
		gap: rem(5);

		> span {
			color: var(--text-secondary);
			font-size: rem(11.5);
			font-weight: 600;

			em {
				color: var(--text-tertiary);
				font-weight: 400;
				font-style: normal;
			}
		}
	}

	input,
	textarea {
		width: 100%;
		padding: rem(7) rem(10);
		color: var(--text);
		font-family: var(--font-mono);
		font-size: rem(12.5);
		background: var(--surface-2);
		border: 1px solid var(--border);
		border-radius: var(--radius-sm);
		outline: none;
		resize: vertical;
		user-select: text;

		&:focus {
			border-color: var(--accent);
		}
	}

	input[readonly] {
		opacity: 0.6;
	}

	.chips {
		display: flex;
		flex-wrap: wrap;
		gap: rem(6);
	}

	.chip {
		display: inline-flex;
		align-items: center;
		gap: rem(4);
		padding: rem(5) rem(11);
		color: var(--text-secondary);
		font-size: rem(12);
		background: var(--surface-2);
		border: 1px solid var(--border);
		border-radius: 999px;
		transition: all 0.12s ease;

		&.on {
			color: var(--accent-text);
			background: var(--accent);
			border-color: var(--accent);
		}
	}

	.err {
		padding: rem(7) rem(10);
		color: var(--danger);
		font-size: rem(12);
		background: color-mix(in srgb, var(--danger) 12%, transparent);
		border-radius: var(--radius-sm);
	}

	footer {
		display: flex;
		justify-content: flex-end;
		gap: rem(8);
		padding: rem(12) rem(16);
		border-top: 1px solid var(--border);
	}

	.btn {
		padding: rem(7) rem(14);
		font-size: rem(13);
		font-weight: 500;
		border: 1px solid var(--border);
		border-radius: var(--radius-sm);
		transition: all 0.12s ease;

		&.ghost {
			color: var(--text-secondary);
			background: transparent;
			&:hover {
				background: var(--hover);
			}
		}
		&.primary {
			color: var(--accent-text);
			background: var(--accent);
			border-color: var(--accent);
			&:hover {
				background: var(--accent-hover);
			}
			&:disabled {
				opacity: 0.6;
			}
		}
	}
</style>
