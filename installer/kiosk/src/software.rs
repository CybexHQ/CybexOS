//! The Software step's wording: card tiles and tags, the footer note, the
//! Customize rows and the review summary. The daemon decides what installs
//! (`State::software`); this only describes it.

use crate::protocol::{Draft, Profile, Software, SoftwareSummary};

/// Software that is always installed. Proprietary ones need that switch.
const ALWAYS: [(&str, bool); 14] = [
    ("Brave", true),
    ("Firefox", false),
    ("Files", false),
    ("Text Editor", false),
    ("Documents", false),
    ("Images", false),
    ("mpv", false),
    ("Calculator", false),
    ("LocalSend", false),
    ("1Password", true),
    ("Claude Code", true),
    ("Codex", false),
    ("Wiz assistant", false),
    ("terminal tools", false),
];

/// Tabler icons for the system feature switches.
pub fn feature_icon(key: &str) -> &'static str {
    match key {
        "docker" => "brand-docker",
        "podman" => "box",
        "tailscale" => "topology-star-3",
        "localNetworkServices" => "radar-2",
        "connectedWidgets" => "layout-dashboard",
        "proprietary" => "license",
        _ => "",
    }
}

pub fn always_included(proprietary: bool) -> String {
    ALWAYS.iter().filter(|(_, unfree)| proprietary || !unfree).map(|(name, _)| *name).collect::<Vec<_>>().join(" · ")
}

/// A two-character badge for software without an icon: "T3 Code" → "T3",
/// "Claude Code" → "CC", "Docker" → "DO".
pub fn monogram(name: &str) -> String {
    let words: Vec<&str> = name.split(|c: char| c.is_whitespace() || c == ',').filter(|w| !w.is_empty()).collect();
    let first = words.first().copied().unwrap_or("");
    let text: String = if first.chars().count() <= 3 && first.chars().any(|c| c.is_ascii_digit()) {
        first.into()
    } else if words.len() > 1 {
        words.iter().take(2).filter_map(|w| w.chars().next()).collect()
    } else {
        first.chars().take(2).collect()
    };
    text.to_uppercase()
}

/// A card's tiles, at most five: what the profile brings (includes) and its
/// apps, alternately, leading with the first include.
pub fn tiles<'a>(profile: &'a Profile, software: &'a Software) -> Vec<Tile<'a>> {
    let mut includes = profile.includes.iter().map(|item| Tile {
        name: &item.name,
        icon: &item.icon,
        mono: item.icon.is_empty(),
    });
    let mut apps = profile.apps.iter().filter_map(|id| software.apps.get(id)).map(|app| Tile {
        name: &app.name,
        icon: &app.icon,
        mono: app.icon.is_empty(),
    });
    let mut result = Vec::new();
    loop {
        let before = result.len();
        result.extend(includes.next());
        result.extend(apps.next());
        if result.len() == before || result.len() >= 5 {
            break;
        }
    }
    result.truncate(5);
    result
}

#[derive(Debug, PartialEq)]
pub struct Tile<'a> {
    pub name: &'a str,
    pub icon: &'a str,
    pub mono: bool,
}

pub fn gigabytes(bytes: u64) -> String {
    if bytes == 0 {
        "no download".into()
    } else if bytes < 50_000_000 {
        "< 0.1 GB".into()
    } else {
        format!("≈ {:.1} GB", bytes as f64 / 1e9)
    }
}

/// The size tag and its tone: on the medium, the download, or needs internet.
pub fn size_tag(profile: &Profile, online: bool) -> (String, &'static str) {
    if profile.on_medium {
        ("On this USB stick".into(), "")
    } else if !online {
        ("Needs internet".into(), "amber")
    } else {
        (gigabytes(profile.download_bytes), "")
    }
}

pub fn vendor_tag(profile: &Profile, online: bool, proprietary: bool) -> String {
    match profile.vendor {
        _ if !online && !profile.on_medium => String::new(),
        0 => "All open source".into(),
        _ if !proprietary => "Vendor apps off".into(),
        n => format!("{n} from vendor"),
    }
}

