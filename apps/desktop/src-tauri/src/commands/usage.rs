//! AI usage analytics — a CodexBar-style view of how much each agent CLI is
//! consuming, read entirely from local data (no auth, no network):
//!   * Claude Code — rich JSONL transcripts (~/.claude/projects/**/*.jsonl).
//!   * Codex       — `response.completed` events in ~/.codex/logs_2.sqlite.
//!   * OpenCode    — per-session token/cost columns in opencode.db.
//! Token counts are exact; costs are estimates from public model pricing
//! (except OpenCode, which records its own cost).

use std::collections::{HashMap, HashSet};
use std::fs;
use std::io::{BufRead, BufReader};
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::{SystemTime, UNIX_EPOCH};

use rusqlite::{Connection, OpenFlags};
use serde::Serialize;
use serde_json::Value;

fn home() -> PathBuf {
    PathBuf::from(std::env::var("HOME").unwrap_or_default())
}

fn now_secs() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}

const SESSION_SECS: i64 = 5 * 3600;
const DAY_SECS: i64 = 24 * 3600;
const WEEK_SECS: i64 = 7 * 24 * 3600;

// --- ISO-8601 (UTC "…Z") -> epoch seconds, dependency-free ------------------

fn days_from_civil(y: i64, m: i64, d: i64) -> i64 {
    let y = if m <= 2 { y - 1 } else { y };
    let era = (if y >= 0 { y } else { y - 399 }) / 400;
    let yoe = y - era * 400;
    let mp = if m > 2 { m - 3 } else { m + 9 };
    let doy = (153 * mp + 2) / 5 + d - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    era * 146097 + doe - 719468
}

fn parse_ts(s: &str) -> Option<i64> {
    let (date, rest) = s.split_once('T')?;
    let mut dp = date.split('-');
    let y: i64 = dp.next()?.parse().ok()?;
    let mo: i64 = dp.next()?.parse().ok()?;
    let d: i64 = dp.next()?.parse().ok()?;
    let time = rest.trim_end_matches('Z').split('.').next()?;
    let mut tp = time.split(':');
    let h: i64 = tp.next()?.parse().ok()?;
    let mi: i64 = tp.next()?.parse().ok()?;
    let se: i64 = tp.next().unwrap_or("0").parse().ok()?;
    Some(days_from_civil(y, mo, d) * 86400 + h * 3600 + mi * 60 + se)
}

/// Pull `key=<int>` out of a Codex tracing log line (e.g. `total_usage_tokens=169180`).
fn kv_int(s: &str, key: &str) -> Option<i64> {
    let i = s.find(key)?;
    let rest = &s[i + key.len()..];
    let end = rest.find(|c: char| !c.is_ascii_digit()).unwrap_or(rest.len());
    rest[..end].parse().ok()
}

/// Pull `key=<token>` (up to whitespace / `}`) out of a Codex tracing log line.
fn kv_str(s: &str, key: &str) -> Option<String> {
    let i = s.find(key)?;
    let rest = &s[i + key.len()..];
    let end = rest
        .find(|c: char| c == ' ' || c == '}' || c == '\n')
        .unwrap_or(rest.len());
    let val = &rest[..end];
    (!val.is_empty()).then(|| val.to_string())
}

// --- Pricing (USD per token) ------------------------------------------------

/// Anthropic (input, output, cache-write, cache-read) per-token USD.
fn rates_claude(model: &str) -> (f64, f64, f64, f64) {
    let m = model.to_lowercase();
    let pm = |i: f64, o: f64, cw: f64, cr: f64| (i / 1e6, o / 1e6, cw / 1e6, cr / 1e6);
    if m.contains("opus") {
        pm(15.0, 75.0, 18.75, 1.5)
    } else if m.contains("haiku") {
        pm(1.0, 5.0, 1.25, 0.10)
    } else {
        pm(3.0, 15.0, 3.75, 0.30)
    }
}

// --- Accumulator shared across providers ------------------------------------

