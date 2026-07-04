import { invoke } from '@tauri-apps/api/core'
import type { PortInfo, ProcessDetail } from './types'

export function listPorts(): Promise<PortInfo[]> {
	return invoke('list_ports')
}

export function killProcess(pid: number, force = false): Promise<void> {
	return invoke('kill_process', { pid, force })
}

export function processDetails(pid: number): Promise<ProcessDetail> {
	return invoke('process_details', { pid })
}
