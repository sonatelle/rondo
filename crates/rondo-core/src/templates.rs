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

/// How closely a template answered a query. Ordered worst to best, so the
/// derived `Ord` sorts the good matches last and a reversed sort puts them
/// first.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
enum Match {
    /// An alias carried the match rather than the name on screen.
    Alias,
    /// The name contains the query somewhere inside it.
    Contained,
    /// The name starts with the query, which is what typing usually means.
    Prefix,
}

/// Folds away the differences people do not intend when they type: case,
/// spaces, and the punctuation that separates words in a brand name.
///
/// It deliberately leaves letters and digits from every script alone, so
/// Chinese names match on their own characters rather than being
/// transliterated into something approximate.
fn normalized(text: &str) -> String {
    text.chars()
        .filter(|c| c.is_alphanumeric())
        .flat_map(char::to_lowercase)
        .collect()
}

/// Bundled services matching `query`, best match first.
///
/// Matching is by substring rather than by edit distance, because the
/// mistake worth forgiving here is an abbreviation - "prime" for Amazon
/// Prime - and not a typo. A nickname sharing no characters with the name,
/// "B站" for Bilibili, cannot be reached by any amount of fuzziness and is
/// carried by `aliases` instead.
///
/// An empty query returns the whole catalogue in its bundled order, which
/// is what a picker shows before anyone types.
pub fn search_service_templates(query: &str) -> Vec<&'static ServiceTemplate> {
    let needle = normalized(query);
    if needle.is_empty() {
        return service_templates().iter().collect();
    }

    let mut hits: Vec<(Match, usize, &'static ServiceTemplate)> = service_templates()
        .iter()
        .enumerate()
        .filter_map(|(position, template)| {
            rank(template, &needle).map(|how| (how, position, template))
        })
        .collect();

    // Best match first; ties keep the catalogue's own order, so a list
    // rearranges as little as possible while someone is still typing.
    hits.sort_by(|a, b| b.0.cmp(&a.0).then(a.1.cmp(&b.1)));
    hits.into_iter().map(|(_, _, template)| template).collect()
}

/// How well one template answers an already-normalized query.
fn rank(template: &ServiceTemplate, needle: &str) -> Option<Match> {
    let name = normalized(&template.name);
    if name.starts_with(needle) {
        return Some(Match::Prefix);
    }
    if name.contains(needle) {
        return Some(Match::Contained);
    }
    template
        .aliases
        .iter()
        .any(|alias| normalized(alias).contains(needle))
        .then_some(Match::Alias)
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

    fn ids_for(query: &str) -> Vec<&'static str> {
        search_service_templates(query)
            .into_iter()
            .map(|t| t.id.as_str())
            .collect()
    }

    #[test]
    fn an_empty_query_returns_the_whole_catalogue() {
        assert_eq!(
            search_service_templates("").len(),
            service_templates().len()
        );
        assert_eq!(
            search_service_templates("   ").len(),
            service_templates().len()
        );
    }

    #[test]
    fn an_abbreviation_inside_a_name_matches() {
        assert_eq!(ids_for("prime"), ["amazon-prime"]);
        assert_eq!(ids_for("奇艺"), ["iqiyi"]);
    }

    #[test]
    fn case_spaces_and_punctuation_are_forgiven() {
        assert_eq!(ids_for("1 PASS.word"), ["1password"]);
        assert_eq!(ids_for("disney +"), ["disney-plus"]);
    }

    /// A nickname sharing no characters with the name is exactly what the
    /// alias list is for; no amount of fuzziness reaches it.
    #[test]
    fn a_nickname_is_reached_only_through_its_alias() {
        assert_eq!(ids_for("B站"), ["bilibili"]);
        assert_eq!(ids_for("office"), ["microsoft-365"]);
        assert_eq!(ids_for("电报"), ["telegram-premium"]);
    }

    /// A prefix is what typing usually means, so it comes first; a name
    /// beats an alias; and equal matches keep the catalogue's own order so
    /// the list stays still while someone is still typing.
    #[test]
    fn matches_are_ordered_prefix_then_name_then_alias() {
        assert_eq!(
            ids_for("ne"),
            [
                "netflix",     // name starts with it
                "apple-one",   // the rest only contain it, in
                "disney-plus", // catalogue order: "disney" holds an
                "google-one",  // "ne" as surely as "apple one" does
                "nintendo-online",
                "netease-music", // only its alias contains it
            ]
        );
    }

    #[test]
    fn a_query_nothing_answers_returns_nothing() {
        assert!(search_service_templates("zzzz").is_empty());
    }

    /// Aliases are maintenance, so each one has to earn its place: an alias
    /// the search already reaches through the name is dead weight.
    #[test]
    fn no_alias_repeats_what_the_name_already_matches() {
        for t in service_templates() {
            let name = normalized(&t.name);
            for alias in &t.aliases {
                let alias = normalized(alias);
                assert!(
                    !name.contains(&alias),
                    "alias {:?} on {} is already inside its own name",
                    alias,
                    t.id
                );
            }
        }
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
