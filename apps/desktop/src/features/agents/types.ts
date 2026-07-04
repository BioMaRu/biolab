export type ToolId = 'claude' | 'codex' | 'opencode'

/** The five sections of the Agents control center. */
export type SectionId = 'overview' | 'mcp' | 'skills' | 'symlinks' | 'context'

export interface AgentTool {
	id: string
	name: string
	installed: boolean
	configPath: string
}

export interface McpServer {
	name: string
	tool: string
	transport: 'stdio' | 'http'
	command: string | null
	args: string[]
	env: Record<string, string>
	url: string | null
	enabled: boolean
	source: string
}

export interface Skill {
	name: string
	tool: string
	path: string
	isSymlink: boolean
	target: string | null
	broken: boolean
	description: string | null
}

export interface SymlinkEntry {
	path: string
	target: string
	resolved: string
	broken: boolean
	category: string
	tool: string
}

export interface ContextFile {
	scope: string
	tool: string
	kind: string
	path: string
	exists: boolean
	bytes: number
	modified: number | null
}

export interface AgentInventory {
	tools: AgentTool[]
	mcpServers: McpServer[]
	disabled: McpServer[]
	skills: Skill[]
	symlinks: SymlinkEntry[]
	contextFiles: ContextFile[]
	centralSkillsDir: string
}

/** Display metadata for the three known agent CLIs. */
export const TOOLS: { id: ToolId; name: string; short: string }[] = [
	{ id: 'claude', name: 'Claude Code', short: 'Claude' },
	{ id: 'codex', name: 'Codex', short: 'Codex' },
	{ id: 'opencode', name: 'OpenCode', short: 'OpenCode' },
]
