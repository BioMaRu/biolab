export type ThemeMode = 'auto' | 'light' | 'dark'

const STORAGE_KEY = 'biolab:theme'

class ThemeStore {
	#mode = $state<ThemeMode>('auto')
	#systemDark = $state(false)
	#initialized = false

	get mode(): ThemeMode {
		return this.#mode
	}

	get resolved(): 'light' | 'dark' {
		if (this.#mode === 'auto') return this.#systemDark ? 'dark' : 'light'
		return this.#mode
	}

	init() {
		if (this.#initialized) return
		this.#initialized = true

		const stored = localStorage.getItem(STORAGE_KEY) as ThemeMode | null
		if (stored === 'auto' || stored === 'light' || stored === 'dark') {
			this.#mode = stored
		}

		const mq = window.matchMedia('(prefers-color-scheme: dark)')
		this.#systemDark = mq.matches
		mq.addEventListener('change', (e) => {
			this.#systemDark = e.matches
			this.#apply()
		})

		this.#apply()
	}

	set(mode: ThemeMode) {
		this.#mode = mode
		localStorage.setItem(STORAGE_KEY, mode)
		this.#apply()
	}

	toggle() {
		this.set(this.resolved === 'dark' ? 'light' : 'dark')
	}

	#apply() {
		document.documentElement.dataset.theme = this.resolved
	}
}

export const themeStore = new ThemeStore()