fn names(profiles: &[&Profile], full: bool) -> String {
    profiles.iter().map(|p| if full { p.name.as_str() } else { p.short.as_str() }).collect::<Vec<_>>().join(", ")
}

/// The footer note: a bold part and the rest, plus a Tabler icon name.
pub fn footer(software: &Software, summary: &SoftwareSummary) -> (String, String, &'static str) {
    let chosen: Vec<&Profile> = software.profiles.iter().filter(|p| summary.profiles.contains(&p.id)).collect();
    if !summary.online {
        let carried: Vec<&Profile> = software.profiles.iter().filter(|p| p.on_medium).collect();
        let rest = if carried.is_empty() {
            "Connect to the internet to add apps.".to_string()
        } else {
            format!("{} {} on this USB stick. Connect to the internet to add the others.", names(&carried, true),
                if carried.len() == 1 { "is" } else { "are" })
        };
        return ("Offline:".into(), rest, "wifi-off");
    }
    if chosen.is_empty() {
        return ("Essentials only.".into(), "You can add apps any time in Software.".into(), "cloud-download");
    }
    if chosen.iter().all(|p| p.on_medium) {
        let verb = if chosen.len() == 1 { "is" } else { "are" };
        return (names(&chosen, false), format!("{verb} on this USB stick: no download needed"), "usb");
    }
    let size = gigabytes(summary.download_bytes);
    let size = if summary.download_bytes == 0 { "no prebuilt download".to_string() } else { format!("downloads {size}") };
    (names(&chosen, false), format!("· {size} of prebuilt apps during installation"), "cloud-download")
}

/// The review page's Software row: its value and detail.
pub fn review(software: &Software, summary: &SoftwareSummary, proprietary: bool) -> (String, String) {
    let chosen: Vec<&Profile> = software.profiles.iter().filter(|p| summary.profiles.contains(&p.id)).collect();
    if chosen.is_empty() {
        return ("Essentials only".into(), "add apps any time in Software".into());
    }
    let mut value = names(&chosen, false);
    let mut detail = if chosen.iter().all(|p| p.on_medium) {
        "on this USB stick · no download".to_string()
    } else {
        format!("{} download", gigabytes(summary.download_bytes))
    };
    if summary.apps_off > 0 {
        let off = format!("{} app{} off", summary.apps_off, if summary.apps_off == 1 { "" } else { "s" });
        // The row's value has room for about 36 characters.
        if value.chars().count() + off.len() + 3 <= 36 {
            value = format!("{value} · {off}");
        } else {
            detail = format!("{off} · {detail}");
        }
    }
    if summary.vendor > 0 {
        detail += &format!(" · {} from vendor", summary.vendor);
    }
    if !proprietary {
        detail += " · no proprietary apps";
    }
    (value, detail)
}

