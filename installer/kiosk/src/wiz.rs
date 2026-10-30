//! Wiz's pictures for ui/wiz.slint, each drawn once at the size it is shown.
//!
//! `assets/wiz` holds the poses the installer shows, cut into the parts it
//! moves; `scripts/export-wiz` writes them from the desktop's rig. Slint's
//! software renderer rasterises an SVG image again on every repaint that
//! touches it, and Wiz moves over his larger pictures. So each picture is
//! rasterised here, once per size, at exactly its physical size, and the screen
//! only places, fades and swaps them: a repaint then copies pixels.

use std::cell::RefCell;
use std::collections::HashMap;

use slint::Image;

use crate::WizArt;

macro_rules! art {
    ($($name:literal),* $(,)?) => {
        &[$(($name, include_str!(concat!("../assets/wiz/", $name, ".svg")))),*]
    };
}

/// Every file in assets/wiz.
const ART: &[(&str, &str)] = art![
    "thinking-body", "thinking-eyes", "thinking-eyes-half", "thinking-eyes-shut", "thinking-hat",
    "thinking-rune0", "thinking-rune1", "thinking-rune2", "thinking-rune3",
    "working-body", "working-eyes", "working-eyes-half", "working-eyes-shut", "working-hat",
    "working-glow", "working-core", "working-mote", "working-ring0", "working-ring1", "working-ring2",
    "needs-input-body", "needs-input-eyes", "needs-input-eyes-half", "needs-input-eyes-shut", "needs-input-hat",
    "needs-input-pip", "needs-input-ring",
    "happy-body", "happy-eyes", "happy-hat",
    "happy-sparkle0", "happy-sparkle1", "happy-sparkle2", "happy-sparkle3", "happy-sparkle4",
    "sorry-body", "sorry-eyes", "sorry-eyes-half", "sorry-eyes-shut", "sorry-hat",
];

thread_local! {
    static DRAWN: RefCell<HashMap<(&'static str, u32, u32), Image>> = RefCell::new(HashMap::new());
}

/// An exported picture's viewBox: where it sits in the rig, in rig units.
fn view_box(svg: &str) -> Option<[f32; 4]> {
    let start = svg.find("viewBox=\"")? + 9;
    let end = start + svg[start..].find('"')?;
    let values: Vec<f32> = svg[start..end].split_whitespace().filter_map(|v| v.parse().ok()).collect();
    values.try_into().ok()
}

/// The picture at exactly `width` × `height` pixels, its viewBox filling them.
fn rasterise(svg: &str, width: u32, height: u32) -> Image {
    let Some(open) = svg.find('>') else { return Image::default() };
    let Some([x, y, w, h]) = view_box(svg) else { return Image::default() };
    let sized = format!(
        "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"{width}\" height=\"{height}\" viewBox=\"{x} {y} {w} {h}\" preserveAspectRatio=\"none\">{}",
        &svg[open + 1..]
    );
    Image::load_from_svg_data(sized.as_bytes())
        .ok()
        .and_then(|image| image.to_rgba8_premultiplied())
        .map(Image::from_rgba8_premultiplied)
        .unwrap_or_default()
}

/// `name` at `ppu` physical pixels per rig unit, scaled by `size` about its
/// centre, and that centre in physical pixels from the rig's origin.
pub fn art(name: &str, ppu: f32, size: f32) -> WizArt {
    let Some(&(name, svg)) = ART.iter().find(|(n, _)| *n == name) else {
        eprintln!("cybexos-installer: no Wiz picture {name}");
        return WizArt::default();
    };
    let Some([x, y, w, h]) = view_box(svg) else { return WizArt::default() };
    let width = (w * ppu * size).round().max(0.0) as u32;
    let height = (h * ppu * size).round().max(0.0) as u32;
    let image = if width == 0 || height == 0 {
        Image::default()
    } else {
        DRAWN.with(|drawn| drawn.borrow_mut().entry((name, width, height)).or_insert_with(|| rasterise(svg, width, height)).clone())
    };
    WizArt { image, x: (x + w / 2.0) * ppu, y: (y + h / 2.0) * ppu }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_exported_picture_is_embedded_and_nothing_else() {
        let dir = concat!(env!("CARGO_MANIFEST_DIR"), "/assets/wiz");
        let mut files: Vec<String> = std::fs::read_dir(dir)
            .unwrap()
            .map(|entry| entry.unwrap().file_name().into_string().unwrap())
            .filter_map(|name| name.strip_suffix(".svg").map(String::from))
            .collect();
        files.sort();
        let mut names: Vec<String> = ART.iter().map(|(name, _)| name.to_string()).collect();
        names.sort();
        assert_eq!(files, names, "assets/wiz changed: update ART after scripts/export-wiz");
    }

    #[test]
    fn each_pose_has_its_parts_and_a_blink_shares_the_eyes_box() {
        for pose in ["thinking", "working", "needs-input", "happy", "sorry"] {
            for part in ["body", "eyes", "hat"] {
                assert!(ART.iter().any(|(name, _)| *name == format!("{pose}-{part}")), "{pose}-{part}");
            }
            if pose != "happy" {
                let eyes = |suffix: &str| {
                    let name = format!("{pose}-eyes{suffix}");
                    view_box(ART.iter().find(|(n, _)| *n == name).unwrap().1).unwrap()
                };
                assert_eq!(eyes(""), eyes("-half"));
                assert_eq!(eyes(""), eyes("-shut"));
            }
        }
    }

    #[test]
    fn pictures_are_drawn_at_their_physical_size_around_their_place() {
        let body = art("happy-body", 1.0, 1.0);
        let [x, y, w, h] = view_box(ART.iter().find(|(n, _)| *n == "happy-body").unwrap().1).unwrap();
        assert_eq!((body.image.size().width, body.image.size().height), (w as u32, h as u32));
        assert_eq!((body.x, body.y), (x + w / 2.0, y + h / 2.0));
        // Twice the pixels, the same place in the rig.
        let sharp = art("happy-body", 2.0, 1.0);
        assert_eq!(sharp.image.size().width, 2 * w as u32);
        assert_eq!((sharp.x, sharp.y), (2.0 * body.x, 2.0 * body.y));
        // A scaled part keeps its centre.
        let pulse = art("needs-input-ring", 1.5, 1.6);
        let still = art("needs-input-ring", 1.5, 1.0);
        assert!(pulse.image.size().width > still.image.size().width);
        assert_eq!((pulse.x, pulse.y), (still.x, still.y));
        // Something is drawn: the cloak's colour beside its seam.
        let pixels = body.image.to_rgba8().unwrap();
        let cloak = pixels.as_slice()[(h as usize / 2) * w as usize + w as usize / 2 - 8];
        assert_eq!((cloak.r, cloak.g, cloak.b, cloak.a), (0x23, 0x26, 0x2c, 255));
        assert_eq!(art("nothing", 1.0, 1.0).image.size().width, 0);
    }
}
