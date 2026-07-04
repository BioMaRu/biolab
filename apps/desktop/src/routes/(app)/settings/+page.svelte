<script lang="ts">
	import { onMount } from 'svelte'
	import { getVersion } from '@tauri-apps/api/app'
	import {
		themeStore,
		type ThemeMode,
	} from '$features/theme/app-theme.svelte'
	import { configStore } from '$features/settings/config.svelte'
	import { checkForUpdates } from '$lib/updater'

	let version = $state('')
	let checking = $state(false)

	onMount(async () => {
		version = await getVersion()
	})

	async function runUpdateCheck() {
		checking = true
		try {
			await checkForUpdates(false)
		} finally {
			checking = false
		}
	}

	const themeOptions: { value: ThemeMode; label: string }[] = [
		{ value: 'auto', label: 'Auto' },
		{ value: 'light', label: 'Light' },
		{ value: 'dark', label: 'Dark' },
	]

	const intervalOptions = [
		{ value: 2000, label: '2s' },
		{ value: 3000, label: '3s' },
		{ value: 5000, label: '5s' },
		{ value: 10000, label: '10s' },
	]

	let newPort = $state('')

	function addFavorite() {
		const n = parseInt(newPort.trim(), 10)
		if (!Number.isNaN(n)) {
			configStore.addFavorite(n)
			newPort = ''
		}
	}
</script>