/// The profiles the Customize sheet lists: chosen and installable now.
pub fn customized<'a>(software: &'a Software, draft: &Draft, online: bool) -> Vec<&'a Profile> {
    software.profiles.iter().filter(|p| draft.profiles.contains(&p.id) && (p.on_medium || online)).collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::protocol::{Included, SoftwareApp};

    fn catalogue() -> Software {
        let app = |name: &str, free: bool, icon: &str| SoftwareApp { name: name.into(), free, icon: icon.into(), download_bytes: 1 };
        let include = |name: &str, icon: &str| Included { name: name.into(), icon: icon.into() };
        let mut software = Software::default();
        software.apps.insert("zed".into(), app("Zed", true, "/icons/zed.png"));
        software.apps.insert("dbeaver".into(), app("DBeaver Community", true, "/icons/dbeaver.png"));
        software.apps.insert("gimp".into(), app("GIMP", true, ""));
        software.profiles = vec![
            Profile {
                id: "development".into(), name: "Software Development".into(), short: "Development".into(),
                on_medium: true,
                includes: vec![include("T3 Code", ""), include("Claude Code", ""), include("Codex", ""), include("Docker", "/icons/docker.png")],
                apps: vec!["zed".into(), "dbeaver".into()], ..Profile::default()
            },
            Profile {
                id: "graphics".into(), name: "Graphics & Design".into(), short: "Graphics".into(),
                apps: vec!["gimp".into()], download_bytes: 1_577_781_783, ..Profile::default()
            },
        ];
        software
    }

    #[test]
    fn tiles_lead_with_what_the_profile_brings_then_alternate() {
        let software = catalogue();
        let names: Vec<&str> = tiles(&software.profiles[0], &software).iter().map(|t| t.name).collect();
        assert_eq!(names, ["T3 Code", "Zed", "Claude Code", "DBeaver Community", "Codex"]);
        let docker = Profile { includes: software.profiles[0].includes[3..].to_vec(), ..Profile::default() };
        assert_eq!(tiles(&docker, &software), [Tile { name: "Docker", icon: "/icons/docker.png", mono: false }],
                   "what a profile includes shows its icon too");
        let gimp = tiles(&software.profiles[1], &software);
        assert_eq!(gimp, [Tile { name: "GIMP", icon: "", mono: true }], "an app without an icon gets a monogram");
    }

    #[test]
    fn monograms_read_like_the_name() {
        assert_eq!(monogram("T3 Code"), "T3");
        assert_eq!(monogram("Claude Code"), "CC");
        assert_eq!(monogram("Docker"), "DO");
        assert_eq!(monogram("Node.js, Bun, Rust"), "NB");
        assert_eq!(monogram(""), "");
    }

    #[test]
    fn tags_and_notes_follow_the_medium_and_the_network() {
        let software = catalogue();
        let (development, graphics) = (&software.profiles[0], &software.profiles[1]);
        assert_eq!(size_tag(development, false), ("On this USB stick".into(), ""));
        assert_eq!(size_tag(graphics, true), ("≈ 1.6 GB".into(), ""));
        assert_eq!(size_tag(graphics, false), ("Needs internet".into(), "amber"));
        assert_eq!(vendor_tag(graphics, true, true), "All open source");
        let summary = |profiles: &[&str], bytes, online| SoftwareSummary {
            profiles: profiles.iter().map(|p| p.to_string()).collect(), download_bytes: bytes, online, ..SoftwareSummary::default()
        };
        assert_eq!(footer(&software, &summary(&["development"], 0, true)),
                   ("Development".into(), "is on this USB stick: no download needed".into(), "usb"));
        assert_eq!(footer(&software, &summary(&["development", "graphics"], 1_577_781_783, true)),
                   ("Development, Graphics".into(), "· downloads ≈ 1.6 GB of prebuilt apps during installation".into(), "cloud-download"));
        assert_eq!(footer(&software, &summary(&[], 0, true)).0, "Essentials only.");
        assert_eq!(footer(&software, &summary(&["development"], 0, false)),
                   ("Offline:".into(), "Software Development is on this USB stick. Connect to the internet to add the others.".into(), "wifi-off"));
        let mut two_off = summary(&["development", "graphics"], 1_577_781_783, true);
        two_off.apps_off = 2;
        assert_eq!(review(&software, &two_off, true), ("Development, Graphics · 2 apps off".into(), "≈ 1.6 GB download".into()));
        let mut long = software.clone();
        long.profiles[1].short = "Graphics, Audio & Video".into();
        assert_eq!(review(&long, &two_off, false),
                   ("Development, Graphics, Audio & Video".into(), "2 apps off · ≈ 1.6 GB download · no proprietary apps".into()));
        assert_eq!(review(&software, &summary(&[], 0, true), false).0, "Essentials only");
    }

    #[test]
    fn proprietary_applications_decide_what_is_always_included() {
        assert!(always_included(true).starts_with("Brave · Firefox"));
        assert!(always_included(true).contains("Claude Code · Codex"));
        let free = always_included(false);
        assert!(!free.contains("Brave") && !free.contains("1Password") && !free.contains("Claude Code"));
        assert!(free.contains("Codex · Wiz assistant"));
    }
}
