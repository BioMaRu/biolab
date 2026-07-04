import { invoke } from '@tauri-apps/api/core'
import type { ClaudeLimits, UsageReport } from './types'

export function scanUsage(): Promise<UsageReport> {
	return invoke('scan_usage')
}

export function claudeUsageLimits(): Promise<ClaudeLimits> {
	return invoke('claude_usage_limits')
}
