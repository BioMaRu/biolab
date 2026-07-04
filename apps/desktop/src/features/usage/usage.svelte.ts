import * as api from './api'
import type { ClaudeLimits, ProviderUsage, UsageReport } from './types'

class UsageStore {
	#report = $state<UsageReport | null>(null)
	#loading = $state(false)
	#error = $state<string | null>(null)
	#lastUpdated = $state<number | null>(null)

	#limits = $state<ClaudeLimits | null>(null)
	#limitsError = $state<string | null>(null)
	#limitsLoading = $state(false)

	get report(): UsageReport | null {
		return this.#report
	}
	get providers(): ProviderUsage[] {
		return this.#report?.providers ?? []
	}
	get loading(): boolean {
		return this.#loading
	}
	get error(): string | null {
		return this.#error
	}
	get lastUpdated(): number | null {
		return this.#lastUpdated
	}

	/** Live Claude plan limits (from Anthropic's usage API). */
	get limits(): ClaudeLimits | null {
		return this.#limits
	}
	get limitsError(): string | null {
		return this.#limitsError
	}
	get limitsLoading(): boolean {
		return this.#limitsLoading
	}

	/** Combined 7-day estimated spend across tracked providers. */
	get weekCost(): number {
		return this.providers.reduce((sum, p) => {
			const w = p.windows.find((x) => x.key === 'week')
			return sum + (w?.cost ?? 0)
		}, 0)
	}

	async refresh() {
		this.#loading = this.#report === null
		try {
			this.#report = await api.scanUsage()
			this.#error = null
			this.#lastUpdated = Date.now()
		} catch (e) {
			this.#error = e instanceof Error ? e.message : String(e)
		} finally {
			this.#loading = false
		}
		// Live Claude limits run alongside — a slow/failed fetch never blocks
		// the local analytics.
		void this.refreshLimits()
	}

	async refreshLimits() {
		this.#limitsLoading = true
		try {
			this.#limits = await api.claudeUsageLimits()
			this.#limitsError = null
		} catch (e) {
			this.#limitsError = e instanceof Error ? e.message : String(e)
		} finally {
			this.#limitsLoading = false
		}
	}
}

export const usageStore = new UsageStore()
