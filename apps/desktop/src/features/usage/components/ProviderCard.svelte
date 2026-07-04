<script lang="ts">
	import Icon from '$components/Icon.svelte'
	import BrandGlyph from '$components/BrandGlyph.svelte'
	import type {
		ClaudeLimits,
		ProviderUsage,
		WindowStat,
	} from '$features/usage/types'
	import {
		fmtAgo,
		fmtCountdown,
		fmtReset,
		fmtTokens,
		fmtUsd,
		modelLabel,
		projectName,
		sessionElapsed,
	} from '$features/usage/format'

	interface Props {
		provider: ProviderUsage
		now: number
		/** Live plan limits (Claude only). */
		limits?: ClaudeLimits | null
		limitsError?: string | null
		limitsLoading?: boolean
		onRetryLimits?: () => void
	}
	let {
		provider,
		now,
		limits = null,
		limitsError = null,
		limitsLoading = false,
		onRetryLimits,
	}: Props = $props()

	const win = (k: WindowStat['key']) =>
		provider.windows.find((w) => w.key === k)
	const session = $derived(win('session'))
	const secondary = $derived(
		(['today', 'week', 'all'] as const)
			.map(win)
			.filter((w): w is WindowStat => !!w),
	)

	const modelMax = $derived(
		Math.max(1, ...provider.models.map((m) => m.total)),
	)
	const projectMax = $derived(
		Math.max(1, ...provider.projects.map((p) => p.total)),
	)
	const sessionActive = $derived(!!session && session.total > 0)
	const hasCost = $derived((win('all')?.cost ?? 0) > 0)
</script>

