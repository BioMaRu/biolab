use std::io::Write;
use std::process::{Command, Stdio};
use std::time::Duration;

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
use crate::commands::usage::{agent_summaries, AgentSummary};

/// A disabled (non-clickable) text row — used for headers and detail lines.
/// Each needs a unique id, so callers thread a running counter.
fn label(app: &AppHandle, n: &mut usize, text: &str) -> tauri::Result<tauri::menu::MenuItem<Wry>> {
    *n += 1;
    MenuItemBuilder::with_id(format!("noop:{n}"), text)
        .enabled(false)
        .build(app)
}

/// The full menu: AI Usage (per-agent submenus) + Ports + actions.
fn build_menu_from(
    app: &AppHandle,
    summaries: &[AgentSummary],
    ports: &[PortInfo],
) -> tauri::Result<Menu<Wry>> {
    let mut n = 0usize;
    let mut mb = MenuBuilder::new(app);

    // --- AI Usage -----------------------------------------------------------
    mb = mb.item(&label(app, &mut n, "AI Usage")?);
    for s in summaries {
        let title = if s.headline.is_empty() {
            s.name.clone()
        } else {
            format!("{} · {}", s.name, s.headline)
        };
        let mut sub = SubmenuBuilder::new(app, title);
        for line in &s.lines {
            sub = sub.item(&label(app, &mut n, line)?);
        }
        mb = mb.item(&sub.build()?);
    }

    mb = mb.separator();

    // --- Ports --------------------------------------------------------------
    mb = mb.item(&label(app, &mut n, &format!("Ports ({})", ports.len()))?);
    if ports.is_empty() {
        mb = mb.item(&label(app, &mut n, "No listening ports")?);
    } else {
        for p in ports.iter().take(20) {
            let open = MenuItemBuilder::with_id(format!("open:{}", p.port), "Open in Browser")
                .build(app)?;
            let copy =
                MenuItemBuilder::with_id(format!("copy:{}", p.port), "Copy Network URL").build(app)?;
            let kill = MenuItemBuilder::with_id(
                format!("kill:{}", p.pid),
                format!("Kill Process (pid {})", p.pid),
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

    // --- Actions ------------------------------------------------------------
    let show = MenuItemBuilder::with_id("app:show", "Open BioLab").build(app)?;
    let autostart_on = app.autolaunch().is_enabled().unwrap_or(false);
    let login = CheckMenuItemBuilder::with_id("pref:autostart", "Open at Login")
        .checked(autostart_on)
        .build(app)?;
    let quit = PredefinedMenuItem::quit(app, Some("Quit BioLab"))?;
    mb = mb.item(&show).item(&login).separator().item(&quit);

    mb.build()
}

/// A lightweight menu shown instantly at startup, before usage data loads.
fn initial_menu(app: &AppHandle) -> tauri::Result<Menu<Wry>> {
    let loading = MenuItemBuilder::with_id("noop:loading", "Loading usage…")
        .enabled(false)
        .build(app)?;
    let show = MenuItemBuilder::with_id("app:show", "Open BioLab").build(app)?;
    let autostart_on = app.autolaunch().is_enabled().unwrap_or(false);
    let login = CheckMenuItemBuilder::with_id("pref:autostart", "Open at Login")
        .checked(autostart_on)
        .build(app)?;
    let quit = PredefinedMenuItem::quit(app, Some("Quit BioLab"))?;

    MenuBuilder::new(app)
        .item(&loading)
        .separator()
        .item(&show)
        .item(&login)
        .separator()
        .item(&quit)
        .build()
}

/// Gather data (off the main thread) then rebuild + attach the menu on the main
/// thread. Reading usage limits touches the Keychain + network, so it must stay
/// off-main to keep the UI responsive.
fn apply(app: &AppHandle) {
    let summaries = agent_summaries();
    let ports = list_ports().unwrap_or_default();
    let app2 = app.clone();
    let _ = app.run_on_main_thread(move || {
        if let Ok(menu) = build_menu_from(&app2, &summaries, &ports) {
            if let Some(tray) = app2.tray_by_id("main") {
                let _ = tray.set_menu(Some(menu));
            }
        }
    });
}

/// Refresh the tray menu from current data, off the main thread.
pub fn refresh(app: &AppHandle) {
    let app = app.clone();
    std::thread::spawn(move || apply(&app));
}

fn copy_to_clipboard(text: &str) {
    if let Ok(mut child) = Command::new("pbcopy").stdin(Stdio::piped()).spawn() {
        if let Some(stdin) = child.stdin.as_mut() {
            let _ = stdin.write_all(text.as_bytes());
        }
        let _ = child.wait();
    }
}

fn handle_menu_event(app: &AppHandle, id: &str) {
    if let Some(port) = id.strip_prefix("open:") {
        let _ = Command::new("open")
            .arg(format!("http://localhost:{port}"))
            .spawn();
    } else if let Some(port) = id.strip_prefix("copy:") {
        copy_to_clipboard(&format!("http://localhost:{port}"));
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
    } else if id == "app:show" {
        if let Some(win) = app.get_webview_window("main") {
            let _ = win.show();
            let _ = win.set_focus();
        }
    }
}

pub fn setup(app: &AppHandle) -> tauri::Result<()> {
    let menu = initial_menu(app)?;

    TrayIconBuilder::with_id("main")
        .icon(tauri::include_image!("icons/tray.png"))
        .icon_as_template(true)
        .tooltip("BioLab")
        .menu(&menu)
        .show_menu_on_left_click(true)
        .on_menu_event(|app, event| handle_menu_event(app, event.id().as_ref()))
        .build(app)?;

    // Populate with live usage + ports in the background, then keep it fresh.
    refresh(app);
    let app_t = app.clone();
    std::thread::spawn(move || loop {
        std::thread::sleep(Duration::from_secs(60));
        apply(&app_t);
    });

    Ok(())
}
