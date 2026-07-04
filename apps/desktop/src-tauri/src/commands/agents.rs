//! Cross-agent config manager: discover and control MCP servers, skills,
//! symlinks and context files (CLAUDE.md / AGENTS.md) across Claude Code,
//! Codex and OpenCode. Every mutation backs the target file up first.

use std::collections::BTreeMap;
use std::fs;
use std::os::unix::fs as unix_fs;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};

// ---------------------------------------------------------------------------
// Paths
// ---------------------------------------------------------------------------

fn home() -> PathBuf {
    PathBuf::from(std::env::var("HOME").unwrap_or_default())
}

fn claude_json() -> PathBuf {
    home().join(".claude.json")
}
fn claude_skills() -> PathBuf {
    home().join(".claude/skills")
}
fn claude_agents() -> PathBuf {
    home().join(".claude/agents")
}
fn codex_toml() -> PathBuf {
    home().join(".codex/config.toml")
}
fn codex_skills() -> PathBuf {
    home().join(".codex/skills")
}
fn opencode_json() -> PathBuf {
    home().join(".config/opencode/opencode.json")
}
fn opencode_skills() -> PathBuf {
    home().join(".config/opencode/skills")
}
fn central_skills() -> PathBuf {
    home().join(".agents/skills")
}
fn biolab_dir() -> PathBuf {
    home().join(".biolab")
}
fn backups_dir() -> PathBuf {
    biolab_dir().join("backups")
}
fn disabled_stash() -> PathBuf {
    biolab_dir().join("disabled-mcp.json")
}

/// Config file for a given tool id.
fn tool_config(tool: &str) -> Result<PathBuf, String> {
    match tool {
        "claude" => Ok(claude_json()),
        "codex" => Ok(codex_toml()),
        "opencode" => Ok(opencode_json()),
        _ => Err(format!("unknown tool: {tool}")),
    }
}

/// Skills directory for a given tool id.
fn tool_skills_dir(tool: &str) -> Result<PathBuf, String> {
    match tool {
        "claude" => Ok(claude_skills()),
        "codex" => Ok(codex_skills()),
        "opencode" => Ok(opencode_skills()),
        "central" => Ok(central_skills()),
        _ => Err(format!("unknown tool: {tool}")),
    }
}

fn to_str(p: &Path) -> String {
    p.to_string_lossy().into_owned()
}

