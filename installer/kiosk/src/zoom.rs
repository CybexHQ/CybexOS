//! Display zoom: the 1280×800 design canvas fitted to the panel.
//!
//! The same rule as the Tiaris kiosk, applied to the output the screen draws
//! on: 1920×1200 → 1.5, 2880×1800 → 2.25, 3840×2160 → 2.7, never below 0.8.
//! Other connected outputs never count: a larger external monitor beside a
//! laptop panel would zoom the canvas past the panel's edges.

pub const CANVAS: (f32, f32) = (1280.0, 800.0);

/// `CYBEXOS_INSTALLER_RESOLUTION` (WIDTHxHEIGHT, before rotation), for
/// previews and tests; the opened output decides otherwise.
pub fn resolution_override() -> Option<(u32, u32)> {
    std::env::var("CYBEXOS_INSTALLER_RESOLUTION").ok().as_deref().and_then(parse_resolution)
}

pub fn parse_resolution(value: &str) -> Option<(u32, u32)> {
    let (w, h) = value.split_once('x')?;
    Some((w.parse().ok()?, h.parse().ok()?)).filter(|&(w, h)| w > 0 && h > 0)
}

/// The boot menu's "Rotate the screen" choice, `cybexos.rotate=` on the kernel
/// command line, in degrees for Slint's KMS backend (`SLINT_KMS_ROTATION`).
pub fn rotation(cmdline: &str) -> Option<u32> {
    cmdline
        .split_whitespace()
        .rev()
        .find_map(|word| word.strip_prefix("cybexos.rotate="))
        .and_then(|value| value.parse().ok())
        .filter(|degrees| matches!(degrees, 0 | 90 | 180 | 270))
}

/// The panel as the interface sees it after rotating by `degrees`.
pub fn rotated(resolution: Option<(u32, u32)>, degrees: u32) -> Option<(u32, u32)> {
    resolution.map(|(width, height)| if degrees % 180 == 90 { (height, width) } else { (width, height) })
}

pub fn zoom_for(resolution: Option<(u32, u32)>) -> f32 {
    let Some((width, height)) = resolution else {
        return 1.0;
    };
    let fit = (width as f32 / CANVAS.0).min(height as f32 / CANVAS.1);
    (fit.clamp(0.8, 3.0) * 100.0).round() / 100.0
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn zoom_fits_the_design_canvas() {
        assert_eq!(zoom_for(Some((1280, 800))), 1.0);
        assert_eq!(zoom_for(Some((1920, 1200))), 1.5);
        assert_eq!(zoom_for(Some((1920, 1080))), 1.35);
        assert_eq!(zoom_for(Some((2880, 1800))), 2.25);
        assert_eq!(zoom_for(Some((3840, 2160))), 2.7);
        assert_eq!(zoom_for(Some((1024, 600))), 0.8);
        assert_eq!(zoom_for(None), 1.0);
    }

    #[test]
    fn resolution_override_is_width_by_height() {
        assert_eq!(parse_resolution("2880x1800"), Some((2880, 1800)));
        assert_eq!(parse_resolution("0x800"), None);
        assert_eq!(parse_resolution("2880"), None);
        assert_eq!(parse_resolution("wide"), None);
    }

    #[test]
    fn rotation_comes_from_the_boot_menu() {
        assert_eq!(rotation("quiet cybexos.rotate=90 splash"), Some(90));
        assert_eq!(rotation("cybexos.rotate=90 cybexos.rotate=270"), Some(270));
        assert_eq!(rotation("quiet fbcon=rotate:1"), None);
        assert_eq!(rotation("cybexos.rotate=45"), None);
        assert_eq!(rotation("cybexos.rotate=-90"), None);
        assert_eq!(rotated(Some((1920, 1080)), 90), Some((1080, 1920)));
        assert_eq!(rotated(Some((1920, 1080)), 180), Some((1920, 1080)));
        // The landscape design canvas fits the panel's portrait width.
        assert_eq!(zoom_for(rotated(Some((1920, 1200)), 270)), 0.94);
    }
}
