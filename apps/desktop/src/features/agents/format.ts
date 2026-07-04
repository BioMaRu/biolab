export function formatBytes(n: number): string {
	if (n < 1024) return `${n} B`
	if (n < 1024 * 1024) return `${(n / 1024).toFixed(1)} KB`
	return `${(n / (1024 * 1024)).toFixed(1)} MB`
}

/** Relative "time ago" from an epoch-seconds timestamp. */
export function formatWhen(secs: number | null): string {
	if (!secs) return '—'
	const diff = Date.now() / 1000 - secs
	if (diff < 60) return 'just now'
	if (diff < 3600) return `${Math.floor(diff / 60)}m ago`
	if (diff < 86400) return `${Math.floor(diff / 3600)}h ago`
	return `${Math.floor(diff / 86400)}d ago`
}

/** Shorten an absolute path with a ~ for $HOME. */
export function tildePath(path: string): string {
	const home = '/Users/'
	if (path.startsWith(home)) {
		const rest = path.slice(home.length)
		const slash = rest.indexOf('/')
		if (slash >= 0) return '~' + rest.slice(slash)
	}
	return path
}