#[derive(Default, Clone)]
struct Win {
    input: i64,
    output: i64,
    cache_read: i64,
    cache_creation: i64,
    cost: f64,
    messages: i64,
}

impl Win {
    fn add(&mut self, i: i64, o: i64, cr: i64, cc: i64, cost: f64) {
        self.input += i;
        self.output += o;
        self.cache_read += cr;
        self.cache_creation += cc;
        self.cost += cost;
        self.messages += 1;
    }
}

#[derive(Default)]
struct Acc {
    now: i64,
    session: Win,
    today: Win,
    week: Win,
    all: Win,
    models: HashMap<String, (i64, f64, i64)>,
    projects: HashMap<String, (i64, i64)>,
    sessions: HashSet<String>,
    web_search: i64,
    web_fetch: i64,
    last_active: Option<i64>,
    session_earliest: Option<i64>,
}

impl Acc {
    fn new() -> Self {
        Acc {
            now: now_secs(),
            ..Default::default()
        }
    }

    #[allow(clippy::too_many_arguments)]
    fn record(
        &mut self,
        ts: i64,
        model: &str,
        inp: i64,
        out: i64,
        cr: i64,
        cc: i64,
        cost: f64,
        cwd: Option<&str>,
        session: Option<&str>,
    ) {
        self.all.add(inp, out, cr, cc, cost);
        let age = self.now - ts;
        if (0..=SESSION_SECS).contains(&age) {
            self.session.add(inp, out, cr, cc, cost);
            self.session_earliest = Some(self.session_earliest.map_or(ts, |e| e.min(ts)));
        }
        if (0..=DAY_SECS).contains(&age) {
            self.today.add(inp, out, cr, cc, cost);
        }
        if (0..=WEEK_SECS).contains(&age) {
            self.week.add(inp, out, cr, cc, cost);
        }

        let e = self.models.entry(model.to_string()).or_default();
        e.0 += inp + out + cr + cc;
        e.1 += cost;
        e.2 += 1;

        if let Some(c) = cwd {
            let p = self.projects.entry(c.to_string()).or_default();
            p.0 += inp + out + cr + cc;
            p.1 += 1;
        }
        if let Some(s) = session {
            self.sessions.insert(s.to_string());
        }
        self.last_active = Some(self.last_active.map_or(ts, |l| l.max(ts)));
    }

    fn finish(self, id: &str, name: &str) -> ProviderUsage {
        let mk = |key: &str, label: &str, w: &Win, resets_at: Option<i64>| WindowStat {
            key: key.into(),
            label: label.into(),
            input: w.input,
            output: w.output,
            cache_read: w.cache_read,
            cache_creation: w.cache_creation,
            total: w.input + w.output + w.cache_read + w.cache_creation,
            cost: w.cost,
            messages: w.messages,
            resets_at,
        };
        let resets_at = self.session_earliest.map(|e| e + SESSION_SECS);

        let mut models: Vec<ModelStat> = self
            .models
            .into_iter()
            .map(|(model, (t, c, m))| ModelStat {
                model,
                total: t,
                cost: c,
                messages: m,
            })
            .collect();
        models.sort_by(|a, b| b.total.cmp(&a.total));

        let mut projects: Vec<ProjectStat> = self
            .projects
            .into_iter()
            .map(|(path, (t, m))| ProjectStat {
                path,
                total: t,
                messages: m,
            })
            .collect();
        projects.sort_by(|a, b| b.total.cmp(&a.total));
        projects.truncate(6);

        ProviderUsage {
            id: id.into(),
            name: name.into(),
            tracked: true,
            note: None,
            windows: vec![
                mk("session", "Session · 5h", &self.session, resets_at),
                mk("today", "Last 24h", &self.today, None),
                mk("week", "Last 7 days", &self.week, None),
                mk("all", "All time", &self.all, None),
            ],
            models,
            projects,
            web_search: self.web_search,
            web_fetch: self.web_fetch,
            sessions: self.sessions.len() as i64,
            last_active: self.last_active,
        }
    }
}

