#!/usr/bin/env bun
// Set the app version across the files that matter, in place.
// Usage: bun scripts/bump-version.mjs <x.y.z>
import { readFileSync, writeFileSync } from 'node:fs'

const version = process.argv[2]
if (!version || !/^\d+\.\d+\.\d+$/.test(version)) {
	console.error('Usage: bun scripts/bump-version.mjs <x.y.z>')
	process.exit(1)
}

const targets = [
	'apps/desktop/src-tauri/tauri.conf.json',
	'apps/desktop/package.json',
	'package.json',
]

for (const path of targets) {
	const src = readFileSync(path, 'utf8')
	const out = src.replace(/("version":\s*")[^"]*(")/, `$1${version}$2`)
	if (out === src) {
		console.warn(`! no version field changed in ${path}`)
	} else {
		writeFileSync(path, out)
		console.log(`✓ ${path} → ${version}`)
	}
}
