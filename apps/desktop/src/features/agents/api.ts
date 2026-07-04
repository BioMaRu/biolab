import { invoke } from '@tauri-apps/api/core'
import type { AgentInventory, McpServer } from './types'

export function scanAgents(): Promise<AgentInventory> {
	return invoke('scan_agents')
}

// --- MCP servers ---

export function mcpUpsert(server: McpServer): Promise<void> {
	return invoke('mcp_upsert', { server })
}

export function mcpRemove(tool: string, name: string): Promise<void> {
	return invoke('mcp_remove', { tool, name })
}

export function mcpSync(server: McpServer, targets: string[]): Promise<void> {
	return invoke('mcp_sync', { server, targets })
}

export function mcpSetEnabled(
	server: McpServer,
	enabled: boolean,
): Promise<void> {
	return invoke('mcp_set_enabled', { server, enabled })
}

// --- Skills ---

export function skillRead(path: string): Promise<string> {
	return invoke('skill_read', { path })
}

export function skillShare(name: string, sourcePath: string): Promise<string> {
	return invoke('skill_share', { name, sourcePath })
}

export function skillLink(tool: string, name: string): Promise<void> {
	return invoke('skill_link', { tool, name })
}

// --- Symlinks ---

export function symlinkRemove(path: string): Promise<void> {
	return invoke('symlink_remove', { path })
}

export function symlinkCreate(target: string, linkPath: string): Promise<void> {
	return invoke('symlink_create', { target, linkPath })
}

export function symlinkRepair(path: string, target: string): Promise<void> {
	return invoke('symlink_repair', { path, target })
}

// --- Context files ---

export function contextRead(path: string): Promise<string> {
	return invoke('context_read', { path })
}

/** Returns the backup path (if a prior version existed). */
export function contextWrite(
	path: string,
	content: string,
): Promise<string | null> {
	return invoke('context_write', { path, content })
}
