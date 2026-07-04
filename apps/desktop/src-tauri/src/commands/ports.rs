use std::collections::{HashMap, HashSet};
use std::process::Command;

use serde::Serialize;

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PortInfo {
    pub pid: u32,
    pub process_name: String,
    pub user: String,
    pub protocol: String,
    pub address: String,
    pub port: u16,
    /// Full command line (from `ps`), falls back to the process name.
    pub command: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ProcessDetail {
    pub pid: u32,
    pub user: String,
    pub command: String,
}

/// One `ps` call → map of pid to full command line, so the list can show real
/// commands without spawning a process per row.
fn full_commands() -> HashMap<u32, String> {
    let mut map = HashMap::new();
    if let Ok(out) = Command::new("ps").args(["-axo", "pid=,command="]).output() {
        let text = String::from_utf8_lossy(&out.stdout);
        for line in text.lines() {
            let line = line.trim_start();
            if let Some((pid_str, cmd)) = line.split_once(char::is_whitespace) {
                if let Ok(pid) = pid_str.trim().parse::<u32>() {
                    map.insert(pid, cmd.trim().to_string());
                }
            }
        }
    }
    map
}

/// Parse an lsof name field ("*:3000", "127.0.0.1:8080", "[::1]:5000") into
/// (address, port).
fn parse_name(name: &str) -> Option<(String, u16)> {
    let idx = name.rfind(':')?;
    let (addr, port_part) = name.split_at(idx);
    let port: u16 = port_part[1..].parse().ok()?;
    let addr = addr.trim_start_matches('[').trim_end_matches(']');
    let address = if addr.is_empty() {
        "*".to_string()
    } else {
        addr.to_string()
    };
    Some((address, port))
}

#[tauri::command]
pub fn list_ports() -> Result<Vec<PortInfo>, String> {
    // -FpcLPn = field output: process (p,c,L) + per-file (f, P protocol, n name).
    // +c 0 disables command-name truncation.
    let output = Command::new("lsof")
        .args(["+c", "0", "-nP", "-iTCP", "-sTCP:LISTEN", "-FpcLPn"])
        .output()
        .map_err(|e| format!("failed to run lsof: {e}"))?;

    // lsof exits non-zero when nothing matches — that's not an error for us.
    let text = String::from_utf8_lossy(&output.stdout);
    let cmd_map = full_commands();

    let mut ports: Vec<PortInfo> = Vec::new();
    let mut seen: HashSet<(u32, u16, String)> = HashSet::new();

    let mut pid: u32 = 0;
    let mut process_name = String::new();
    let mut user = String::new();
    let mut protocol = String::new();

    for line in text.lines() {
        if line.is_empty() {
            continue;
        }
        let (tag, val) = line.split_at(1);
        match tag {
            "p" => {
                pid = val.parse().unwrap_or(0);
                process_name.clear();
                user.clear();
                protocol.clear();
            }
            "c" => process_name = val.to_string(),
            "L" => user = val.to_string(),
            "f" => protocol.clear(),
            "P" => protocol = val.to_string(),
            "n" => {
                if let Some((address, port)) = parse_name(val) {
                    if seen.insert((pid, port, address.clone())) {
                        let proto = if protocol.is_empty() {
                            "TCP".to_string()
                        } else {
                            protocol.clone()
                        };
                        ports.push(PortInfo {
                            pid,
                            process_name: process_name.clone(),
                            user: user.clone(),
                            protocol: proto,
                            address,
                            port,
                            command: cmd_map
                                .get(&pid)
                                .cloned()
                                .unwrap_or_else(|| process_name.clone()),
                        });
                    }
                }
            }
            _ => {}
        }
    }

    ports.sort_by(|a, b| a.port.cmp(&b.port).then(a.pid.cmp(&b.pid)));
    Ok(ports)
}

#[tauri::command]
pub fn kill_process(pid: u32, force: bool) -> Result<(), String> {
    use nix::sys::signal::{kill, Signal};
    use nix::unistd::Pid;

    let signal = if force {
        Signal::SIGKILL
    } else {
        Signal::SIGTERM
    };

    kill(Pid::from_raw(pid as i32), signal).map_err(|e| format!("failed to kill pid {pid}: {e}"))
}

#[tauri::command]
pub fn process_details(pid: u32) -> Result<ProcessDetail, String> {
    let output = Command::new("ps")
        .args(["-p", &pid.to_string(), "-o", "user=,command="])
        .output()
        .map_err(|e| format!("failed to run ps: {e}"))?;

    let text = String::from_utf8_lossy(&output.stdout);
    let line = text.trim();
    if line.is_empty() {
        return Err(format!("process {pid} not found"));
    }

    let (user, command) = line
        .split_once(char::is_whitespace)
        .unwrap_or((line, ""));

    Ok(ProcessDetail {
        pid,
        user: user.trim().to_string(),
        command: command.trim().to_string(),
    })
}
