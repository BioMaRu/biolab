import type { IconName } from '$components/Icon.svelte'

export interface NavItem {
	label: string
	href: string
	icon: IconName
}

export const navItems: NavItem[] = [
	{ label: 'Dashboard', href: '/dashboard', icon: 'dashboard' },
	{ label: 'Ports', href: '/ports', icon: 'ports' },
	{ label: 'AI', href: '/ai', icon: 'ai' },
	{ label: 'Settings', href: '/settings', icon: 'settings' },
]

export function titleForPath(pathname: string): string {
	const match = navItems.find((item) => pathname.startsWith(item.href))
	return match?.label ?? 'BioLab'
}