// --- Output model (camelCase to the frontend) -------------------------------

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct WindowStat {
    key: String,
    label: String,
    input: i64,
    output: i64,
    cache_read: i64,
    cache_creation: i64,
    total: i64,
    cost: f64,
    messages: i64,
    resets_at: Option<i64>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct ModelStat {
    model: String,
    total: i64,
    cost: f64,
    messages: i64,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct ProjectStat {
    path: String,
    total: i64,
    messages: i64,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct ProviderUsage {
    id: String,
    name: String,
    tracked: bool,
    note: Option<String>,
    windows: Vec<WindowStat>,
    models: Vec<ModelStat>,
    projects: Vec<ProjectStat>,
    web_search: i64,
    web_fetch: i64,
    sessions: i64,
    last_active: Option<i64>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct UsageReport {
    generated_at: i64,
    providers: Vec<ProviderUsage>,
}

fn untracked(id: &str, name: &str, note: &str) -> ProviderUsage {
    ProviderUsage {
        id: id.into(),
        name: name.into(),
        tracked: false,
        note: Some(note.into()),
        windows: vec![],
        models: vec![],
        projects: vec![],
        web_search: 0,
        web_fetch: 0,
        sessions: 0,
        last_active: None,
    }
}

/// Open a SQLite database read-only without disturbing the live file. Prefers a
/// read-only connection (sees WAL); falls back to `immutable` (main file only).
fn open_ro(path: &Path) -> Option<Connection> {
    if !path.exists() {
        return None;
    }
    let p = path.to_string_lossy();
    let flags = OpenFlags::SQLITE_OPEN_READ_ONLY | OpenFlags::SQLITE_OPEN_URI;
    Connection::open_with_flags(format!("file:{p}?mode=ro"), flags)
        .or_else(|_| Connection::open_with_flags(format!("file:{p}?immutable=1"), flags))
        .ok()
}

// --- Claude Code: ~/.claude/projects/**/*.jsonl -----------------------------

fn collect_jsonl(dir: &PathBuf, out: &mut Vec<PathBuf>) {
    if let Ok(rd) = fs::read_dir(dir) {
        for e in rd.flatten() {
            let p = e.path();
            if p.is_dir() {
                collect_jsonl(&p, out);
            } else if p.extension().and_then(|s| s.to_str()) == Some("jsonl") {
                out.push(p);
            }
        }
    }
}

fn claude_usage() -> ProviderUsage {
    let mut acc = Acc::new();
    let mut files = Vec::new();
    collect_jsonl(&home().join(".claude/projects"), &mut files);

    for f in &files {
        let file = match fs::File::open(f) {
            Ok(x) => x,
            Err(_) => continue,
        };
        for line in BufReader::new(file).lines().map_while(Result::ok) {
            if line.is_empty() {
                continue;
            }
            let v: Value = match serde_json::from_str(&line) {
                Ok(x) => x,
                Err(_) => continue,
            };
            if v.get("type").and_then(|t| t.as_str()) != Some("assistant") {
                continue;
            }
            let msg = match v.get("message") {
                Some(m) => m,
                None => continue,
            };
            let usage = match msg.get("usage") {
                Some(u) => u,
                None => continue,
            };
            let ts = match v
                .get("timestamp")
                .and_then(|t| t.as_str())
                .and_then(parse_ts)
            {
                Some(t) => t,
                None => continue,
            };

            let f = |k: &str| usage.get(k).and_then(|x| x.as_i64()).unwrap_or(0);
            let (inp, out, cr, cc) = (
                f("input_tokens"),
                f("output_tokens"),
                f("cache_read_input_tokens"),
                f("cache_creation_input_tokens"),
            );
            let model = msg
                .get("model")
                .and_then(|m| m.as_str())
                .unwrap_or("unknown");
            let (ri, ro, rcw, rcr) = rates_claude(model);
            let cost = inp as f64 * ri + out as f64 * ro + cc as f64 * rcw + cr as f64 * rcr;

            if let Some(stu) = usage.get("server_tool_use") {
                acc.web_search += stu
                    .get("web_search_requests")
                    .and_then(|x| x.as_i64())
                    .unwrap_or(0);
                acc.web_fetch += stu
                    .get("web_fetch_requests")
                    .and_then(|x| x.as_i64())
                    .unwrap_or(0);
            }

            acc.record(
                ts,
                model,
                inp,
                out,
                cr,
                cc,
                cost,
                v.get("cwd").and_then(|c| c.as_str()),
                v.get("sessionId").and_then(|s| s.as_str()),
            );
        }
    }

    acc.finish("claude", "Claude Code")
}

// --- Codex: per-turn token telemetry in ~/.codex/logs_2.sqlite --------------
// Codex logs each turn as a `codex_core::session::turn` tracing line carrying
// `total_usage_tokens=<n>` (that turn's total tokens processed) plus `model=`
// and `thread_id=` span fields. That's the per-turn figure we sum — directly
// comparable to Claude's per-message totals. Cost is metered by the ChatGPT
// plan, not per token, so we don't estimate a dollar figure for Codex.

fn codex_usage() -> ProviderUsage {
    let path = home().join(".codex/logs_2.sqlite");
    let conn = match open_ro(&path) {
        Some(c) => c,
        None => return untracked("codex", "Codex", "No local Codex log database found."),
    };

    let mut stmt = match conn.prepare(
        "SELECT ts, feedback_log_body FROM logs \
         WHERE feedback_log_body LIKE '%total_usage_tokens=%'",
    ) {
        Ok(s) => s,
        Err(e) => return untracked("codex", "Codex", &format!("Couldn't read Codex logs: {e}")),
    };

    let rows = match stmt.query_map([], |r| {
        Ok((r.get::<_, i64>(0)?, r.get::<_, String>(1)?))
    }) {
        Ok(r) => r,
        Err(e) => return untracked("codex", "Codex", &format!("Codex query failed: {e}")),
    };

    let mut acc = Acc::new();
    for (ts, body) in rows.flatten() {
        let tokens = kv_int(&body, "total_usage_tokens=").unwrap_or(0);
        if tokens <= 0 {
            continue;
        }
        let model = kv_str(&body, "model=").unwrap_or_else(|| "gpt".into());
        let thread = kv_str(&body, "thread_id=");
        acc.record(ts, &model, tokens, 0, 0, 0, 0.0, None, thread.as_deref());
    }

    let mut provider = acc.finish("codex", "Codex");
    provider.note = Some(
        "Per-turn token totals from Codex's local telemetry. Cost is metered by your ChatGPT plan, not per token."
            .into(),
    );
    provider
}

// --- OpenCode: per-session columns in opencode.db ---------------------------

fn opencode_usage() -> ProviderUsage {
    let path = home().join(".local/share/opencode/opencode.db");
    let conn = match open_ro(&path) {
        Some(c) => c,
        None => return untracked("opencode", "OpenCode", "No local OpenCode database found."),
    };
    let mut acc = Acc::new();

    let mut stmt = match conn.prepare(
        "SELECT time_updated, model, directory, id, \
         tokens_input, tokens_output, tokens_reasoning, tokens_cache_read, tokens_cache_write, cost \
         FROM session",
    ) {
        Ok(s) => s,
        Err(e) => {
            return untracked(
                "opencode",
                "OpenCode",
                &format!("Couldn't read OpenCode sessions: {e}"),
            )
        }
    };

    let rows = stmt.query_map([], |r| {
        Ok((
            r.get::<_, i64>(0)?,                 // time_updated (ms)
            r.get::<_, Option<String>>(1)?,      // model (json or plain)
            r.get::<_, Option<String>>(2)?,      // directory
            r.get::<_, String>(3)?,              // id
            r.get::<_, i64>(4)?,                 // input
            r.get::<_, i64>(5)?,                 // output
            r.get::<_, i64>(6)?,                 // reasoning
            r.get::<_, i64>(7)?,                 // cache_read
            r.get::<_, i64>(8)?,                 // cache_write
            r.get::<_, f64>(9)?,                 // cost
        ))
    });
    let rows = match rows {
        Ok(r) => r,
        Err(e) => return untracked("opencode", "OpenCode", &format!("OpenCode query failed: {e}")),
    };

    for row in rows.flatten() {
        let (t_ms, model_raw, dir, id, inp, out, reasoning, cr, cw, cost) = row;
        if inp + out + reasoning + cr + cw == 0 {
            continue;
        }
        // Timestamps are epoch milliseconds.
        let ts = if t_ms > 1_000_000_000_000 { t_ms / 1000 } else { t_ms };
        let model = match &model_raw {
            Some(s) if s.trim_start().starts_with('{') => serde_json::from_str::<Value>(s)
                .ok()
                .and_then(|v| v.get("id").and_then(|x| x.as_str()).map(str::to_string))
                .unwrap_or_else(|| "unknown".into()),
            Some(s) if !s.is_empty() => s.clone(),
            _ => "unknown".into(),
        };
        acc.record(
            ts,
            &model,
            inp,
            out + reasoning,
            cr,
            cw,
            cost,
            dir.as_deref(),
            Some(&id),
        );
    }

    acc.finish("opencode", "OpenCode")
}

#[tauri::command]
pub fn scan_usage() -> Result<UsageReport, String> {
    Ok(UsageReport {
        generated_at: now_secs(),
        providers: vec![claude_usage(), codex_usage(), opencode_usage()],
    })
}

// --- Claude plan limits (live, from Anthropic's OAuth usage endpoint) --------
// The same data Claude Code's "Your usage limits" panel shows: %-of-plan for the
// 5h session window and the weekly buckets, with authoritative reset times. Uses
// the OAuth token from the macOS Keychain (first read prompts once).

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct LimitBar {
    kind: String,
    label: String,
    group: String,
    percent: f64,
    severity: String,
    resets_at: Option<i64>,
    is_active: bool,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct ExtraUsage {
    enabled: bool,
    used: f64,
    limit: f64,
    currency: String,
    percent: f64,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ClaudeLimits {
    plan: Option<String>,
    bars: Vec<LimitBar>,
    extra: Option<ExtraUsage>,
}

fn title_case(s: &str) -> String {
    s.replace(['_', '-'], " ")
        .split_whitespace()
        .map(|w| {
            let mut c = w.chars();
            match c.next() {
                Some(f) => f.to_uppercase().collect::<String>() + c.as_str(),
                None => String::new(),
            }
        })
        .collect::<Vec<_>>()
        .join(" ")
}

/// Read the Claude OAuth access token (+ subscription type) from the macOS Keychain.
fn read_claude_creds() -> Result<(String, Option<String>), String> {
    let out = Command::new("security")
        .args(["find-generic-password", "-s", "Claude Code-credentials", "-w"])
        .output()
        .map_err(|e| format!("Keychain read failed: {e}"))?;
    if !out.status.success() {
        return Err("Couldn't read Claude credentials from the Keychain.".into());
    }
    let raw = String::from_utf8_lossy(&out.stdout);
    let v: Value =
        serde_json::from_str(raw.trim()).map_err(|_| "Unexpected credential format.".to_string())?;
    let oauth = v
        .get("claudeAiOauth")
        .ok_or("No Claude OAuth entry in the Keychain.")?;
    let token = oauth
        .get("accessToken")
        .and_then(|t| t.as_str())
        .ok_or("No access token found.")?
        .to_string();
    let sub = oauth
        .get("subscriptionType")
        .and_then(|s| s.as_str())
        .map(str::to_string);
    Ok((token, sub))
}

#[tauri::command]
pub fn claude_usage_limits() -> Result<ClaudeLimits, String> {
    fetch_claude_limits()
}

fn fetch_claude_limits() -> Result<ClaudeLimits, String> {
    let (token, sub) = read_claude_creds()?;

    let out = Command::new("curl")
        .args([
            "-s",
            "--max-time",
            "20",
            "-H",
            &format!("Authorization: Bearer {token}"),
            "-H",
            "anthropic-beta: oauth-2025-04-20",
            "-H",
            "anthropic-version: 2023-06-01",
            "https://api.anthropic.com/api/oauth/usage",
        ])
        .output()
        .map_err(|e| format!("Request failed: {e}"))?;

    let body = String::from_utf8_lossy(&out.stdout);
    let v: Value = serde_json::from_str(body.trim()).map_err(|_| {
        "Anthropic returned an unexpected response — your token may be expired (open Claude Code to refresh).".to_string()
    })?;
    if let Some(err) = v.get("error") {
        let msg = err
            .get("message")
            .and_then(|m| m.as_str())
            .unwrap_or("unknown error");
        return Err(format!("Anthropic: {msg}"));
    }

    let mut bars = Vec::new();
    if let Some(arr) = v.get("limits").and_then(|l| l.as_array()) {
        for l in arr {
            let kind = l.get("kind").and_then(|x| x.as_str()).unwrap_or("").to_string();
            let group = l.get("group").and_then(|x| x.as_str()).unwrap_or("").to_string();
            let percent = l.get("percent").and_then(|x| x.as_f64()).unwrap_or(0.0);
            let severity = l
                .get("severity")
                .and_then(|x| x.as_str())
                .unwrap_or("normal")
                .to_string();
            let resets_at = l
                .get("resets_at")
                .and_then(|x| x.as_str())
                .and_then(parse_ts);
            let is_active = l.get("is_active").and_then(|x| x.as_bool()).unwrap_or(false);
            let scope_model = l
                .get("scope")
                .and_then(|s| s.get("model"))
                .and_then(|m| m.get("display_name"))
                .and_then(|x| x.as_str());
            let label = match kind.as_str() {
                "session" => "Current session".to_string(),
                "weekly_all" => "Weekly · All models".to_string(),
                "weekly_scoped" => format!("Weekly · {}", scope_model.unwrap_or("Scoped")),
                _ => title_case(&kind),
            };
            bars.push(LimitBar {
                kind,
                label,
                group,
                percent,
                severity,
                resets_at,
                is_active,
            });
        }
    }
    if bars.is_empty() {
        return Err("No usage limits were returned.".into());
    }

    // Extra usage (pay-as-you-go credits) from the `spend` block.
    let extra = v.get("spend").map(|s| {
        let money = |key: &str| -> Option<f64> {
            let m = s.get(key)?;
            let minor = m.get("amount_minor")?.as_f64()?;
            let exp = m.get("exponent").and_then(|x| x.as_i64()).unwrap_or(2);
            Some(minor / 10f64.powi(exp as i32))
        };
        let currency = s
            .get("used")
            .and_then(|u| u.get("currency"))
            .and_then(|c| c.as_str())
            .unwrap_or("USD")
            .to_string();
        ExtraUsage {
            enabled: s.get("enabled").and_then(|x| x.as_bool()).unwrap_or(false),
            used: money("used").unwrap_or(0.0),
            limit: money("limit").unwrap_or(0.0),
            currency,
            percent: s.get("percent").and_then(|x| x.as_f64()).unwrap_or(0.0),
        }
    });

    Ok(ClaudeLimits {
        plan: sub.map(|s| title_case(&s)),
        bars,
        extra,
    })
}

// --- Native tray summaries --------------------------------------------------
// Compact, pre-formatted lines the macOS tray menu renders as (disabled) items.

fn fmt_tokens(n: i64) -> String {
    let f = n as f64;
    if f >= 1e9 {
        format!("{:.1}B", f / 1e9)
    } else if f >= 1e7 {
        format!("{:.0}M", f / 1e6)
    } else if f >= 1e6 {
        format!("{:.1}M", f / 1e6)
    } else if f >= 1e4 {
        format!("{:.0}K", f / 1e3)
    } else if f >= 1e3 {
        format!("{:.1}K", f / 1e3)
    } else {
        n.to_string()
    }
}

fn fmt_usd(n: f64) -> String {
    if n <= 0.0 {
        "$0".into()
    } else if n < 1000.0 {
        format!("${n:.2}")
    } else {
        format!("${n:.0}")
    }
}

fn fmt_reset(resets_at: Option<i64>, now: i64) -> String {
    let Some(r) = resets_at else {
        return "—".into();
    };
    let s = r - now;
    if s <= 0 {
        return "resets now".into();
    }
    let h = s / 3600;
    let d = h / 24;
    if d >= 1 {
        format!("resets {}d {}h", d, h % 24)
    } else if h >= 1 {
        format!("resets {}h {}m", h, (s % 3600) / 60)
    } else {
        format!("resets {}m", s / 60)
    }
}

/// One agent's block for the tray menu: a title, a right-aligned headline
/// (plan / model) and a set of pre-formatted detail lines.
pub struct AgentSummary {
    pub name: String,
    pub headline: String,
    pub lines: Vec<String>,
}

fn window_of<'a>(p: &'a ProviderUsage, key: &str) -> Option<&'a WindowStat> {
    p.windows.iter().find(|w| w.key == key)
}

pub fn agent_summaries() -> Vec<AgentSummary> {
    let now = now_secs();
    let mut out = Vec::new();

    // Claude — plan limits (live) + local totals.
    let cu = claude_usage();
    let mut lines = Vec::new();
    let mut headline = String::new();
    match fetch_claude_limits() {
        Ok(lim) => {
            headline = lim.plan.clone().unwrap_or_default();
            for b in &lim.bars {
                let short = match b.kind.as_str() {
                    "session" => "Session",
                    "weekly_all" => "Weekly",
                    "weekly_scoped" => "Fable",
                    _ => b.label.as_str(),
                };
                lines.push(format!(
                    "{short}   {}% used · {}",
                    b.percent.round() as i64,
                    fmt_reset(b.resets_at, now)
                ));
            }
            if let Some(x) = &lim.extra {
                if x.enabled {
                    lines.push(format!(
                        "Extra usage   {} / {} {}",
                        format!("{:.2}", x.used),
                        format!("{:.0}", x.limit),
                        x.currency
                    ));
                }
            }
        }
        Err(_) => lines.push("Plan limits unavailable (open Claude Code)".into()),
    }
    if let Some(t) = window_of(&cu, "today") {
        lines.push(format!("Today   {} · {}", fmt_tokens(t.total), fmt_usd(t.cost)));
    }
    if let Some(a) = window_of(&cu, "all") {
        lines.push(format!("All time   {} · {}", fmt_tokens(a.total), fmt_usd(a.cost)));
    }
    let top = cu.models.first().map(|m| m.model.clone()).unwrap_or_default();
    lines.push(format!("{} sessions · {top}", cu.sessions));
    out.push(AgentSummary {
        name: cu.name.clone(),
        headline,
        lines,
    });

    // Codex + OpenCode — local totals (plan metered elsewhere).
    for pu in [codex_usage(), opencode_usage()] {
        let mut lines = Vec::new();
        if pu.tracked {
            if let Some(t) = window_of(&pu, "today") {
                lines.push(format!("Today   {}", fmt_tokens(t.total)));
            }
            if let Some(a) = window_of(&pu, "all") {
                lines.push(format!("All time   {}", fmt_tokens(a.total)));
            }
            lines.push(format!("{} sessions", pu.sessions));
        } else {
            lines.push(pu.note.clone().unwrap_or_else(|| "Not tracked".into()));
        }
        let headline = pu.models.first().map(|m| m.model.clone()).unwrap_or_default();
        out.push(AgentSummary {
            name: pu.name.clone(),
            headline,
            lines,
        });
    }

    out
}
