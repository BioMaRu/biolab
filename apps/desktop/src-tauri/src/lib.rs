mod commands;
mod tray;

use commands::agents::{
    context_read, context_write, mcp_remove, mcp_set_enabled, mcp_sync, mcp_upsert, scan_agents,
    skill_link, skill_read, skill_share, symlink_create, symlink_remove, symlink_repair,
};
use commands::ports::{kill_process, list_ports, process_details};

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_notification::init())
        .plugin(tauri_plugin_autostart::init(
            tauri_plugin_autostart::MacosLauncher::LaunchAgent,
            None,
        ))
        .plugin(tauri_plugin_updater::Builder::new().build())
        .plugin(tauri_plugin_process::init())
        .setup(|app| {
            #[cfg(target_os = "macos")]
            {
                use tauri::Manager;
                use window_vibrancy::{apply_vibrancy, NSVisualEffectMaterial, NSVisualEffectState};

                let window = app.get_webview_window("main").unwrap();
                apply_vibrancy(
                    &window,
                    NSVisualEffectMaterial::Sidebar,
                    Some(NSVisualEffectState::Active),
                    None,
                )
                .expect("failed to apply macOS window vibrancy");
            }

            tray::setup(app.handle())?;
            Ok(())
        })
        .on_window_event(|window, event| {
            // Closing the window hides it to the menu bar instead of quitting.
            // The app keeps running in the tray; Quit (⌘Q) exits for real.
            if let tauri::WindowEvent::CloseRequested { api, .. } = event {
                api.prevent_close();
                let _ = window.hide();
                // Freshen the menu-bar menu now that tray-only usage begins.
                use tauri::Manager;
                tray::refresh(window.app_handle());
            }
        })
        .invoke_handler(tauri::generate_handler![
            list_ports,
            kill_process,
            process_details,
            scan_agents,
            mcp_upsert,
            mcp_remove,
            mcp_sync,
            mcp_set_enabled,
            skill_read,
            skill_share,
            skill_link,
            symlink_create,
            symlink_remove,
            symlink_repair,
            context_read,
            context_write
        ])
        .build(tauri::generate_context!())
        .expect("error while building tauri application")
        .run(|app, event| {
            // Re-show the window when the app is reopened (e.g. Dock icon click).
            if let tauri::RunEvent::Reopen { .. } = event {
                use tauri::Manager;
                if let Some(win) = app.get_webview_window("main") {
                    let _ = win.show();
                    let _ = win.set_focus();
                }
            }
        });
}