{#if !provider.tracked}
	<div class="card untracked">
		<div class="head">
			<span class="glyph">
				<BrandGlyph
					tool={provider.id}
					label={provider.name}
					size={16}
				/>
			</span>
			<span class="name">{provider.name}</span>
			<span class="badge">Not tracked</span>
		</div>
		<p class="note">{provider.note}</p>
	</div>
{:else}
	<div class="card">
		<div class="head">
			<span class="glyph">
				<BrandGlyph
					tool={provider.id}
					label={provider.name}
					size={16}
				/>
			</span>
			<span class="name">{provider.name}</span>
			<span class="active">{fmtAgo(provider.lastActive, now)}</span>
			{#if hasCost}
				<span class="spend" title="All-time estimated spend">
					{fmtUsd(win('all')?.cost ?? 0)}
				</span>
			{/if}
		</div>

		{#if provider.note}
			<p class="card-note">{provider.note}</p>
		{/if}

		<!-- Live plan limits (Claude) ---------------------------------- -->
		{#if provider.id === 'claude'}
			<div class="limits">
				<div class="limits-head">
					<span class="limits-title">Plan limits</span>
					{#if limits?.plan}<span class="plan">
							{limits.plan}
						</span>{/if}
					{#if limitsLoading && !limits}
						<span class="limits-loading">loading…</span>
					{/if}
				</div>

				{#if limits}
					{#each limits.bars as b (b.kind + b.label)}
						<div class="limit">
							<div class="limit-top">
								<span class="limit-label">
									{b.label}
									{#if b.isActive}
										<span
											class="active-dot"
											title="Active window"
										></span>
									{/if}
								</span>
								<span class="limit-pct">
									{Math.round(b.percent)}%
								</span>
							</div>
							<div class="limit-track">
								<div
									class="limit-fill sev-{b.severity}"
									style:width="{Math.min(100, b.percent)}%"
								></div>
							</div>
							<span class="limit-reset">
								{fmtReset(b.resetsAt, now)}
							</span>
						</div>
					{/each}
				{:else if limitsError}
					<div class="limits-err">
						<Icon name="alert" size={13} />
						<span>{limitsError}</span>
						{#if onRetryLimits}
							<button onclick={onRetryLimits}>Retry</button>
						{/if}
					</div>
				{/if}
			</div>

			<div class="local-divider">Local activity · estimated</div>
		{/if}

		<!-- Session (5h rolling) --------------------------------------- -->
		{#if session}
			<div class="session" class:idle={!sessionActive}>
				<div class="s-main">
					<span class="s-label">{session.label}</span>
					<div class="s-figures">
						<strong>{fmtTokens(session.total)}</strong>
						<span class="s-unit">tokens</span>
						{#if hasCost}
							<span class="s-dot">·</span>
							<span class="s-cost">{fmtUsd(session.cost)}</span>
						{/if}
						<span class="s-dot">·</span>
						<span class="s-msgs">{session.messages} msgs</span>
					</div>
				</div>
				<div class="s-reset">
					<span class="s-reset-label">
						<Icon name="clock" size={12} />
						{sessionActive
							? `resets in ${fmtCountdown(session.resetsAt, now)}`
							: 'no active window'}
					</span>
					<div class="track">
						<div
							class="fill"
							style:width="{sessionActive
								? sessionElapsed(session.resetsAt, now) * 100
								: 0}%"
						></div>
					</div>
				</div>
			</div>
		{/if}

		<!-- Today / Week / All ----------------------------------------- -->
		<div class="windows">
			{#each secondary as w (w.key)}
				<div class="win">
					<span class="w-label">{w.label}</span>
					<strong>{fmtTokens(w.total)}</strong>
					{#if hasCost}
						<span class="w-cost">{fmtUsd(w.cost)}</span>
					{:else}
						<span class="w-cost">{w.messages} turns</span>
					{/if}
				</div>
			{/each}
		</div>

		<!-- By model --------------------------------------------------- -->
		{#if provider.models.length}
			<div class="section">
				<span class="sec-title">By model</span>
				{#each provider.models.slice(0, 5) as m (m.model)}
					<div class="row">
						<span class="row-name">{modelLabel(m.model)}</span>
						<div class="row-bar">
							<div
								class="row-fill"
								style:width="{(m.total / modelMax) * 100}%"
							></div>
						</div>
						<span class="row-val">{fmtTokens(m.total)}</span>
						{#if hasCost}
							<span class="row-cost">{fmtUsd(m.cost)}</span>
						{/if}
					</div>
				{/each}
			</div>
		{/if}

		<!-- Top projects ----------------------------------------------- -->
		{#if provider.projects.length}
			<div class="section">
				<span class="sec-title">Top projects</span>
				{#each provider.projects.slice(0, 4) as p (p.path)}
					<div class="row">
						<span class="row-name mono" title={p.path}>
							{projectName(p.path)}
						</span>
						<div class="row-bar">
							<div
								class="row-fill alt"
								style:width="{(p.total / projectMax) * 100}%"
							></div>
						</div>
						<span class="row-val">{fmtTokens(p.total)}</span>
					</div>
				{/each}
			</div>
		{/if}

		<!-- Footer meta ------------------------------------------------ -->
		<div class="foot">
			<span title="Distinct sessions">
				<Icon name="activity" size={12} />
				{provider.sessions} sessions
			</span>
			{#if provider.webSearch > 0}
				<span title="Web search tool calls">
					<Icon name="search" size={12} />
					{provider.webSearch}
				</span>
			{/if}
			{#if provider.webFetch > 0}
				<span title="Web fetch tool calls">
					<Icon name="external" size={12} />
					{provider.webFetch}
				</span>
			{/if}
		</div>
	</div>
{/if}

<style lang="scss">
	.card {
		display: flex;
		flex-direction: column;
		gap: rem(14);
		padding: rem(16);
		background: var(--surface);
		border: 1px solid var(--border);
		border-radius: var(--radius-lg);

		&.untracked {
			gap: rem(10);
			background: var(--surface-2);
			opacity: 0.75;
		}
	}

	.head {
		display: flex;
		align-items: center;
		gap: rem(10);
	}

	.glyph {
		display: flex;
		justify-content: center;
		align-items: center;
		width: rem(28);
		height: rem(28);
		flex-shrink: 0;
		color: var(--text);
		background: var(--surface-2);
		border: 1px solid var(--border);
		border-radius: var(--radius-sm);
	}
	.untracked .glyph {
		color: var(--text-tertiary);
	}

	.name {
		font-size: rem(14);
		font-weight: 600;
	}

	.active {
		color: var(--text-tertiary);
		font-size: rem(11.5);
	}

	.spend {
		margin-left: auto;
		padding: rem(3) rem(9);
		color: var(--accent-fg);
		font-size: rem(12);
		font-weight: 600;
		font-variant-numeric: tabular-nums;
		background: color-mix(in srgb, var(--accent) 12%, transparent);
		border-radius: 999px;
	}

	.badge {
		margin-left: auto;
		padding: rem(2) rem(9);
		color: var(--text-tertiary);
		font-size: rem(10.5);
		font-weight: 600;
		text-transform: uppercase;
		letter-spacing: 0.03em;
		background: var(--surface);
		border: 1px solid var(--border);
		border-radius: 999px;
	}

	.note {
		color: var(--text-tertiary);
		font-size: rem(12);
		line-height: 1.5;
		padding-left: rem(38);
	}

	.card-note {
		margin-top: rem(-6);
		color: var(--text-tertiary);
		font-size: rem(11.5);
		line-height: 1.45;
	}

	/* Live plan limits -------------------------------------------------- */
	.limits {
		display: flex;
		flex-direction: column;
		gap: rem(12);
		padding: rem(14);
		background: var(--surface-2);
		border: 1px solid var(--border);
		border-radius: var(--radius);
	}

	.limits-head {
		display: flex;
		align-items: center;
		gap: rem(8);
	}

	.limits-title {
		color: var(--text-secondary);
		font-size: rem(11);
		font-weight: 600;
		text-transform: uppercase;
		letter-spacing: 0.04em;
	}

	.plan {
		padding: rem(2) rem(8);
		color: var(--accent-fg);
		font-size: rem(10.5);
		font-weight: 600;
		background: color-mix(in srgb, var(--accent) 14%, transparent);
		border-radius: 999px;
	}

	.limits-loading {
		margin-left: auto;
		color: var(--text-tertiary);
		font-size: rem(11);
	}

	.limit {
		display: flex;
		flex-direction: column;
		gap: rem(5);
	}

	.limit-top {
		display: flex;
		justify-content: space-between;
		align-items: baseline;
	}

	.limit-label {
		display: inline-flex;
		align-items: center;
		gap: rem(6);
		color: var(--text);
		font-size: rem(12.5);
		font-weight: 500;
	}

	.active-dot {
		width: rem(6);
		height: rem(6);
		border-radius: 50%;
		background: var(--success);
		box-shadow: 0 0 0 3px
			color-mix(in srgb, var(--success) 22%, transparent);
	}

	.limit-pct {
		color: var(--text-secondary);
		font-size: rem(12.5);
		font-weight: 600;
		font-variant-numeric: tabular-nums;
	}

	.limit-track {
		height: rem(8);
		background: color-mix(in srgb, var(--text-tertiary) 20%, transparent);
		border-radius: 999px;
		overflow: hidden;
	}

	.limit-fill {
		height: 100%;
		border-radius: 999px;
		background: var(--accent);
		transition: width 0.4s ease;

		&.sev-warning {
			background: var(--warning);
		}
		&.sev-critical {
			background: var(--danger);
		}
	}

	.limit-reset {
		color: var(--text-tertiary);
		font-size: rem(11);
		font-variant-numeric: tabular-nums;
	}

	.limits-err {
		display: flex;
		align-items: center;
		gap: rem(8);
		color: var(--danger);
		font-size: rem(12);

		button {
			margin-left: auto;
			padding: rem(3) rem(10);
			color: var(--danger);
			font-family: inherit;
			font-size: rem(11.5);
			font-weight: 600;
			background: transparent;
			border: 1px solid color-mix(in srgb, var(--danger) 40%, transparent);
			border-radius: var(--radius-sm);
			&:hover {
				background: color-mix(in srgb, var(--danger) 12%, transparent);
			}
		}
	}

	.local-divider {
		margin-top: rem(2);
		color: var(--text-tertiary);
		font-size: rem(10.5);
		font-weight: 600;
		text-transform: uppercase;
		letter-spacing: 0.04em;
	}

	/* Session ------------------------------------------------------- */
	.session {
		display: flex;
		align-items: center;
		gap: rem(14);
		padding: rem(13) rem(14);
		background: color-mix(in srgb, var(--accent) 8%, var(--surface-2));
		border: 1px solid color-mix(in srgb, var(--accent) 22%, transparent);
		border-radius: var(--radius);

		&.idle {
			background: var(--surface-2);
			border-color: var(--border);
		}
	}

	.s-main {
		display: flex;
		flex-direction: column;
		gap: rem(3);
		min-width: 0;
		flex: 1;
	}

	.s-label {
		color: var(--text-secondary);
		font-size: rem(11);
		font-weight: 600;
		text-transform: uppercase;
		letter-spacing: 0.04em;
	}

	.s-figures {
		display: flex;
		align-items: baseline;
		gap: rem(6);
		flex-wrap: wrap;

		strong {
			font-size: rem(24);
			font-weight: 650;
			font-variant-numeric: tabular-nums;
		}
		.s-unit {
			color: var(--text-tertiary);
			font-size: rem(12);
		}
		.s-dot {
			color: var(--text-tertiary);
		}
		.s-cost {
			color: var(--accent-fg);
			font-size: rem(13);
			font-weight: 600;
		}
		.s-msgs {
			color: var(--text-tertiary);
			font-size: rem(12);
		}
	}

	.s-reset {
		display: flex;
		flex-direction: column;
		gap: rem(6);
		width: rem(130);
		flex-shrink: 0;
	}

	.s-reset-label {
		display: inline-flex;
		align-items: center;
		gap: rem(4);
		color: var(--text-tertiary);
		font-size: rem(11.5);
		white-space: nowrap;
	}

	.track {
		height: rem(6);
		background: var(--surface-2);
		border: 1px solid var(--border);
		border-radius: 999px;
		overflow: hidden;
	}
	.fill {
		height: 100%;
		background: var(--accent);
		border-radius: 999px;
		transition: width 0.4s ease;
	}

	/* Windows ------------------------------------------------------- */
	.windows {
		display: grid;
		grid-template-columns: repeat(3, 1fr);
		gap: rem(8);
	}

	.win {
		display: flex;
		flex-direction: column;
		gap: rem(2);
		padding: rem(10) rem(12);
		background: var(--surface-2);
		border: 1px solid var(--border);
		border-radius: var(--radius-sm);

		.w-label {
			color: var(--text-tertiary);
			font-size: rem(11);
		}
		strong {
			font-size: rem(16);
			font-weight: 650;
			font-variant-numeric: tabular-nums;
		}
		.w-cost {
			color: var(--text-tertiary);
			font-size: rem(11.5);
			font-variant-numeric: tabular-nums;
		}
	}

	/* Sections (model / projects) ----------------------------------- */
	.section {
		display: flex;
		flex-direction: column;
		gap: rem(7);
	}

	.sec-title {
		color: var(--text-tertiary);
		font-size: rem(10.5);
		font-weight: 600;
		text-transform: uppercase;
		letter-spacing: 0.04em;
	}

	.row {
		display: flex;
		align-items: center;
		gap: rem(10);
		font-size: rem(12.5);
	}

	.row-name {
		width: rem(96);
		flex-shrink: 0;
		overflow: hidden;
		color: var(--text-secondary);
		text-overflow: ellipsis;
		white-space: nowrap;

		&.mono {
			font-family: var(--font-mono);
			font-size: rem(11.5);
		}
	}

	.row-bar {
		flex: 1;
		height: rem(6);
		background: var(--surface-2);
		border-radius: 999px;
		overflow: hidden;
	}
	.row-fill {
		height: 100%;
		background: var(--accent);
		border-radius: 999px;

		&.alt {
			background: color-mix(
				in srgb,
				var(--accent) 55%,
				var(--text-tertiary)
			);
		}
	}

	.row-val {
		width: rem(48);
		flex-shrink: 0;
		color: var(--text);
		font-variant-numeric: tabular-nums;
		text-align: right;
	}
	.row-cost {
		width: rem(58);
		flex-shrink: 0;
		color: var(--text-tertiary);
		font-variant-numeric: tabular-nums;
		text-align: right;
	}

	/* Footer -------------------------------------------------------- */
	.foot {
		display: flex;
		align-items: center;
		gap: rem(14);
		padding-top: rem(12);
		border-top: 1px solid var(--border);
		color: var(--text-tertiary);
		font-size: rem(11.5);

		span {
			display: inline-flex;
			align-items: center;
			gap: rem(5);
			font-variant-numeric: tabular-nums;
		}
	}
</style>
