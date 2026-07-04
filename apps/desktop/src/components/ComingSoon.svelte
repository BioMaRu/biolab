<script lang="ts">
	import Icon, { type IconName } from '$components/Icon.svelte'

	interface Props {
		icon?: IconName
		title: string
		description?: string
	}

	let { icon = 'info', title, description = 'Coming soon.' }: Props = $props()
</script>

<div class="coming-soon">
	<div class="badge"><Icon name={icon} size={26} /></div>
	<h2>{title}</h2>
	<p>{description}</p>
</div>

<style lang="scss">
	.coming-soon {
		display: flex;
		flex-direction: column;
		justify-content: center;
		align-items: center;
		gap: rem(10);
		width: 100%;
		height: 100%;
		text-align: center;
	}

	.badge {
		display: flex;
		justify-content: center;
		align-items: center;
		width: rem(56);
		height: rem(56);
		margin-bottom: rem(4);
		color: var(--text-secondary);
		background: var(--surface);
		border: 1px solid var(--border);
		border-radius: var(--radius-lg);
	}

	h2 {
		font-size: rem(17);
		font-weight: 600;
	}

	p {
		max-width: rem(320);
		color: var(--text-secondary);
		font-size: rem(13.5);
	}
</style>