<div class="settings u-scroll">
	<div class="inner">
		<section class="card">
			<h2>Appearance</h2>
			<div class="setting">
				<div class="label">
					<span class="name">Theme</span>
					<span class="hint">
						Follow the system, or force light / dark.
					</span>
				</div>
				<div class="segmented">
					{#each themeOptions as opt (opt.value)}
						<button
							class:active={themeStore.mode === opt.value}
							onclick={() => themeStore.set(opt.value)}
						>
							{opt.label}
						</button>
					{/each}
				</div>
			</div>
		</section>

		<section class="card">
			<h2>Port Manager</h2>
			<div class="setting">
				<div class="label">
					<span class="name">Auto-refresh</span>
					<span class="hint">
						Periodically refresh the port list.
					</span>
				</div>
				<button
					class="switch"
					class:on={configStore.autoRefresh}
					role="switch"
					aria-checked={configStore.autoRefresh}
					aria-label="Toggle auto-refresh"
					onclick={() =>
						configStore.setAutoRefresh(!configStore.autoRefresh)}
				>
					<span class="knob"></span>
				</button>
			</div>
			<div class="setting" class:dim={!configStore.autoRefresh}>
				<div class="label">
					<span class="name">Refresh interval</span>
					<span class="hint">How often to poll for changes.</span>
				</div>
				<div class="segmented">
					{#each intervalOptions as opt (opt.value)}
						<button
							class:active={configStore.refreshIntervalMs ===
								opt.value}
							disabled={!configStore.autoRefresh}
							onclick={() =>
								configStore.setRefreshInterval(opt.value)}
						>
							{opt.label}
						</button>
					{/each}
				</div>
			</div>
		</section>

		<section class="card">
			<h2>Favorite ports</h2>
			<p class="section-hint">
				Added here, they show up as quick-kill chips on the Ports page.
			</p>
			<div class="add">
				<input
					type="text"
					inputmode="numeric"
					placeholder="e.g. 3000"
					bind:value={newPort}
					onkeydown={(e) => e.key === 'Enter' && addFavorite()}
				/>
				<button class="btn" onclick={addFavorite}>Add</button>
			</div>
			{#if configStore.favoritePorts.length === 0}
				<p class="empty">No favorites yet.</p>
			{:else}
				<div class="fav-list">
					{#each configStore.favoritePorts as port (port)}
						<span class="fav-chip">
							{port}
							<button
								aria-label={`Remove ${port}`}
								onclick={() => configStore.removeFavorite(port)}
							>
								×
							</button>
						</span>
					{/each}
				</div>
			{/if}
		</section>

		<section class="card">
			<h2>About &amp; Updates</h2>
			<div class="setting">
				<div class="label">
					<span class="name">Version</span>
					<span class="hint">BioLab {version || '…'}</span>
				</div>
				<button
					class="btn"
					disabled={checking}
					onclick={runUpdateCheck}
				>
					{checking ? 'Checking…' : 'Check for Updates'}
				</button>
			</div>
		</section>
	</div>
</div>

<style lang="scss">
	.settings {
		height: 100%;
	}

	.inner {
		display: flex;
		flex-direction: column;
		gap: rem(16);
		max-width: rem(640);
		padding: rem(24);
	}

	.card {
		padding: rem(18) rem(20);
		background: var(--surface);
		border: 1px solid var(--border);
		border-radius: var(--radius-lg);
	}

	h2 {
		margin-bottom: rem(14);
		font-size: rem(13);
		font-weight: 600;
	}

	.setting {
		display: flex;
		justify-content: space-between;
		align-items: center;
		gap: rem(16);
		padding: rem(10) 0;

		& + .setting {
			border-top: 1px solid var(--border);
		}

		&.dim {
			opacity: 0.5;
		}
	}

	.label {
		display: flex;
		flex-direction: column;
		gap: rem(2);
	}

	.name {
		font-size: rem(13.5);
		font-weight: 500;
	}

	.hint {
		color: var(--text-secondary);
		font-size: rem(12);
	}

	.segmented {
		display: flex;
		flex-shrink: 0;
		padding: rem(2);
		background: var(--surface-2);
		border: 1px solid var(--border);
		border-radius: var(--radius);

		button {
			padding: rem(4) rem(12);
			color: var(--text-secondary);
			font-size: rem(12.5);
			font-weight: 500;
			background: transparent;
			border: none;
			border-radius: rem(6);
			transition: all 0.12s ease;

			&.active {
				color: var(--text);
				background: var(--surface);
				box-shadow: var(--shadow);
			}

			&:disabled {
				opacity: 0.5;
			}
		}
	}

	.switch {
		position: relative;
		flex-shrink: 0;
		width: rem(40);
		height: rem(24);
		background: var(--border-strong);
		border: none;
		border-radius: 999px;
		transition: background-color 0.15s ease;

		&.on {
			background: var(--accent);
		}

		.knob {
			position: absolute;
			top: rem(2);
			left: rem(2);
			width: rem(20);
			height: rem(20);
			background: #fff;
			border-radius: 50%;
			box-shadow: 0 1px 2px rgba(0, 0, 0, 0.3);
			transition: transform 0.15s ease;
		}

		&.on .knob {
			transform: translateX(rem(16));
		}
	}

	.section-hint {
		margin-bottom: rem(12);
		color: var(--text-secondary);
		font-size: rem(12);
	}

	.add {
		display: flex;
		gap: rem(8);
		margin-bottom: rem(12);

		input {
			width: rem(140);
			padding: rem(6) rem(10);
			color: var(--text);
			font-family: inherit;
			font-size: rem(13);
			background: var(--surface-2);
			border: 1px solid var(--border);
			border-radius: var(--radius);
			outline: none;
			user-select: text;

			&:focus {
				border-color: var(--accent);
			}
		}
	}

	.btn {
		padding: rem(6) rem(14);
		color: var(--accent-text);
		font-size: rem(13);
		font-weight: 500;
		background: var(--accent);
		border: none;
		border-radius: var(--radius);

		&:hover {
			background: var(--accent-hover);
		}
	}

	.empty {
		color: var(--text-tertiary);
		font-size: rem(12.5);
	}

	.fav-list {
		display: flex;
		flex-wrap: wrap;
		gap: rem(6);
	}

	.fav-chip {
		display: inline-flex;
		align-items: center;
		gap: rem(6);
		padding: rem(4) rem(6) rem(4) rem(10);
		color: var(--text);
		font-family: var(--font-mono);
		font-size: rem(12);
		background: var(--surface-2);
		border: 1px solid var(--border);
		border-radius: 999px;

		button {
			display: flex;
			justify-content: center;
			align-items: center;
			width: rem(16);
			height: rem(16);
			color: var(--text-tertiary);
			font-size: rem(14);
			line-height: 1;
			background: transparent;
			border: none;
			border-radius: 50%;

			&:hover {
				color: var(--danger);
				background: var(--hover);
			}
		}
	}
</style>
