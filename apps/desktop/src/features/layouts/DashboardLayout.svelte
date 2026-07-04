<script lang="ts">
	import { page } from '$app/stores'
	import Icon from '$components/Icon.svelte'
	import { themeStore } from '$features/theme/app-theme.svelte'
	import { navItems, titleForPath } from './config'

	let { children } = $props()

	let pathname = $derived($page.url.pathname)
	let title = $derived(titleForPath(pathname))

	function isActive(href: string): boolean {
		return pathname === href || pathname.startsWith(href + '/')
	}
</script>

<div class="shell">
	<aside class="sidebar">
		<div class="titlebar-drag" data-tauri-drag-region></div>
		<div class="brand">
			<img class="brand-logo" src="/biolab.svg" alt="" />
			<span class="brand-name">BioLab</span>
		</div>
		<nav>
			{#each navItems as item (item.href)}
				<a class="nav-item" class:active={isActive(item.href)} href={item.href}>
					<Icon name={item.icon} />
					<span>{item.label}</span>
				</a>
			{/each}
		</nav>
	</aside>

	<div class="main">
		<header class="topbar" data-tauri-drag-region>
			<h1 class="title">{title}</h1>
			<div class="actions">
				<button
					class="icon-btn"
					title="Toggle theme"
					aria-label="Toggle theme"
					onclick={() => themeStore.toggle()}
				>
					<Icon name={themeStore.resolved === 'dark' ? 'sun' : 'moon'} />
				</button>
			</div>
		</header>

		<div class="content u-scroll">
			{@render children()}
		</div>
	</div>
</div>

<style lang="scss">
	.shell {
		display: flex;
		width: 100%;
		height: 100vh;
		overflow: hidden;
	}

	.sidebar {
		display: flex;
		flex-direction: column;
		flex-shrink: 0;
		width: var(--sidebar-width);
		padding: 0 rem(10) rem(10);
		// mostly translucent (macOS vibrancy) with a subtle tint to tame the wallpaper
		background: var(--sidebar-bg);
		border-right: 1px solid var(--border);
	}

	.titlebar-drag {
		// clears the floating traffic-light buttons and lets you drag the window
		height: rem(28);
		flex-shrink: 0;
	}

	.brand {
		display: flex;
		align-items: center;
		gap: rem(9);
		padding: rem(6) rem(10) rem(14);
	}

	.brand-logo {
		width: auto;
		height: rem(26);
		border-radius: rem(6);
	}

	.brand-name {
		color: var(--text);
		font-size: rem(15);
		font-weight: 700;
		letter-spacing: -0.01em;
	}

	nav {
		display: flex;
		flex-direction: column;
		gap: rem(2);
	}

	.nav-item {
		display: flex;
		align-items: center;
		gap: rem(10);
		padding: rem(7) rem(10);
		color: var(--text-secondary);
		font-size: rem(13.5);
		font-weight: 500;
		text-decoration: none;
		border-radius: var(--radius-sm);
		transition: background-color 0.12s ease, color 0.12s ease;

		&:hover {
			color: var(--text);
			background: var(--hover);
		}

		&.active {
			color: var(--accent-text);
			background: var(--accent);
		}
	}

	.main {
		display: flex;
		flex-direction: column;
		flex: 1;
		min-width: 0;
		background: var(--content-bg);
	}

	.topbar {
		display: flex;
		justify-content: space-between;
		align-items: center;
		flex-shrink: 0;
		height: var(--topbar-height);
		padding: 0 rem(16);
		border-bottom: 1px solid var(--border);
	}

	.title {
		font-size: rem(15);
		font-weight: 600;
	}

	.actions {
		display: flex;
		align-items: center;
		gap: rem(6);
	}

	.icon-btn {
		display: flex;
		justify-content: center;
		align-items: center;
		width: rem(30);
		height: rem(30);
		color: var(--text-secondary);
		background: transparent;
		border: none;
		border-radius: var(--radius-sm);
		transition: background-color 0.12s ease, color 0.12s ease;

		&:hover {
			color: var(--text);
			background: var(--hover);
		}
	}

	.content {
		flex: 1;
		min-height: 0;
		// Pages manage their own padding so full-height views (like Ports)
		// can stretch edge-to-edge without gaps.
	}
</style>
