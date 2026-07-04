<script lang="ts">
	import Icon from '$components/Icon.svelte'
	import { agentsStore } from '$features/agents/agents.svelte'
	import { contextRead, contextWrite } from '$features/agents/api'
	import { notify } from '$lib/notify'
	import { formatBytes, formatWhen, tildePath } from '$features/agents/format'
	import type { ContextFile } from '$features/agents/types'

	const files = $derived(agentsStore.inventory?.contextFiles ?? [])
	const globals = $derived(files.filter((f) => f.scope === 'global'))
	const projects = $derived(files.filter((f) => f.scope !== 'global'))

	let editing = $state<ContextFile | null>(null)
	let content = $state('')
	let original = $state('')
	let saving = $state(false)
	let statusMsg = $state<string | null>(null)

	const dirty = $derived(content !== original)

	async function open(f: ContextFile) {
		try {
			const text = await contextRead(f.path)
			content = text
			original = text
			editing = f
			statusMsg = null
		} catch (e) {
			await notify(
				'Read failed',
				e instanceof Error ? e.message : String(e),
			)
		}
	}

	async function save() {
		if (!editing) return
		saving = true
		try {
			const backup = await contextWrite(editing.path, content)
			original = content
			statusMsg = backup ? `Saved · backed up previous version` : 'Saved'
			await agentsStore.refresh()
		} catch (e) {
			statusMsg = null
			await notify(
				'Save failed',
				e instanceof Error ? e.message : String(e),
			)
		} finally {
			saving = false
		}
	}

	function close() {
		editing = null
		statusMsg = null
	}
</script>

