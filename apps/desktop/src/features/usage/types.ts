export interface WindowStat {
	key: 'session' | 'today' | 'week' | 'all'
	label: string
	input: number
	output: number
	cacheRead: number
	cacheCreation: number
	total: number
	cost: number
	messages: number
	/** Epoch seconds when the rolling session window frees up (session only). */
	resetsAt: number | null
}

export interface ModelStat {
	model: string
	total: number
	cost: number
	messages: number
}

export interface ProjectStat {
	path: string
	total: number
	messages: number
}

export interface ProviderUsage {
	id: string
	name: string
	/** Whether we have real local usage data for this provider. */
	tracked: boolean
	note: string | null
	windows: WindowStat[]
	models: ModelStat[]
	projects: ProjectStat[]
	webSearch: number
	webFetch: number
	sessions: number
	/** Epoch seconds of the most recent activity. */
	lastActive: number | null
}

export interface UsageReport {
	generatedAt: number
	providers: ProviderUsage[]
}

/** One row in Claude's official "usage limits" panel. */
export interface LimitBar {
	kind: string
	label: string
	group: string
	percent: number
	severity: 'normal' | 'warning' | 'critical' | string
	/** Epoch seconds when this limit resets. */
	resetsAt: number | null
	isActive: boolean
}

/** Live plan limits from Anthropic's OAuth usage endpoint. */
export interface ClaudeLimits {
	plan: string | null
	bars: LimitBar[]
}
