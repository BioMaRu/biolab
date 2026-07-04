import * as api from './api'
import type { AgentInventory, McpServer, ToolId } from './types'

/** Status of one MCP server within one tool. */
export interface McpCell {
	configured: boolean
	on: boolean
	server: McpServer | null
}

class AgentsStore {
	#inv = $state<AgentInventory | null>(null)
	#loading = $state(false)
	#error = $state<string | null>(null)
	#lastUpdated = $state<number | null>(null)

	get inventory(): AgentInventory | null {
		return this.#inv
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

	get mcpServers(): McpServer[] {
		return this.#inv?.mcpServers ?? []
	}
	get disabled(): McpServer[] {
		return this.#inv?.disabled ?? []
	}

	/** Every MCP server name across all tools (live + disabled), sorted. */
	get mcpNames(): string[] {
		const names = new Set<string>()
		for (const s of this.mcpServers) names.add(s.name)
		for (const s of this.disabled) names.add(s.name)
		return [...names].sort((a, b) => a.localeCompare(b))
	}

	/** Resolve a server's state in a given tool. */
	mcpCell(name: string, tool: ToolId): McpCell {
		const live = this.mcpServers.find(
			(s) => s.name === name && s.tool === tool,
		)
		if (live) return { configured: true, on: live.enabled, server: live }
		const stashed = this.disabled.find(
			(s) => s.name === name && s.tool === tool,
		)
		if (stashed) return { configured: true, on: false, server: stashed }
		return { configured: false, on: false, server: null }
	}

	async refresh() {
		this.#loading = this.#inv === null
		try {
			this.#inv = await api.scanAgents()
			this.#error = null
			this.#lastUpdated = Date.now()
		} catch (e) {
			this.#error = e instanceof Error ? e.message : String(e)
		} finally {
			this.#loading = false
		}
	}

	// All mutations refresh the inventory afterwards so the UI stays truthful.

	async mcpUpsert(server: McpServer) {
		await api.mcpUpsert(server)
		await this.refresh()
	}
	async mcpRemove(tool: string, name: string) {
		await api.mcpRemove(tool, name)
		await this.refresh()
	}
	async mcpSync(server: McpServer, targets: string[]) {
		await api.mcpSync(server, targets)
		await this.refresh()
	}
	async mcpSetEnabled(server: McpServer, enabled: boolean) {
		await api.mcpSetEnabled(server, enabled)
		await this.refresh()
	}

	async skillShare(name: string, sourcePath: string) {
		await api.skillShare(name, sourcePath)
		await this.refresh()
	}
	async skillLink(tool: string, name: string) {
		await api.skillLink(tool, name)
		await this.refresh()
	}

	async symlinkRemove(path: string) {
		await api.symlinkRemove(path)
		await this.refresh()
	}
	async symlinkRepair(path: string, target: string) {
		await api.symlinkRepair(path, target)
		await this.refresh()
	}
}

export const agentsStore = new AgentsStore()
