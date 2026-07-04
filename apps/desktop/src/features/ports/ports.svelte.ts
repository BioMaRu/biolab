import { listPorts } from './api'
import type { PortInfo } from './types'

class PortsStore {
	#ports = $state<PortInfo[]>([])
	#loading = $state(false)
	#refreshing = $state(false)
	#error = $state<string | null>(null)
	#query = $state('')
	#lastUpdated = $state<number | null>(null)
	#timer: ReturnType<typeof setInterval> | null = null

	get ports(): PortInfo[] {
		return this.#ports
	}
	get loading(): boolean {
		return this.#loading
	}
	get refreshing(): boolean {
		return this.#refreshing
	}
	get error(): string | null {
		return this.#error
	}
	get lastUpdated(): number | null {
		return this.#lastUpdated
	}

	get query(): string {
		return this.#query
	}
	set query(value: string) {
		this.#query = value
	}

	get filtered(): PortInfo[] {
		const q = this.#query.trim().toLowerCase()
		if (!q) return this.#ports
		return this.#ports.filter(
			(p) =>
				String(p.port).includes(q) ||
				String(p.pid).includes(q) ||
				p.processName.toLowerCase().includes(q) ||
				p.command.toLowerCase().includes(q) ||
				p.address.toLowerCase().includes(q),
		)
	}

	async refresh() {
		if (this.#ports.length === 0) this.#loading = true
		this.#refreshing = true
		try {
			this.#ports = await listPorts()
			this.#error = null
			this.#lastUpdated = Date.now()
		} catch (e) {
			this.#error = e instanceof Error ? e.message : String(e)
		} finally {
			this.#loading = false
			this.#refreshing = false
		}
	}

	startAutoRefresh(intervalMs = 3000) {
		this.stopAutoRefresh()
		this.#timer = setInterval(() => {
			void this.refresh()
		}, intervalMs)
	}

	stopAutoRefresh() {
		if (this.#timer !== null) {
			clearInterval(this.#timer)
			this.#timer = null
		}
	}
}

export const portsStore = new PortsStore()
