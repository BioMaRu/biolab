export interface PortInfo {
	pid: number
	processName: string
	user: string
	protocol: string
	address: string
	port: number
	/** Full command line (from `ps`), falls back to the process name. */
	command: string
}

export interface ProcessDetail {
	pid: number
	user: string
	command: string
}
