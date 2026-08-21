//! Bundled service templates for quick subscription entry.

use std::sync::OnceLock;

use serde::{Deserialize, Serialize};

/// A well-known service the user can pick instead of typing details.
///
/// Templates only prefill the form; a subscription keeps its own copy of
/// every field and never depends on the template afterwards.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ServiceTemplate {
    /// Stable template id, referenced by `Subscription::template_id`.
    pub id: String,
    /// Display name of the service.
    pub name: String,
    /// Brand-ish accent color as `#RRGGBB`.
    pub color: String,
    /// Service home page, if one is worth linking.
    pub url: Option<String>,
}

/// Template catalogue compiled into the binary; parsed once on first use.
///
/// Panics only if the bundled JSON is invalid, which the test suite rules
/// out before release.
pub fn service_templates() -> &'static [ServiceTemplate] {
    static TEMPLATES: OnceLock<Vec<ServiceTemplate>> = OnceLock::new();
    TEMPLATES.get_or_init(|| {
        serde_json::from_str(include_str!("../templates/services.json"))
            .expect("bundled services.json must be valid")
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashSet;

    #[test]
    fn bundled_templates_parse_and_have_unique_ids() {
        let templates = service_templates();
        assert!(!templates.is_empty());
        let ids: HashSet<&str> = templates.iter().map(|t| t.id.as_str()).collect();
        assert_eq!(ids.len(), templates.len(), "template ids must be unique");
    }

    #[test]
    fn bundled_template_colors_are_rrggbb() {
        for t in service_templates() {
            assert!(
                t.color.len() == 7
                    && t.color.starts_with('#')
                    && t.color[1..].bytes().all(|b| b.is_ascii_hexdigit()),
                "bad color {:?} on template {}",
                t.color,
                t.id
            );
        }
    }
}
