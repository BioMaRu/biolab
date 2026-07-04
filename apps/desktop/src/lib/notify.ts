import {
	isPermissionGranted,
	requestPermission,
	sendNotification,
} from '@tauri-apps/plugin-notification'

let granted: boolean | null = null

/** Send a native macOS notification, requesting permission on first use. */
export async function notify(title: string, body: string) {
	if (granted === null) {
		granted = await isPermissionGranted()
		if (!granted) {
			granted = (await requestPermission()) === 'granted'
		}
	}
	if (granted) {
		sendNotification({ title, body })
	}
}