{#if editing}
	<div class="editor">
		<div class="ed-head">
			<button class="back" onclick={close}>
				<Icon name="close" size={15} /> Back
			</button>
			<div class="path">
				<span class="badge">{editing.tool}</span>
				<span class="mono">{tildePath(editing.path)}</span>
			</div>
			<button class="save" disabled={!dirty || saving} onclick={save}>
				<Icon name="check" size={14} />
				{saving ? 'Saving…' : 'Save'}
			</button>
		</div>
		<textarea
			class="u-scroll"
			bind:value={content}
			spellcheck="false"
			placeholder="This file is empty. Start typing to create it…"></textarea>
		<div class="ed-foot">
			<span>{content.length} chars</span>
			{#if statusMsg}<span class="ok">
					{statusMsg}
				</span>{:else if dirty}<span class="unsaved">
					Unsaved changes
				</span>{/if}
		</div>
	</div>
{:else}
	<div class="ctx">
		<p class="hint">
			Global instruction files your agents read on every run, plus every
			<code>CLAUDE.md</code>
			/
			<code>AGENTS.md</code>
			across your projects. Edits are backed up automatically.
		</p>

		<div class="list u-scroll">
			<div class="group-label">Global</div>
			{#each globals as f (f.path)}
				<button class="row" onclick={() => open(f)}>
					<div class="left">
						<Icon name="file" size={15} />
						<div class="labels">
							<span class="kind">{f.kind}</span>
							<span class="sub mono">{tildePath(f.path)}</span>
						</div>
					</div>
					<div class="right">
						<span class="badge">{f.tool}</span>
						{#if f.exists}
							<span class="meta">
								{formatBytes(f.bytes)} · {formatWhen(
									f.modified,
								)}
							</span>
						{:else}
							<span class="meta absent">not created</span>
						{/if}
						<Icon name="edit" size={13} />
					</div>
				</button>
			{/each}

			{#if projects.length}
				<div class="group-label">Projects</div>
				{#each projects as f (f.path)}
					<button class="row" onclick={() => open(f)}>
						<div class="left">
							<Icon name="file" size={15} />
							<div class="labels">
								<span class="kind">
									{f.kind}
									<span class="scope">· {f.scope}</span>
								</span>
								<span class="sub mono">
									{tildePath(f.path)}
								</span>
							</div>
						</div>
						<div class="right">
							<span class="badge">{f.tool}</span>
							<span class="meta">
								{formatBytes(f.bytes)} · {formatWhen(
									f.modified,
								)}
							</span>
							<Icon name="edit" size={13} />
						</div>
					</button>
				{/each}
			{/if}
		</div>
	</div>
{/if}

<style lang="scss">
	.ctx {
		display: flex;
		flex-direction: column;
		height: 100%;
	}

	.hint {
		flex-shrink: 0;
		padding: rem(12) rem(16);
		color: var(--text-tertiary);
		font-size: rem(12);
		border-bottom: 1px solid var(--border);

		code {
			font-family: var(--font-mono);
			font-size: rem(11.5);
			color: var(--text-secondary);
		}
	}

	.list {
		flex: 1;
		min-height: 0;
		padding: rem(8) rem(12);
	}

	.group-label {
		padding: rem(10) rem(4) rem(6);
		color: var(--text-tertiary);
		font-size: rem(11);
		font-weight: 600;
		text-transform: uppercase;
		letter-spacing: 0.04em;
	}

	.row {
		display: flex;
		justify-content: space-between;
		align-items: center;
		gap: rem(12);
		width: 100%;
		padding: rem(9) rem(12);
		color: var(--text);
		text-align: left;
		background: transparent;
		border: none;
		border-radius: var(--radius-sm);
		transition: background-color 0.12s ease;

		&:hover {
			background: var(--hover);
		}
	}

	.left {
		display: flex;
		align-items: center;
		gap: rem(10);
		min-width: 0;
		color: var(--text-secondary);
	}

	.labels {
		display: flex;
		flex-direction: column;
		gap: rem(2);
		min-width: 0;
	}

	.kind {
		color: var(--text);
		font-size: rem(13);
		font-weight: 500;
	}

	.scope {
		color: var(--text-tertiary);
		font-weight: 400;
	}

	.sub {
		overflow: hidden;
		color: var(--text-tertiary);
		font-size: rem(11);
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	.mono {
		font-family: var(--font-mono);
	}

	.right {
		display: flex;
		align-items: center;
		gap: rem(10);
		flex-shrink: 0;
		color: var(--text-tertiary);
	}

	.badge {
		padding: rem(2) rem(8);
		color: var(--text-secondary);
		font-size: rem(10.5);
		font-weight: 600;
		text-transform: uppercase;
		background: var(--surface-2);
		border: 1px solid var(--border);
		border-radius: 999px;
	}

	.meta {
		font-size: rem(11.5);
		font-variant-numeric: tabular-nums;

		&.absent {
			color: var(--text-tertiary);
			font-style: italic;
		}
	}

	/* Editor */
	.editor {
		display: flex;
		flex-direction: column;
		height: 100%;
	}

	.ed-head {
		display: flex;
		justify-content: space-between;
		align-items: center;
		gap: rem(12);
		flex-shrink: 0;
		padding: rem(10) rem(16);
		border-bottom: 1px solid var(--border);
	}

	.back {
		display: inline-flex;
		align-items: center;
		gap: rem(5);
		color: var(--text-secondary);
		font-size: rem(12.5);
		background: transparent;
		border: none;
		&:hover {
			color: var(--text);
		}
	}

	.path {
		display: flex;
		align-items: center;
		gap: rem(8);
		min-width: 0;
		flex: 1;
		justify-content: center;

		.mono {
			overflow: hidden;
			color: var(--text-secondary);
			font-size: rem(12);
			text-overflow: ellipsis;
			white-space: nowrap;
		}
	}

	.save {
		display: inline-flex;
		align-items: center;
		gap: rem(5);
		padding: rem(6) rem(13);
		color: var(--accent-text);
		font-size: rem(12.5);
		font-weight: 500;
		background: var(--accent);
		border: none;
		border-radius: var(--radius-sm);

		&:hover:not(:disabled) {
			background: var(--accent-hover);
		}
		&:disabled {
			opacity: 0.5;
		}
	}

	textarea {
		flex: 1;
		min-height: 0;
		padding: rem(16);
		color: var(--text);
		font-family: var(--font-mono);
		font-size: rem(12.5);
		line-height: 1.6;
		background: transparent;
		border: none;
		outline: none;
		resize: none;
		user-select: text;
	}

	.ed-foot {
		display: flex;
		justify-content: space-between;
		align-items: center;
		flex-shrink: 0;
		padding: rem(8) rem(16);
		color: var(--text-tertiary);
		font-size: rem(11.5);
		border-top: 1px solid var(--border);

		.ok {
			color: var(--success);
		}
		.unsaved {
			color: var(--warning);
		}
	}
</style>
