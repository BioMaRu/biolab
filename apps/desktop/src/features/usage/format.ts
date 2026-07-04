/** Compact token count: 1234 -> 1.2K, 3.4M, 1.0B. */
export function fmtTokens(n: number): string {
	if (n >= 1_000_000_000) return (n / 1_000_000_000).toFixed(1) + 'B'
	if (n >= 1_000_000)
		return (n / 1_000_000).toFixed(n >= 10_000_000 ? 0 : 1) + 'M'
	if (n >= 1_000) return (n / 1_000).toFixed(n >= 10_000 ? 0 : 1) + 'K'
	return String(n)
}

/** Estimated USD spend. */
export function fmtUsd(n: number): string {
	if (n <= 0) return '$0.00'
	if (n < 0.01) return '<$0.01'
	if (n < 1000) return '$' + n.toFixed(2)
	return '$' + Math.round(n).toLocaleString()
}

/** Time remaining until a rolling window frees up. `now` is epoch ms. */
export function fmtCountdown(resetsAt: number | null, now: number): string {
	if (!resetsAt) return 'idle'
	const s = resetsAt - Math.floor(now / 1000)
	if (s <= 0) return 'ready'
	const h = Math.floor(s / 3600)
	const m = Math.floor((s % 3600) / 60)
	return h > 0 ? `${h}h ${m}m` : `${m}m`
}

/** Reset time for a plan limit: "in 1h 24m" when near, else "Sat 11:59 AM". */
export function fmtReset(resetsAt: number | null, now: number): string {
	if (!resetsAt) return '—'
	const s = resetsAt - Math.floor(now / 1000)
	if (s <= 0) return 'resets now'
	if (s < 24 * 3600) {
		const h = Math.floor(s / 3600)
		const m = Math.floor((s % 3600) / 60)
		return `resets in ${h > 0 ? `${h}h ${m}m` : `${m}m`}`
	}
	const d = new Date(resetsAt * 1000)
	return (
		'resets ' +
		d.toLocaleString([], {
			weekday: 'short',
			hour: 'numeric',
			minute: '2-digit',
		})
	)
}

/** Fraction [0,1] of a 5h session window already elapsed. */
export function sessionElapsed(resetsAt: number | null, now: number): number {
	if (!resetsAt) return 0
	const remaining = resetsAt - Math.floor(now / 1000)
	const frac = 1 - remaining / (5 * 3600)
	return Math.min(1, Math.max(0, frac))
}

/** Relative "time ago" from epoch seconds. `now` is epoch ms. */
export function fmtAgo(secs: number | null, now: number): string {
	if (!secs) return 'never'
	const diff = Math.floor(now / 1000) - secs
	if (diff < 60) return 'just now'
	if (diff < 3600) return `${Math.floor(diff / 60)}m ago`
	if (diff < 86400) return `${Math.floor(diff / 3600)}h ago`
	return `${Math.floor(diff / 86400)}d ago`
}

/** Last path segment of a project directory, for a compact label. */
export function projectName(path: string): string {
	const parts = path.split('/').filter(Boolean)
	return parts[parts.length - 1] || path
}

/** Short model label: claude-opus-4-8 -> Opus 4.8. */
export function modelLabel(model: string): string {
	const m = model.toLowerCase()
	const family = m.includes('opus')
		? 'Opus'
		: m.includes('sonnet')
			? 'Sonnet'
			: m.includes('haiku')
				? 'Haiku'
				: model
	const ver = model.match(/(\d+[-.]\d+)/)?.[1]?.replace('-', '.')
	return ver ? `${family} ${ver}` : family
}
