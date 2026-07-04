const KEY = 'biolab:config'

interface ConfigData {
	autoRefresh: boolean
	refreshIntervalMs: number
	favoritePorts: number[]
}

const DEFAULTS: ConfigData = {
	autoRefresh: true,
	refreshIntervalMs: 3000,
	favoritePorts: [],
}

class ConfigStore {
	#autoRefresh = $state(DEFAULTS.autoRefresh)
	#refreshIntervalMs = $state(DEFAULTS.refreshIntervalMs)
	#favoritePorts = $state<number[]>([])
	#loaded = false

	get autoRefresh(): boolean {
		return this.#autoRefresh
	}
	get refreshIntervalMs(): number {
		return this.#refreshIntervalMs
	}
	get favoritePorts(): number[] {
		return this.#favoritePorts
	}

	init() {
		if (this.#loaded) return
		this.#loaded = true
		try {
			const raw = localStorage.getItem(KEY)
			if (!raw) return
			const data = JSON.parse(raw) as Partial<ConfigData>
			if (typeof data.autoRefresh === 'boolean') {
				this.#autoRefresh = data.autoRefresh
			}
			if (typeof data.refreshIntervalMs === 'number') {
				this.#refreshIntervalMs = data.refreshIntervalMs
			}
			if (Array.isArray(data.favoritePorts)) {
				this.#favoritePorts = data.favoritePorts.filter(
					(n) => typeof n === 'number',
				)
			}
		} catch {
			/* ignore malformed config */
		}
	}

	#persist() {
		const data: ConfigData = {
			autoRefresh: this.#autoRefresh,
			refreshIntervalMs: this.#refreshIntervalMs,
			favoritePorts: this.#favoritePorts,
		}
		localStorage.setItem(KEY, JSON.stringify(data))
	}

	setAutoRefresh(value: boolean) {
		this.#autoRefresh = value
		this.#persist()
	}

	setRefreshInterval(ms: number) {
		this.#refreshIntervalMs = ms
		this.#persist()
	}

	addFavorite(port: number) {
		if (port < 1 || port > 65535) return
		if (!this.#favoritePorts.includes(port)) {
			this.#favoritePorts = [...this.#favoritePorts, port].sort(
				(a, b) => a - b,
			)
			this.#persist()
		}
	}

	removeFavorite(port: number) {
		this.#favoritePorts = this.#favoritePorts.filter((p) => p !== port)
		this.#persist()
	}
}

export const configStore = new ConfigStore()
