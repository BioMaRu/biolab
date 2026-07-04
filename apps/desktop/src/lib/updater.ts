import { check } from '@tauri-apps/plugin-updater'
import { relaunch } from '@tauri-apps/plugin-process'
import { ask, message } from '@tauri-apps/plugin-dialog'

/**
 * Check GitHub for a newer BioLab release. When `silent`, only prompts if an
 * update exists (used on launch); otherwise also reports "up to date" / errors.
 */
export async function checkForUpdates(silent = false) {
	try {
		const update = await check()

		if (!update) {
			if (!silent) {
				await message('You’re on the latest version.', {
					title: 'BioLab',
					kind: 'info',
				})
			}
			return
		}

		const notes = update.body ? `\n\n${update.body}` : ''
		const wanted = await ask(
			`BioLab ${update.version} is available (you have ${update.currentVersion}).${notes}\n\nDownload and install now?`,
			{
				title: 'Update Available',
				kind: 'info',
				okLabel: 'Update & Restart',
				cancelLabel: 'Later',
			},
		)
		if (!wanted) return

		await update.downloadAndInstall()
		await relaunch()
	} catch (e) {
		if (!silent) {
			await message(
				`Update check failed: ${e instanceof Error ? e.message : String(e)}`,
				{ title: 'BioLab', kind: 'error' },
			)
		}
	}
}
