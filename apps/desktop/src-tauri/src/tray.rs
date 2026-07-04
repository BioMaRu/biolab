use std::io::Write;
use std::process::{Command, Stdio};

use tauri::{
    menu::{
        CheckMenuItemBuilder, Menu, MenuBuilder, MenuItemBuilder, PredefinedMenuItem,
        SubmenuBuilder,
    },
    tray::TrayIconBuilder,
    AppHandle, Manager, Wry,
};
use tauri_plugin_autostart::ManagerExt;

use crate::commands::ports::{kill_process, list_ports, PortInfo};

/// Build the tray menu from a snapshot of listening ports.
fn build_menu(app: &AppHandle, ports: &[PortInfo]) -> tauri::Result<Menu<Wry>> {
    let mut mb = MenuBuilder::new(app);

    let header = MenuItemBuilder::with_id("noop:header", "Listening Processes")
        .enabled(false)
        .build(app)?;
    mb = mb.item(&header);

    if ports.is_empty() {
        let none = MenuItemBuilder::with_id("noop:none", "No listening ports")
            .enabled(false)
            .build(app)?;
        mb = mb.item(&none);
    } else {
        for p in ports.iter().take(25) {
            let open =
                MenuItemBuilder::with_id(format!("open:{}", p.port), "Open in Browser").build(app)?;
            let copy = MenuItemBuilder::with_id(format!("copy:{}", p.port), "Copy Network URL")
                .build(app)?;
            let kill = MenuItemBuilder::with_id(
                format!("kill:{}", p.pid),
                format!("Kill Process (id {})", p.pid),
            )
            .build(app)?;
            let sub = SubmenuBuilder::new(app, format!("{} · {}", p.port, p.process_name))
                .item(&open)
                .item(&copy)
                .separator()
                .item(&kill)
                .build()?;
            mb = mb.item(&sub);
        }
    }

    mb = mb.separator();

    let show = MenuItemBuilder::with_id("app:show", "Show BioLab").build(app)?;
    let autostart_on = app.autolaunch().is_enabled().unwrap_or(false);
    let login = CheckMenuItemBuilder::with_id("pref:autostart", "Open at Login")
        .checked(autostart_on)
        .build(app)?;
    let about = MenuItemBuilder::with_id("pref:about", "About BioLab").build(app)?;
    let quit = PredefinedMenuItem::quit(app, Some("Quit BioLab"))?;

    mb = mb
        .item(&show)
        .item(&login)
        .item(&about)
        .separator()
        .item(&quit);

    mb.build()
}

fn copy_to_clipboard(text: &str) {
    if let Ok(mut child) = Command::new("pbcopy").stdin(Stdio::piped()).spawn() {
        if let Some(stdin) = child.stdin.as_mut() {
            let _ = stdin.write_all(text.as_bytes());
        }
        let _ = child.wait();
    }
}

/// Rebuild the tray menu from the current port list. Safe when the menu is
/// closed (startup, after an action, on hide-to-tray) — not while it's open.
pub fn refresh(app: &AppHandle) {
    let ports = list_ports().unwrap_or_default();
    if let Ok(menu) = build_menu(app, &ports) {
        if let Some(tray) = app.tray_by_id("main") {
            let _ = tray.set_menu(Some(menu));
        }
    }
}

fn handle_menu_event(app: &AppHandle, id: &str) {
    if let Some(port) = id.strip_prefix("open:") {
        let _ = Command::new("open")
            .arg(format!("http://localhost:{}", port))
            .spawn();
    } else if let Some(port) = id.strip_prefix("copy:") {
        copy_to_clipboard(&format!("http://localhost:{}", port));
    } else if let Some(pid) = id.strip_prefix("kill:") {
        if let Ok(pid) = pid.parse::<u32>() {
            let _ = kill_process(pid, false);
        }
        refresh(app);
    } else if id == "pref:autostart" {
        let al = app.autolaunch();
        if al.is_enabled().unwrap_or(false) {
            let _ = al.disable();
        } else {
            let _ = al.enable();
        }
        refresh(app);
    } else if id == "app:show" || id == "pref:about" {
        if let Some(win) = app.get_webview_window("main") {
            let _ = win.show();
            let _ = win.set_focus();
        }
    }
}

pub fn setup(app: &AppHandle) -> tauri::Result<()> {
    let ports = list_ports().unwrap_or_default();
    let menu = build_menu(app, &ports)?;

    TrayIconBuilder::with_id("main")
        .icon(tauri::include_image!("icons/tray.png"))
        .icon_as_template(true)
        .tooltip("BioLab — Port Manager")
        .menu(&menu)
        .show_menu_on_left_click(true)
        .on_menu_event(|app, event| handle_menu_event(app, event.id().as_ref()))
        .build(app)?;

    Ok(())
}
