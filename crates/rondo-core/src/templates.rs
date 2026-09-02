//! Bundled service templates for quick subscription entry.

use std::sync::OnceLock;

use serde::{Deserialize, Serialize};

/// The template id reserved for "not on this list".
///
/// Picking custom is a choice the user made, not the absence of one, so it
/// gets a name rather than being inferred from an empty provider. No
/// bundled template may claim it, which a test enforces.
pub const CUSTOM_TEMPLATE_ID: &str = "custom";

/// A well-known service the user can pick instead of typing details.
///
/// Templates only prefill the form; a subscription keeps its own copy of
/// every field and never depends on the template afterwards.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ServiceTemplate {
    /// Stable template id, referenced by `Subscription::template_id`.
    ///
    /// It also names the artwork a frontend draws for the service. There is
    /// no second key for that: every bundled service would repeat its own
    /// id, and a frontend that carries no image under this name falls back
    /// to the service's initials.
    pub id: String,
    /// Display name of the service.
    pub name: String,
    /// Other names people type for this service.
    ///
    /// Only for names sharing nothing with `name`: "B站" for Bilibili, and
    /// "Office" for Microsoft 365. Anything the search already reaches by
    /// substring - "网易云" inside "网易云音乐" - would be dead weight here.
    #[serde(default)]
    pub aliases: Vec<String>,
    /// Brand-ish accent color as `#RRGGBB`.
    pub color: String,
    /// Which built-in category a subscription from this template starts in.
    ///
    /// A semantic key, never a symbol name or a hex colour: the core is
    /// shared, and an Android frontend can do something with `"video"`
    /// while an SF Symbol name would arrive as a string it cannot use.
    pub default_category: String,
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

    /// The categories a bundled template may start a subscription in.
    ///
    /// Kept here rather than in the data so a typo in `services.json` fails
    /// the build instead of seeding a category nobody meant to create.
    const KNOWN_CATEGORIES: [&str; 8] = [
        "video", "music", "storage", "tools", "dev", "ai", "games", "reading",
    ];

    #[test]
    fn bundled_templates_use_known_categories() {
        for t in service_templates() {
            assert!(
                KNOWN_CATEGORIES.contains(&t.default_category.as_str()),
                "unknown category {:?} on template {}",
                t.default_category,
                t.id
            );
        }
    }

    #[test]
    fn no_bundled_template_claims_the_custom_id() {
        assert!(
            service_templates()
                .iter()
                .all(|t| t.id != CUSTOM_TEMPLATE_ID),
            "a bundled service took the id reserved for the custom choice"
        );
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