// ---------------------------------------------------------------------------
// Data model (serialized camelCase to the frontend)
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AgentTool {
    pub id: String,
    pub name: String,
    pub installed: bool,
    pub config_path: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct McpServer {
    pub name: String,
    pub tool: String,
    pub transport: String, // "stdio" | "http"
    #[serde(default)]
    pub command: Option<String>,
    #[serde(default)]
    pub args: Vec<String>,
    #[serde(default)]
    pub env: BTreeMap<String, String>,
    #[serde(default)]
    pub url: Option<String>,
    #[serde(default = "default_true")]
    pub enabled: bool,
    #[serde(default)]
    pub source: String,
}

fn default_true() -> bool {
    true
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Skill {
    pub name: String,
    pub tool: String,
    pub path: String,
    pub is_symlink: bool,
    pub target: Option<String>,
    pub broken: bool,
    pub description: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SymlinkEntry {
    pub path: String,
    pub target: String,
    pub resolved: String,
    pub broken: bool,
    pub category: String, // "skill" | "agent" | "other"
    pub tool: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ContextFile {
    pub scope: String, // "global" or a project name
    pub tool: String,  // "claude" | "codex" | "opencode" | "shared"
    pub kind: String,  // "CLAUDE.md" | "AGENTS.md"
    pub path: String,
    pub exists: bool,
    pub bytes: u64,
    pub modified: Option<u64>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AgentInventory {
    pub tools: Vec<AgentTool>,
    pub mcp_servers: Vec<McpServer>,
    pub disabled: Vec<McpServer>,
    pub skills: Vec<Skill>,
    pub symlinks: Vec<SymlinkEntry>,
    pub context_files: Vec<ContextFile>,
    pub central_skills_dir: String,
}

// ---------------------------------------------------------------------------
// Low-level file helpers
// ---------------------------------------------------------------------------

fn read_json(path: &Path) -> Value {
    fs::read_to_string(path)
        .ok()
        .and_then(|t| serde_json::from_str(&t).ok())
        .unwrap_or(Value::Null)
}

fn write_json_pretty(path: &Path, value: &Value) -> Result<(), String> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    }
    let text = serde_json::to_string_pretty(value).map_err(|e| e.to_string())?;
    fs::write(path, text + "\n").map_err(|e| e.to_string())
}

fn read_toml_doc(path: &Path) -> Result<toml_edit::DocumentMut, String> {
    let text = fs::read_to_string(path).unwrap_or_default();
    text.parse::<toml_edit::DocumentMut>()
        .map_err(|e| format!("failed to parse {}: {e}", to_str(path)))
}

fn write_toml_doc(path: &Path, doc: &toml_edit::DocumentMut) -> Result<(), String> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    }
    fs::write(path, doc.to_string()).map_err(|e| e.to_string())
}

/// Copy a file into ~/.biolab/backups with a timestamp prefix. No-op if the
/// file does not exist yet. Returns the backup path when made.
fn backup_file(path: &Path) -> Option<String> {
    if !path.exists() {
        return None;
    }
    let ts = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    let name = path
        .file_name()
        .map(|n| n.to_string_lossy().into_owned())
        .unwrap_or_else(|| "file".into());
    let dir = backups_dir();
    fs::create_dir_all(&dir).ok()?;
    let dest = dir.join(format!("{ts}-{name}"));
    fs::copy(path, &dest).ok()?;
    Some(to_str(&dest))
}

// ---------------------------------------------------------------------------
// MCP: parsing each tool's format into the normalized McpServer
// ---------------------------------------------------------------------------

fn json_str(v: &Value, key: &str) -> Option<String> {
    v.get(key).and_then(|x| x.as_str()).map(String::from)
}

fn json_args(v: &Value) -> Vec<String> {
    v.get("args")
        .and_then(|a| a.as_array())
        .map(|a| a.iter().filter_map(|e| e.as_str().map(String::from)).collect())
        .unwrap_or_default()
}

fn json_env(v: &Value) -> BTreeMap<String, String> {
    let mut env = BTreeMap::new();
    if let Some(obj) = v.get("env").and_then(|e| e.as_object()) {
        for (k, val) in obj {
            if let Some(s) = val.as_str() {
                env.insert(k.clone(), s.to_string());
            }
        }
    }
    env
}

/// Claude (`.claude.json`) style server object.
fn parse_claude_server(name: &str, v: &Value, source: &str) -> McpServer {
    let url = json_str(v, "url");
    let declared = json_str(v, "type").unwrap_or_default();
    let transport = if declared == "http" || declared == "sse" || (url.is_some() && declared.is_empty())
    {
        "http".to_string()
    } else {
        "stdio".to_string()
    };
    McpServer {
        name: name.to_string(),
        tool: "claude".to_string(),
        transport,
        command: json_str(v, "command"),
        args: json_args(v),
        env: json_env(v),
        url,
        enabled: true,
        source: source.to_string(),
    }
}

fn scan_claude_mcp() -> Vec<McpServer> {
    let path = claude_json();
    let json = read_json(&path);
    let mut out = Vec::new();
    if let Some(obj) = json.get("mcpServers").and_then(|m| m.as_object()) {
        for (name, def) in obj {
            out.push(parse_claude_server(name, def, &to_str(&path)));
        }
    }
    out
}

fn toml_str(item: &toml_edit::Item, key: &str) -> Option<String> {
    item.get(key).and_then(|v| v.as_str()).map(String::from)
}

fn scan_codex_mcp() -> Vec<McpServer> {
    let path = codex_toml();
    let source = to_str(&path);
    let mut out = Vec::new();
    let Ok(doc) = read_toml_doc(&path) else {
        return out;
    };
    let Some(table) = doc.get("mcp_servers").and_then(|i| i.as_table()) else {
        return out;
    };
    for (name, item) in table.iter() {
        let url = toml_str(item, "url");
        let transport = if url.is_some() { "http" } else { "stdio" }.to_string();
        let args = item
            .get("args")
            .and_then(|a| a.as_array())
            .map(|a| a.iter().filter_map(|e| e.as_str().map(String::from)).collect())
            .unwrap_or_default();
        let mut env = BTreeMap::new();
        if let Some(env_t) = item.get("env").and_then(|e| e.as_table()) {
            for (k, v) in env_t.iter() {
                if let Some(s) = v.as_str() {
                    env.insert(k.to_string(), s.to_string());
                }
            }
        }
        out.push(McpServer {
            name: name.to_string(),
            tool: "codex".to_string(),
            transport,
            command: toml_str(item, "command"),
            args,
            env,
            url,
            enabled: true,
            source: source.clone(),
        });
    }
    out
}

fn scan_opencode_mcp() -> Vec<McpServer> {
    let path = opencode_json();
    let source = to_str(&path);
    let json = read_json(&path);
    let mut out = Vec::new();
    if let Some(obj) = json.get("mcp").and_then(|m| m.as_object()) {
        for (name, def) in obj {
            let kind = json_str(def, "type").unwrap_or_default();
            let is_remote = kind == "remote" || def.get("url").is_some();
            // OpenCode "local" packs the command + args into one array.
            let cmd_arr: Vec<String> = def
                .get("command")
                .and_then(|c| c.as_array())
                .map(|a| a.iter().filter_map(|e| e.as_str().map(String::from)).collect())
                .unwrap_or_default();
            let (command, args) = if cmd_arr.is_empty() {
                (None, Vec::new())
            } else {
                (Some(cmd_arr[0].clone()), cmd_arr[1..].to_vec())
            };
            out.push(McpServer {
                name: name.to_string(),
                tool: "opencode".to_string(),
                transport: if is_remote { "http" } else { "stdio" }.to_string(),
                command,
                args,
                env: json_env(def),
                url: json_str(def, "url"),
                enabled: def.get("enabled").and_then(|e| e.as_bool()).unwrap_or(true),
                source: source.clone(),
            });
        }
    }
    out
}

fn read_stash() -> Vec<McpServer> {
    let json = read_json(&disabled_stash());
    serde_json::from_value(json).unwrap_or_default()
}

fn write_stash(list: &[McpServer]) -> Result<(), String> {
    let value = serde_json::to_value(list).map_err(|e| e.to_string())?;
    write_json_pretty(&disabled_stash(), &value)
}

// ---------------------------------------------------------------------------
// MCP: serializing the normalized McpServer back to each tool's format
// ---------------------------------------------------------------------------

fn claude_value(s: &McpServer) -> Value {
    let mut m = Map::new();
    m.insert("type".into(), Value::String(s.transport.clone()));
    if s.transport == "http" {
        if let Some(url) = &s.url {
            m.insert("url".into(), Value::String(url.clone()));
        }
    } else {
        if let Some(cmd) = &s.command {
            m.insert("command".into(), Value::String(cmd.clone()));
        }
        m.insert(
            "args".into(),
            Value::Array(s.args.iter().cloned().map(Value::String).collect()),
        );
        let env: Map<String, Value> = s
            .env
            .iter()
            .map(|(k, v)| (k.clone(), Value::String(v.clone())))
            .collect();
        m.insert("env".into(), Value::Object(env));
    }
    Value::Object(m)
}

fn opencode_value(s: &McpServer) -> Value {
    let mut m = Map::new();
    if s.transport == "http" {
        m.insert("type".into(), Value::String("remote".into()));
        if let Some(url) = &s.url {
            m.insert("url".into(), Value::String(url.clone()));
        }
    } else {
        m.insert("type".into(), Value::String("local".into()));
        let mut cmd: Vec<Value> = Vec::new();
        if let Some(c) = &s.command {
            cmd.push(Value::String(c.clone()));
        }
        cmd.extend(s.args.iter().cloned().map(Value::String));
        m.insert("command".into(), Value::Array(cmd));
    }
    m.insert("enabled".into(), Value::Bool(s.enabled));
    Value::Object(m)
}

fn codex_item(s: &McpServer) -> toml_edit::Item {
    use toml_edit::{value, Array, Item, Table};
    let mut t = Table::new();
    if s.transport == "http" {
        if let Some(url) = &s.url {
            t["url"] = value(url.clone());
        }
    } else {
        if let Some(cmd) = &s.command {
            t["command"] = value(cmd.clone());
        }
        let mut arr = Array::new();
        for a in &s.args {
            arr.push(a.clone());
        }
        t["args"] = value(arr);
        if !s.env.is_empty() {
            let mut env_t = Table::new();
            for (k, v) in &s.env {
                env_t[k] = value(v.clone());
            }
            t["env"] = Item::Table(env_t);
        }
    }
    Item::Table(t)
}

/// Insert or replace a server in the destination tool (`server.tool`).
fn upsert(server: &McpServer) -> Result<(), String> {
    let path = tool_config(&server.tool)?;
    backup_file(&path);
    match server.tool.as_str() {
        "claude" => {
            let mut json = read_json(&path);
            if !json.is_object() {
                json = Value::Object(Map::new());
            }
            let obj = json.as_object_mut().unwrap();
            let servers = obj
                .entry("mcpServers")
                .or_insert_with(|| Value::Object(Map::new()));
            if let Some(map) = servers.as_object_mut() {
                map.insert(server.name.clone(), claude_value(server));
            }
            write_json_pretty(&path, &json)
        }
        "opencode" => {
            let mut json = read_json(&path);
            if !json.is_object() {
                let mut m = Map::new();
                m.insert(
                    "$schema".into(),
                    Value::String("https://opencode.ai/config.json".into()),
                );
                json = Value::Object(m);
            }
            let obj = json.as_object_mut().unwrap();
            let servers = obj.entry("mcp").or_insert_with(|| Value::Object(Map::new()));
            if let Some(map) = servers.as_object_mut() {
                map.insert(server.name.clone(), opencode_value(server));
            }
            write_json_pretty(&path, &json)
        }
        "codex" => {
            let mut doc = read_toml_doc(&path)?;
            if doc.get("mcp_servers").and_then(|i| i.as_table()).is_none() {
                doc["mcp_servers"] = toml_edit::Item::Table(toml_edit::Table::new());
            }
            doc["mcp_servers"][&server.name] = codex_item(server);
            write_toml_doc(&path, &doc)
        }
        other => Err(format!("unknown tool: {other}")),
    }
}

/// Remove a server from a tool's config file.
fn remove_from_tool(tool: &str, name: &str) -> Result<(), String> {
    let path = tool_config(tool)?;
    backup_file(&path);
    match tool {
        "claude" => {
            let mut json = read_json(&path);
            if let Some(map) = json.get_mut("mcpServers").and_then(|m| m.as_object_mut()) {
                map.remove(name);
            }
            write_json_pretty(&path, &json)
        }
        "opencode" => {
            let mut json = read_json(&path);
            if let Some(map) = json.get_mut("mcp").and_then(|m| m.as_object_mut()) {
                map.remove(name);
            }
            write_json_pretty(&path, &json)
        }
        "codex" => {
            let mut doc = read_toml_doc(&path)?;
            if let Some(table) = doc.get_mut("mcp_servers").and_then(|i| i.as_table_mut()) {
                table.remove(name);
            }
            write_toml_doc(&path, &doc)
        }
        other => Err(format!("unknown tool: {other}")),
    }
}

// ---------------------------------------------------------------------------
// Skills & symlinks scanning
// ---------------------------------------------------------------------------

fn skill_description(skill_dir: &Path) -> Option<String> {
    let md = skill_dir.join("SKILL.md");
    let text = fs::read_to_string(md).ok()?;
    let mut in_front = false;
    for line in text.lines() {
        let trimmed = line.trim();
        if trimmed == "---" {
            if in_front {
                break;
            }
            in_front = true;
            continue;
        }
        if in_front {
            if let Some(rest) = trimmed.strip_prefix("description:") {
                let val = rest.trim().trim_matches('"').trim_matches('\'').trim();
                if !val.is_empty() {
                    return Some(val.to_string());
                }
            }
        }
    }
    None
}

fn scan_skills_in(dir: &Path, tool: &str, skills: &mut Vec<Skill>) {
    let Ok(entries) = fs::read_dir(dir) else {
        return;
    };
    for entry in entries.flatten() {
        let path = entry.path();
        let name = entry.file_name().to_string_lossy().into_owned();
        if name.starts_with('.') {
            continue;
        }
        let meta = match fs::symlink_metadata(&path) {
            Ok(m) => m,
            Err(_) => continue,
        };
        let is_symlink = meta.file_type().is_symlink();
        // Only surface directories (real or via symlink), not stray files.
        if !is_symlink && !meta.is_dir() {
            continue;
        }
        let (target, broken) = if is_symlink {
            let raw = fs::read_link(&path).ok().map(|p| to_str(&p));
            (raw, fs::canonicalize(&path).is_err())
        } else {
            (None, false)
        };
        let description = if broken {
            None
        } else {
            skill_description(&path)
        };
        skills.push(Skill {
            name,
            tool: tool.to_string(),
            path: to_str(&path),
            is_symlink,
            target,
            broken,
            description,
        });
    }
}

fn collect_symlinks(dir: &Path, category: &str, tool: &str, out: &mut Vec<SymlinkEntry>) {
    let Ok(entries) = fs::read_dir(dir) else {
        return;
    };
    for entry in entries.flatten() {
        let path = entry.path();
        let Ok(meta) = fs::symlink_metadata(&path) else {
            continue;
        };
        if !meta.file_type().is_symlink() {
            continue;
        }
        let target = fs::read_link(&path).map(|p| to_str(&p)).unwrap_or_default();
        let canonical = fs::canonicalize(&path);
        let broken = canonical.is_err();
        let resolved = canonical.map(|p| to_str(&p)).unwrap_or_else(|_| {
            // Best-effort resolution for display when the link is dangling.
            let raw = PathBuf::from(&target);
            if raw.is_absolute() {
                target.clone()
            } else {
                to_str(&path.parent().unwrap_or(dir).join(&raw))
            }
        });
        out.push(SymlinkEntry {
            path: to_str(&path),
            target,
            resolved,
            broken,
            category: category.to_string(),
            tool: tool.to_string(),
        });
    }
}

// ---------------------------------------------------------------------------
// Context files scanning
// ---------------------------------------------------------------------------

fn context_meta(path: &Path) -> (bool, u64, Option<u64>) {
    match fs::metadata(path) {
        Ok(m) => {
            let modified = m
                .modified()
                .ok()
                .and_then(|t| t.duration_since(UNIX_EPOCH).ok())
                .map(|d| d.as_secs());
            (true, m.len(), modified)
        }
        Err(_) => (false, 0, None),
    }
}

fn push_context(list: &mut Vec<ContextFile>, scope: &str, tool: &str, kind: &str, path: PathBuf) {
    let (exists, bytes, modified) = context_meta(&path);
    list.push(ContextFile {
        scope: scope.to_string(),
        tool: tool.to_string(),
        kind: kind.to_string(),
        path: to_str(&path),
        exists,
        bytes,
        modified,
    });
}

fn scan_context_files() -> Vec<ContextFile> {
    let mut list = Vec::new();

    // Global instruction files, always shown (even if absent, so they can be created).
    push_context(&mut list, "global", "claude", "CLAUDE.md", home().join(".claude/CLAUDE.md"));
    push_context(&mut list, "global", "codex", "AGENTS.md", home().join(".codex/AGENTS.md"));
    push_context(
        &mut list,
        "global",
        "opencode",
        "AGENTS.md",
        home().join(".config/opencode/AGENTS.md"),
    );

    // Per-project files discovered from Claude's known project list.
    let claude = read_json(&claude_json());
    if let Some(projects) = claude.get("projects").and_then(|p| p.as_object()) {
        for dir in projects.keys() {
            let base = PathBuf::from(dir);
            let scope = base
                .file_name()
                .map(|n| n.to_string_lossy().into_owned())
                .unwrap_or_else(|| dir.clone());
            for (kind, tool) in [("CLAUDE.md", "claude"), ("AGENTS.md", "shared")] {
                let path = base.join(kind);
                if path.exists() {
                    push_context(&mut list, &scope, tool, kind, path);
                }
            }
        }
    }

    list
}

// ---------------------------------------------------------------------------
// Commands
// ---------------------------------------------------------------------------

#[tauri::command]
pub fn scan_agents() -> Result<AgentInventory, String> {
    let tools = vec![
        AgentTool {
            id: "claude".into(),
            name: "Claude Code".into(),
            installed: home().join(".claude").is_dir(),
            config_path: to_str(&claude_json()),
        },
        AgentTool {
            id: "codex".into(),
            name: "Codex".into(),
            installed: home().join(".codex").is_dir(),
            config_path: to_str(&codex_toml()),
        },
        AgentTool {
            id: "opencode".into(),
            name: "OpenCode".into(),
            installed: home().join(".config/opencode").is_dir(),
            config_path: to_str(&opencode_json()),
        },
    ];

    let mut mcp_servers = Vec::new();
    mcp_servers.extend(scan_claude_mcp());
    mcp_servers.extend(scan_codex_mcp());
    mcp_servers.extend(scan_opencode_mcp());
    mcp_servers.sort_by(|a, b| a.name.cmp(&b.name).then(a.tool.cmp(&b.tool)));

    let disabled = read_stash();

    let mut skills = Vec::new();
    scan_skills_in(&central_skills(), "central", &mut skills);
    scan_skills_in(&claude_skills(), "claude", &mut skills);
    scan_skills_in(&codex_skills(), "codex", &mut skills);
    scan_skills_in(&opencode_skills(), "opencode", &mut skills);
    skills.sort_by(|a, b| a.name.cmp(&b.name).then(a.tool.cmp(&b.tool)));

    let mut symlinks = Vec::new();
    collect_symlinks(&claude_skills(), "skill", "claude", &mut symlinks);
    collect_symlinks(&claude_agents(), "agent", "claude", &mut symlinks);
    collect_symlinks(&codex_skills(), "skill", "codex", &mut symlinks);
    collect_symlinks(&opencode_skills(), "skill", "opencode", &mut symlinks);
    collect_symlinks(&central_skills(), "skill", "central", &mut symlinks);
    symlinks.sort_by(|a, b| a.path.cmp(&b.path));

    let context_files = scan_context_files();

    Ok(AgentInventory {
        tools,
        mcp_servers,
        disabled,
        skills,
        symlinks,
        context_files,
        central_skills_dir: to_str(&central_skills()),
    })
}

/// Add a new server, or edit an existing one, in `server.tool`.
#[tauri::command]
pub fn mcp_upsert(server: McpServer) -> Result<(), String> {
    upsert(&server)
}

/// Delete a server from a tool.
#[tauri::command]
pub fn mcp_remove(tool: String, name: String) -> Result<(), String> {
    remove_from_tool(&tool, &name)
    // Also drop it from the disabled stash if present.
    .and_then(|_| {
        let mut stash = read_stash();
        let before = stash.len();
        stash.retain(|s| !(s.tool == tool && s.name == name));
        if stash.len() != before {
            write_stash(&stash)?;
        }
        Ok(())
    })
}

/// Copy a server's definition into each of `targets` (format-translated).
#[tauri::command]
pub fn mcp_sync(server: McpServer, targets: Vec<String>) -> Result<(), String> {
    for tool in targets {
        let mut copy = server.clone();
        copy.tool = tool;
        copy.source = String::new();
        upsert(&copy)?;
    }
    Ok(())
}

/// Enable/disable a server. OpenCode flips its native `enabled` flag; Claude and
/// Codex have no such flag, so we stash the definition and remove it from the
/// live config (restoring it on re-enable).
#[tauri::command]
pub fn mcp_set_enabled(server: McpServer, enabled: bool) -> Result<(), String> {
    if server.tool == "opencode" {
        let path = opencode_json();
        backup_file(&path);
        let mut json = read_json(&path);
        if let Some(def) = json.get_mut("mcp").and_then(|m| m.get_mut(&server.name)) {
            if let Some(obj) = def.as_object_mut() {
                obj.insert("enabled".into(), Value::Bool(enabled));
            }
        }
        return write_json_pretty(&path, &json);
    }

    let mut stash = read_stash();
    if enabled {
        // Restore from stash into the live config.
        if let Some(pos) = stash
            .iter()
            .position(|s| s.tool == server.tool && s.name == server.name)
        {
            let mut restored = stash.remove(pos);
            restored.enabled = true;
            upsert(&restored)?;
            write_stash(&stash)?;
        }
    } else {
        // Stash the current definition, then remove it from the live config.
        let mut stashed = server.clone();
        stashed.enabled = false;
        stash.retain(|s| !(s.tool == stashed.tool && s.name == stashed.name));
        stash.push(stashed);
        write_stash(&stash)?;
        remove_from_tool(&server.tool, &server.name)?;
    }
    Ok(())
}

/// Read a skill's SKILL.md.
#[tauri::command]
pub fn skill_read(path: String) -> Result<String, String> {
    let md = PathBuf::from(&path).join("SKILL.md");
    fs::read_to_string(&md).map_err(|e| format!("failed to read {}: {e}", to_str(&md)))
}

/// Move a skill folder into the central store (~/.agents/skills) and replace the
/// original location with a symlink, so it can be shared across agents.
#[tauri::command]
pub fn skill_share(name: String, source_path: String) -> Result<String, String> {
    let source = PathBuf::from(&source_path);
    let central = central_skills();
    fs::create_dir_all(&central).map_err(|e| e.to_string())?;
    let dest = central.join(&name);

    // Already living in the central store — nothing to move.
    if source == dest {
        return Ok(to_str(&dest));
    }

    let is_symlink = fs::symlink_metadata(&source)
        .map(|m| m.file_type().is_symlink())
        .unwrap_or(false);

    if !dest.exists() {
        if is_symlink {
            // Source is already a link; copy the resolved contents into central.
            copy_dir(&fs::canonicalize(&source).map_err(|e| e.to_string())?, &dest)?;
        } else {
            copy_dir(&source, &dest)?;
        }
    }

    // Replace the original with a symlink to the central copy.
    if is_symlink {
        fs::remove_file(&source).map_err(|e| e.to_string())?;
    } else if source.exists() {
        fs::remove_dir_all(&source).map_err(|e| e.to_string())?;
    }
    unix_fs::symlink(&dest, &source).map_err(|e| e.to_string())?;
    Ok(to_str(&dest))
}

/// Symlink a central skill into a tool's skills directory.
#[tauri::command]
pub fn skill_link(tool: String, name: String) -> Result<(), String> {
    let central = central_skills().join(&name);
    if !central.exists() {
        return Err(format!("no central skill named {name}"));
    }
    let dir = tool_skills_dir(&tool)?;
    fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    let link = dir.join(&name);
    if link.exists() || fs::symlink_metadata(&link).is_ok() {
        return Err(format!("{} already exists", to_str(&link)));
    }
    unix_fs::symlink(&central, &link).map_err(|e| e.to_string())
}

/// Remove a symlink (skills or anywhere else). Refuses non-symlinks for safety.
#[tauri::command]
pub fn symlink_remove(path: String) -> Result<(), String> {
    let p = PathBuf::from(&path);
    let meta = fs::symlink_metadata(&p).map_err(|e| e.to_string())?;
    if !meta.file_type().is_symlink() {
        return Err(format!("{path} is not a symlink"));
    }
    fs::remove_file(&p).map_err(|e| e.to_string())
}

/// Create a symlink at `link_path` pointing to `target`.
#[tauri::command]
pub fn symlink_create(target: String, link_path: String) -> Result<(), String> {
    let link = PathBuf::from(&link_path);
    if let Some(parent) = link.parent() {
        fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    }
    if fs::symlink_metadata(&link).is_ok() {
        return Err(format!("{link_path} already exists"));
    }
    unix_fs::symlink(PathBuf::from(&target), &link).map_err(|e| e.to_string())
}

/// Repoint a broken/existing symlink at a new target.
#[tauri::command]
pub fn symlink_repair(path: String, target: String) -> Result<(), String> {
    let link = PathBuf::from(&path);
    if fs::symlink_metadata(&link).is_ok() {
        fs::remove_file(&link).map_err(|e| e.to_string())?;
    }
    unix_fs::symlink(PathBuf::from(&target), &link).map_err(|e| e.to_string())
}

/// Read a context/instruction file (returns empty string if absent).
#[tauri::command]
pub fn context_read(path: String) -> Result<String, String> {
    let p = PathBuf::from(&path);
    if !p.exists() {
        return Ok(String::new());
    }
    fs::read_to_string(&p).map_err(|e| format!("failed to read {path}: {e}"))
}

/// Write a context/instruction file, backing up any existing version first.
#[tauri::command]
pub fn context_write(path: String, content: String) -> Result<Option<String>, String> {
    let p = PathBuf::from(&path);
    let backup = backup_file(&p);
    if let Some(parent) = p.parent() {
        fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    }
    fs::write(&p, content).map_err(|e| format!("failed to write {path}: {e}"))?;
    Ok(backup)
}

// ---------------------------------------------------------------------------
// Utilities
// ---------------------------------------------------------------------------

/// Recursively copy a directory tree.
fn copy_dir(from: &Path, to: &Path) -> Result<(), String> {
    fs::create_dir_all(to).map_err(|e| e.to_string())?;
    for entry in fs::read_dir(from).map_err(|e| e.to_string())? {
        let entry = entry.map_err(|e| e.to_string())?;
        let src = entry.path();
        let dst = to.join(entry.file_name());
        let ft = entry.file_type().map_err(|e| e.to_string())?;
        if ft.is_dir() {
            copy_dir(&src, &dst)?;
        } else {
            fs::copy(&src, &dst).map_err(|e| e.to_string())?;
        }
    }
    Ok(())
}
