//! BetterDesk-specific HTTP helpers for the official desktop client.
//!
//! Extension point for branding / health probes and future panel Generator
//! + enrollment features. Base URL comes from configured `api-server`.

use hbb_common::{bail, config, log, ResultType};
use serde_json::Value;

use super::create_http_client_async_with_url;

/// Product marker sent in sysinfo / future API bodies.
pub const CLIENT_PRODUCT: &str = config::BETTERDESK_CLIENT_PRODUCT;

fn api_base() -> String {
    let api = crate::get_api_server(
        config::Config::get_option("api-server"),
        config::Config::get_option("custom-rendezvous-server"),
    );
    api.trim_end_matches('/').to_owned()
}

/// GET `{api}/api/health` — returns Ok(json) when API is reachable.
pub async fn fetch_health() -> ResultType<Value> {
    let base = api_base();
    if base.is_empty() {
        bail!("BetterDesk API server is not configured");
    }
    let url = format!("{base}/api/health");
    let client = create_http_client_async_with_url(&url).await;
    let resp = client.get(&url).send().await?;
    let status = resp.status();
    let text = resp.text().await.unwrap_or_default();
    if !status.is_success() {
        bail!("health check failed: HTTP {status} {text}");
    }
    match serde_json::from_str(&text) {
        Ok(v) => Ok(v),
        Err(_) => Ok(Value::String(text)),
    }
}

/// GET `{api}/api/branding` — optional white-label payload from the panel.
pub async fn fetch_branding() -> ResultType<Value> {
    let base = api_base();
    if base.is_empty() {
        bail!("BetterDesk API server is not configured");
    }
    let url = format!("{base}/api/branding");
    let client = create_http_client_async_with_url(&url).await;
    let resp = client.get(&url).send().await?;
    let status = resp.status();
    let text = resp.text().await.unwrap_or_default();
    if !status.is_success() {
        bail!("branding fetch failed: HTTP {status}");
    }
    Ok(serde_json::from_str(&text).unwrap_or(Value::Null))
}

/// GET `{api}/api/server-key` — public key helpers for Network auto-fill UX.
pub async fn fetch_server_key() -> ResultType<String> {
    let base = api_base();
    if base.is_empty() {
        bail!("BetterDesk API server is not configured");
    }
    let url = format!("{base}/api/server-key");
    let client = create_http_client_async_with_url(&url).await;
    let resp = client.get(&url).send().await?;
    let status = resp.status();
    let text = resp.text().await.unwrap_or_default();
    if !status.is_success() {
        bail!("server-key fetch failed: HTTP {status}");
    }
    if let Ok(v) = serde_json::from_str::<Value>(&text) {
        if let Some(k) = v.get("key").and_then(|x| x.as_str()) {
            return Ok(k.to_owned());
        }
    }
    Ok(text.trim().to_owned())
}

/// Log a one-line identity banner at startup (no network).
pub fn log_client_identity() {
    log::info!(
        "BetterDesk official client product={} app={}",
        CLIENT_PRODUCT,
        crate::get_app_name()
    );
}
