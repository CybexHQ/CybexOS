//! Exercise the actual Slint tree and controller, without display devices.
use cybexos_installer::{
    client::Client,
    protocol::{State, Static},
    ui::App,
    InstallerWindow, Store,
};
use slint::platform::software_renderer::{MinimalSoftwareWindow, RepaintBufferType};
use slint::platform::{Key, Platform, WindowAdapter, WindowEvent};
use slint::{ComponentHandle, Model, PhysicalSize};
use std::{cell::Cell, rc::Rc, time::Duration};

thread_local! {
    // Slint's clock stands still unless a test advances it, so timers and
    // Wiz's motion run only when a test asks for them.
    static CLOCK: Cell<Duration> = const { Cell::new(Duration::ZERO) };
}

struct Headless(Rc<MinimalSoftwareWindow>);
impl Platform for Headless {
    fn create_window_adapter(&self) -> Result<Rc<dyn WindowAdapter>, slint::PlatformError> {
        Ok(self.0.clone())
    }

    fn duration_since_start(&self) -> Duration {
        CLOCK.with(Cell::get)
    }
}

fn setup() -> (
    InstallerWindow,
    cybexos_installer::ui::Shared,
    Rc<MinimalSoftwareWindow>,
) {
    let surface = MinimalSoftwareWindow::new(RepaintBufferType::NewBuffer);
    slint::platform::set_platform(Box::new(Headless(surface.clone()))).unwrap();
    surface.set_size(PhysicalSize::new(1280, 800));
    let ui = InstallerWindow::new().unwrap();
    ui.show().unwrap();
    let app = App::new(&ui, Client::offline());
    app.borrow_mut().apply_static(Static {
        languages: vec![
            ("en_US.UTF-8".into(), "English".into()),
            ("de_DE.UTF-8".into(), "German".into()),
        ],
        layouts: vec![("us".into(), "US".into(), "us".into())],
        features: vec![("docker".into(), "Docker".into(), "Container engine".into())],
        ..Static::default()
    });
    app.borrow_mut().apply_state(State {
        phase: "setup".into(),
        ..State::default()
    });
    draw(&surface);
    (ui, app, surface)
}

fn draw(surface: &MinimalSoftwareWindow) {
    slint::platform::update_timers_and_animations();
    let mut pixels = vec![slint::Rgb8Pixel::default(); 1280 * 800];
    surface.draw_if_needed(|r| {
        r.render(&mut pixels, 1280);
    });
}

fn key(
    ui: &InstallerWindow,
    surface: &MinimalSoftwareWindow,
    text: impl Into<slint::SharedString>,
) {
    let text = text.into();
    ui.window()
        .dispatch_event(WindowEvent::KeyPressed { text: text.clone() });
    ui.window()
        .dispatch_event(WindowEvent::KeyReleased { text });
    draw(surface);
}

#[test]
fn close_is_reachable_and_tab_stays_in_every_sheet() {
    let (ui, _app, surface) = setup();
    let store = ui.global::<Store>();
    let background = Rc::new(Cell::new(0));
    let count = background.clone();
    store.on_navigate(move |_| count.set(count.get() + 1));
    for sheet in [
        "log", "wifi", "keyboard", "language", "apps", "gpu", "timezone",
    ] {
        store.invoke_open_sheet(sheet.into());
        draw(&surface);
        // Initial sheet scope -> first interactive control, Close.
        key(&ui, &surface, Key::Tab);
        key(&ui, &surface, Key::Return);
        assert!(
            store.get_sheet().is_empty(),
            "Close not reachable in {sheet}"
        );
        // From any tab position Escape still closes, and background actions
        // cannot receive focus under the modal.
        store.invoke_open_sheet(sheet.into());
        draw(&surface);
        for _ in 0..45 {
            key(&ui, &surface, Key::Tab);
        }
        key(&ui, &surface, Key::Escape);
        assert!(
            store.get_sheet().is_empty(),
            "Escape not handled in {sheet}"
        );
        store.invoke_open_sheet(sheet.into());
        draw(&surface);
        ui.window().dispatch_event(WindowEvent::KeyPressed {
            text: Key::Shift.into(),
        });
        for _ in 0..45 {
            key(&ui, &surface, Key::Tab);
        }
        ui.window().dispatch_event(WindowEvent::KeyReleased {
            text: Key::Shift.into(),
        });
        key(&ui, &surface, Key::Escape);
        assert!(store.get_sheet().is_empty(), "Shift+Tab escaped {sheet}");
    }
    assert_eq!(background.get(), 0);
}

#[test]
fn snapshots_preserve_list_identity_and_selection_focus() {
    let (ui, app, surface) = setup();
    let store = ui.global::<Store>();
    store.invoke_open_sheet("language".into());
    draw(&surface);
    key(&ui, &surface, Key::Tab); // Close
    key(&ui, &surface, Key::Tab); // English
    key(&ui, &surface, Key::Tab); // German
    let before = store.get_languages();
    let mut next = State {
        phase: "setup".into(),
        ..State::default()
    };
    next.network.busy = true;
    app.borrow_mut().apply_state(next.clone());
    draw(&surface);
    assert!(
        before == store.get_languages(),
        "model was replaced on network update"
    );
    let picked = Rc::new(Cell::new(false));
    let result = picked.clone();
    store.on_choose_language(move |language| result.set(language == "de_DE.UTF-8"));
    key(&ui, &surface, Key::Return);
    assert!(picked.get(), "snapshot lost focus on German row");
    // Updating the selection also preserves the model and focused delegate.
    next.draft.locale = "de_DE.UTF-8".into();
    app.borrow_mut().apply_state(next);
    assert!(before == store.get_languages());
}

#[test]
fn repeated_enter_cannot_activate_install_or_other_actions() {
    let (ui, _app, surface) = setup();
    let store = ui.global::<Store>();
    store.set_screen("review".into());
    draw(&surface);
    let installs = Rc::new(Cell::new(0));
    let count = installs.clone();
    store.on_install(move || count.set(count.get() + 1));
    // Tab through every control while simulating the repeat from a held Enter.
    for _ in 0..25 {
        key(&ui, &surface, Key::Tab);
        ui.window().dispatch_event(WindowEvent::KeyPressRepeated {
            text: Key::Return.into(),
        });
        draw(&surface);
    }
    assert_eq!(installs.get(), 0);
}

#[test]
fn unchanged_snapshots_do_not_repaint_the_screen() {
    let (_ui, app, surface) = setup();
    let state = State {
        phase: "setup".into(),
        ..State::default()
    };
    app.borrow_mut().apply_state(state.clone());
    draw(&surface);
    let started = std::time::Instant::now();
    let mut frames = 0;
    let mut pixels = vec![slint::Rgb8Pixel::default(); 1280 * 800];
    for _ in 0..100 {
        app.borrow_mut().apply_state(state.clone());
        slint::platform::update_timers_and_animations();
        surface.draw_if_needed(|renderer| {
            frames += 1;
            renderer.render(&mut pixels, 1280);
        });
    }
    eprintln!(
        "100 unchanged snapshots: {} ms, {frames} frames",
        started.elapsed().as_millis()
    );
    assert_eq!(
        frames, 0,
        "unchanged state should not schedule a framebuffer repaint"
    );
}

fn log_pixels(surface: &MinimalSoftwareWindow) -> Vec<slint::Rgb8Pixel> {
    surface.request_redraw();
    let mut pixels = vec![slint::Rgb8Pixel::default(); 1280 * 800];
    surface.draw_if_needed(|renderer| {
        renderer.render(&mut pixels, 1280);
    });
    (220..400)
        .flat_map(|y| pixels[y * 1280 + 100..y * 1280 + 700].iter().copied())
        .collect()
}

#[test]
fn log_scrolls_with_keyboard_and_refresh_keeps_the_reading_position() {
    let (ui, _app, surface) = setup();
    let store = ui.global::<Store>();
    let mut text: String = (0..250)
        .map(|i| format!("Log line {i:03}: installation diagnostics\n"))
        .collect();
    store.set_details(text.clone().into());
    store.invoke_open_sheet("log".into());
    draw(&surface);
    key(&ui, &surface, Key::Home);
    let head = log_pixels(&surface);
    key(&ui, &surface, Key::End);
    let tail = log_pixels(&surface);
    assert!(
        head != tail,
        "Home and End must scroll the actual rendered log"
    );
    key(&ui, &surface, Key::PageUp);
    assert!(tail != log_pixels(&surface), "Page Up must scroll the log");
    key(&ui, &surface, Key::Home);
    text.push_str("New diagnostics while reading\n");
    store.set_details(text.into());
    draw(&surface);
    assert!(
        head == log_pixels(&surface),
        "refresh moved the reader to the end"
    );
}

#[test]
fn network_panel_stays_available_while_installation_waits_for_reconnection() {
    let (ui, app, surface) = setup();
    let store = ui.global::<Store>();
    let mut state = State {
        phase: "installing".into(),
        stage: 4,
        message: "Connection interrupted. Reconnect Ethernet or Wi-Fi; installation will resume automatically.".into(),
        ..State::default()
    };
    app.borrow_mut().apply_state(state.clone());
    draw(&surface);
    let position = slint::LogicalPosition::new(990.0, 36.0);
    ui.window().dispatch_event(WindowEvent::PointerPressed {
        position,
        button: slint::platform::PointerEventButton::Left,
    });
    ui.window().dispatch_event(WindowEvent::PointerReleased {
        position,
        button: slint::platform::PointerEventButton::Left,
    });
    draw(&surface);
    assert_eq!(store.get_sheet(), "wifi", "the network chip was disabled during installation");
    state.elapsed = 30;
    state.network.busy = true;
    app.borrow_mut().apply_state(state.clone());
    draw(&surface);
    assert_eq!(store.get_sheet(), "wifi", "a background snapshot closed network recovery");
    assert_eq!(store.get_stages().row_data(3).unwrap().detail, state.message);
    assert_eq!(store.get_install_pose(), "thinking", "Wiz should check while the network is away");
    state.message = "Connection restored. Resuming installation…".into();
    app.borrow_mut().apply_state(state);
    assert_eq!(store.get_install_pose(), "working");
}

/// Frames drawn while Slint's clock runs `ms` milliseconds ahead.
fn frames_over(surface: &MinimalSoftwareWindow, ms: u64) -> usize {
    let mut frames = 0;
    let mut pixels = vec![slint::Rgb8Pixel::default(); 1280 * 800];
    for _ in 0..ms / 40 {
        CLOCK.with(|clock| clock.set(clock.get() + Duration::from_millis(40)));
        slint::platform::update_timers_and_animations();
        surface.draw_if_needed(|renderer| {
            frames += 1;
            renderer.render(&mut pixels, 1280);
        });
    }
    frames
}

#[test]
fn hardware_preflight_distinguishes_detection_and_blocks_unsupported_graphics() {
    let (ui, app, surface) = setup();
    let store = ui.global::<Store>();
    let mut ready = State {
        phase: "setup".into(),
        memory: 16 << 30,
        hardware: serde_json::from_value(serde_json::json!({
            "nvidia": true, "nvidiaSelection": {"open": false, "closed": true},
            "graphicsDetail": "Driver selected for the detected IDs",
            "networkIssues": ["Network adapter 14e4:43a0 has no active driver"], "blockers": []
        })).unwrap(),
        ..State::default()
    };
    ready.firmware.uefi = true;
    ready.network.connected = true;
    ready.draft.nvidia_open = false;
    app.borrow_mut().apply_state(ready.clone());
    draw(&surface);
    let graphics = store.get_checks().iter().find(|c| c.label == "Graphics").unwrap();
    assert_eq!(graphics.state, 2, "detected graphics are not a desktop qualification pass");
    let network = store.get_checks().iter().find(|c| c.label == "Network").unwrap();
    assert_eq!(network.state, 3, "a second broken adapter must remain visible when connected");
    assert!(network.detail.contains("14e4:43a0"));
    assert!(!store.get_nvidia_open_available());
    assert!(store.get_nvidia_closed_available());
    assert!(store.get_can_start());

    ready.hardware.insert("blockers".into(), serde_json::json!(["No packaged NVIDIA driver supports all detected GPUs"]));
    app.borrow_mut().apply_state(ready.clone());
    assert!(!store.get_can_start());
    let graphics = store.get_checks().iter().find(|c| c.label == "Graphics").unwrap();
    assert_eq!(graphics.state, 4);
    assert!(graphics.detail.contains("No packaged NVIDIA driver"));

    ready.phase = "preflight".into();
    ready.firmware.secure_boot = true;
    ready.error = "Secure Boot is enabled".into();
    app.borrow_mut().apply_state(ready);
    assert!(store.get_stop_steps().iter().any(|step| step == "Keep Secure Boot enabled."));
    assert!(store.get_stop_action().is_empty());
}

#[test]
fn wiz_moves_only_while_he_checks_or_works_and_never_under_a_sheet() {
    use cybexos_installer::protocol::Disk;
    let (ui, app, surface) = setup();
    let store = ui.global::<Store>();
    // Verifying the medium: the runes circle his hat, 25 frames a second.
    app.borrow_mut().apply_state(State {
        phase: "loading".into(),
        ..State::default()
    });
    draw(&surface);
    assert_eq!(store.get_check_pose(), "thinking");
    assert!(frames_over(&surface, 1000) >= 20, "thinking should loop");
    // A sheet over him holds him still; only the 1 Hz activity tick repaints.
    store.invoke_open_sheet("keyboard".into());
    draw(&surface);
    assert!(frames_over(&surface, 2000) <= 3, "Wiz moved under a sheet");
    store.invoke_close_sheet();
    draw(&surface);
    // Every check passed: happy, and still, with no blinks.
    let mut ready = State {
        phase: "setup".into(),
        memory: 16 << 30,
        disks: vec![Disk {
            path: "/dev/vda".into(),
            available: true,
            ..Disk::default()
        }],
        ..State::default()
    };
    ready.firmware.uefi = true;
    ready.network.connected = true;
    app.borrow_mut().apply_state(ready.clone());
    draw(&surface);
    assert_eq!(store.get_check_pose(), "happy");
    assert_eq!(frames_over(&surface, 10_000), 0, "a happy Wiz should hold still");
    // Offline is your move: blinks and a few pulses, not a loop.
    ready.network.connected = false;
    app.borrow_mut().apply_state(ready);
    draw(&surface);
    assert_eq!(store.get_check_pose(), "needs-input");
    let waiting = frames_over(&surface, 20_000);
    assert!(waiting > 0 && waiting < 200, "needs-input drew {waiting} frames in 20 s");
    // Installing: the spell works on, sorry after a failure.
    app.borrow_mut().apply_state(State {
        phase: "installing".into(),
        stage: 2,
        ..State::default()
    });
    draw(&surface);
    assert_eq!(store.get_install_pose(), "working");
    assert!(frames_over(&surface, 1000) >= 20, "working should loop");
    let mut failed = State {
        phase: "error".into(),
        error: "The installation download service could not be reached.".into(),
        ..State::default()
    };
    failed.firmware.uefi = true;
    app.borrow_mut().apply_state(failed);
    assert_eq!(store.get_screen(), "stopped");
    assert_eq!(store.get_stop_pose(), "sorry");
}

#[test]
fn wifi_submission_keeps_keyboard_focus_in_the_network_panel() {
    use cybexos_installer::protocol::WifiNetwork;
    let (ui, app, surface) = setup();
    let store = ui.global::<Store>();
    let mut state = State { phase: "setup".into(), ..State::default() };
    state.network.wifi.interface = "wlan0".into();
    state.network.wifi.networks = vec![WifiNetwork {
        ssid: "Test network".into(), security: "WPA2".into(), ..WifiNetwork::default()
    }];
    app.borrow_mut().apply_state(state);
    store.invoke_open_sheet("wifi".into());
    draw(&surface);
    for _ in 0..3 { key(&ui, &surface, Key::Tab); }
    key(&ui, &surface, Key::Return);
    key(&ui, &surface, Key::Tab);
    for letter in "testsecret".chars() { key(&ui, &surface, letter.to_string()); }
    key(&ui, &surface, Key::Return);
    assert_eq!(store.get_wifi_selected(), -1);
    draw(&surface);
    key(&ui, &surface, Key::Escape);
    assert_eq!(store.get_sheet(), "", "submitting removed the focused field and stranded Escape");
}

#[test]
fn wifi_refresh_preserves_credentials_but_reordering_clears_selection() {
    use cybexos_installer::protocol::WifiNetwork;
    use std::cell::RefCell;
    let (ui, app, surface) = setup();
    let store = ui.global::<Store>();
    let mut state = State {
        phase: "setup".into(),
        ..State::default()
    };
    state.network.wifi.interface = "wlan0".into();
    state.network.wifi.networks = vec![WifiNetwork {
        ssid: "Test network".into(),
        security: "WPA2".into(),
        signal: 80,
        ..WifiNetwork::default()
    }];
    app.borrow_mut().apply_state(state.clone());
    store.invoke_open_sheet("wifi".into());
    draw(&surface);
    for _ in 0..3 {
        key(&ui, &surface, Key::Tab);
    } // Close, Refresh, network
    key(&ui, &surface, Key::Return);
    assert_eq!(store.get_wifi_selected(), 0);
    key(&ui, &surface, Key::Tab); // Password
    for letter in "testsecret".chars() {
        key(&ui, &surface, letter.to_string());
    }
    state.network.wifi.networks[0].signal = 70;
    app.borrow_mut().apply_state(state.clone());
    draw(&surface);
    let password = Rc::new(RefCell::new(String::new()));
    let observed = password.clone();
    store.on_wifi_connect(move |_, secret, _| *observed.borrow_mut() = secret.to_string());
    key(&ui, &surface, Key::Return);
    assert_eq!(*password.borrow(), "testsecret");
    state.network.wifi.networks.insert(
        0,
        WifiNetwork {
            ssid: "Other network".into(),
            ..WifiNetwork::default()
        },
    );
    app.borrow_mut().apply_state(state);
    assert_eq!(
        store.get_wifi_selected(),
        -1,
        "credentials could move to another SSID"
    );
}

const SOFTWARE: &str = r#"{"type":"static","schema":"cybexos.installer-state.v1",
    "layouts":[["us","US","us"]],"languages":[["en_US.UTF-8","English"]],
    "features":[["docker","Docker","Container engine"],["proprietary","Proprietary applications","Vendor apps"]],
    "software":{"profiles":[
        {"id":"development","name":"Software Development","short":"Development","icon":"code","default":true,"onMedium":true,
         "includes":[{"name":"Docker","icon":""}],"apps":["zed"],"features":["developer","docker"],"downloadBytes":0,"vendor":0},
        {"id":"office","name":"Office & Productivity","short":"Office","icon":"briefcase","apps":["writer"],"downloadBytes":90000000,"vendor":0},
        {"id":"chat","name":"Chat & Meetings","short":"Chat","icon":"messages","apps":["slack"],"downloadBytes":5,"vendor":1}],
     "apps":{"zed":{"name":"Zed","free":true,"icon":"","downloadBytes":1},
             "writer":{"name":"Writer","free":true,"icon":"","downloadBytes":1},
             "slack":{"name":"Slack","free":false,"icon":"","downloadBytes":0}}}}"#;

/// A recording controller on the Software step with the given draft and network.
fn software_setup(
    draft: serde_json::Value,
    online: bool,
) -> (InstallerWindow, cybexos_installer::ui::Shared, Rc<MinimalSoftwareWindow>, cybexos_installer::client::Recorder) {
    use cybexos_installer::protocol::{parse, Message};
    let surface = MinimalSoftwareWindow::new(RepaintBufferType::NewBuffer);
    slint::platform::set_platform(Box::new(Headless(surface.clone()))).unwrap();
    surface.set_size(PhysicalSize::new(1280, 800));
    let ui = InstallerWindow::new().unwrap();
    ui.show().unwrap();
    let (client, recorder) = Client::recording();
    let app = App::new(&ui, client);
    let Some(Message::Static(statics)) = parse(SOFTWARE) else { panic!("static fixture") };
    app.borrow_mut().apply_static(*statics);
    let mut state = serde_json::json!({"type": "state", "schema": "cybexos.installer-state.v1", "phase": "setup",
        "network": {"connected": online}, "draft": {"screen": "software", "profiles": ["development"]},
        "software": {"profiles": ["development"], "online": online}});
    for (key, value) in draft.as_object().unwrap() {
        state["draft"][key] = value.clone();
    }
    app.borrow_mut().apply_state(state_from(state));
    draw(&surface);
    recorder.take();
    (ui, app, surface, recorder)
}

fn state_from(value: serde_json::Value) -> State {
    use cybexos_installer::protocol::{parse, Message};
    let Some(Message::State(state)) = parse(&value.to_string()) else { panic!("state fixture") };
    *state
}

fn click(ui: &InstallerWindow, surface: &MinimalSoftwareWindow, x: f32, y: f32) {
    let position = slint::LogicalPosition::new(x, y);
    for event in [
        WindowEvent::PointerPressed { position, button: slint::platform::PointerEventButton::Left },
        WindowEvent::PointerReleased { position, button: slint::platform::PointerEventButton::Left },
    ] {
        ui.window().dispatch_event(event);
    }
    draw(surface);
}

#[test]
fn the_software_step_holds_the_password_until_its_continue() {
    let (ui, _app, surface, sent) = software_setup(serde_json::json!({"screen": "account", "username": "ada"}), true);
    let store = ui.global::<Store>();
    store.set_screen("account".into());
    store.set_username("ada".into());
    store.set_password("correct horse battery".into());
    store.set_confirm("correct horse battery".into());
    store.invoke_passwords_edited();
    store.invoke_continue_account();
    assert_eq!(store.get_screen(), "software");
    let requests = sent.take();
    assert_eq!(requests, [serde_json::json!({"action": "draft", "values": {"screen": "software"}})],
               "the account step sends no password");
    draw(&surface);
    // Enter on the Software step asks for the review with the held password.
    key(&ui, &surface, Key::Return);
    let requests = sent.take();
    assert_eq!(requests.len(), 1);
    assert_eq!(requests[0]["action"], "review");
    assert_eq!(requests[0]["password"], "correct horse battery");
    // A restarted screen (a new keyboard layout) lost the password: back to You.
    store.set_password("".into());
    store.set_confirm("".into());
    store.set_review_busy(false);
    store.invoke_continue_software();
    assert_eq!(store.get_screen(), "account");
    assert_eq!(sent.take(), [serde_json::json!({"action": "draft", "values": {"screen": "account"}})]);
}

#[test]
fn profile_cards_toggle_and_need_the_internet_unless_on_the_medium() {
    let (ui, app, surface, sent) = software_setup(serde_json::json!({}), true);
    let store = ui.global::<Store>();
    let cards = store.get_profiles();
    assert_eq!(cards.row_count(), 3);
    let development = cards.row_data(0).unwrap();
    assert!(development.selected && development.recommended);
    assert_eq!(development.size, "On this USB stick");
    assert_eq!(cards.row_data(2).unwrap().vendor, "1 from vendor");
    assert_eq!(store.get_software_note_strong(), "Development");
    // The second card, Office & Productivity.
    click(&ui, &surface, 640.0, 300.0);
    assert_eq!(sent.take(), [serde_json::json!({"action": "draft", "values": {"profiles": ["development", "office"]}})]);
    click(&ui, &surface, 250.0, 300.0);
    assert_eq!(sent.take(), [serde_json::json!({"action": "draft", "values": {"profiles": []}})]);

    // Offline, the profiles the medium does not carry are dimmed and inert.
    let offline = serde_json::json!({"type": "state", "schema": "cybexos.installer-state.v1", "phase": "setup",
        "network": {"connected": false}, "draft": {"screen": "software", "profiles": ["development", "office"]},
        "software": {"profiles": ["development"], "online": false}});
    app.borrow_mut().apply_state(state_from(offline));
    draw(&surface);
    let office = store.get_profiles().row_data(1).unwrap();
    assert!(!office.available && !office.selected);
    assert_eq!(office.size, "Needs internet");
    assert_eq!(store.get_software_note_strong(), "Offline:");
    click(&ui, &surface, 640.0, 300.0);
    store.invoke_toggle_profile("office".into());
    assert!(sent.take().is_empty(), "an offline-only card was toggled");
}

#[test]
fn customize_switches_apps_and_system_features_from_the_keyboard() {
    let (ui, app, surface, sent) = software_setup(serde_json::json!({"profiles": ["development", "chat"]}), true);
    let store = ui.global::<Store>();
    store.invoke_open_sheet("apps".into());
    draw(&surface);
    let rows: Vec<_> = (0..store.get_custom_rows().row_count()).map(|i| store.get_custom_rows().row_data(i).unwrap()).collect();
    let titles: Vec<&str> = rows.iter().map(|r| r.title.as_str()).collect();
    assert_eq!(titles, ["SOFTWARE DEVELOPMENT", "Zed", "Also includes Docker.", "CHAT & MEETINGS", "Slack",
                        "SYSTEM FEATURES", "Docker", "Proprietary applications"]);
    key(&ui, &surface, Key::Tab); // Close
    key(&ui, &surface, Key::Tab); // Zed
    key(&ui, &surface, " ");
    assert_eq!(sent.take(), [serde_json::json!({"action": "draft", "values": {"appsOff": ["zed"]}})]);
    store.invoke_toggle_feature("proprietary".into());
    assert_eq!(sent.take(), [serde_json::json!({"action": "draft", "values": {"features": {"proprietary": false}}})]);

    // Without proprietary applications, unfree apps cannot be switched on.
    let state = serde_json::json!({"type": "state", "schema": "cybexos.installer-state.v1", "phase": "setup",
        "network": {"connected": true}, "draft": {"screen": "software", "profiles": ["development", "chat"],
        "appsOff": ["zed"], "features": {"proprietary": false}},
        "software": {"profiles": ["development", "chat"], "online": true, "withheld": 1}});
    app.borrow_mut().apply_state(state_from(state));
    draw(&surface);
    let rows: Vec<_> = (0..store.get_custom_rows().row_count()).map(|i| store.get_custom_rows().row_data(i).unwrap()).collect();
    let zed = rows.iter().find(|r| r.title == "Zed").unwrap();
    assert!(zed.enabled && !zed.on);
    let slack = rows.iter().find(|r| r.title == "Slack").unwrap();
    assert!(!slack.enabled && !slack.on);
    assert!(rows.iter().any(|r| r.kind == 3 && r.warn && r.title.contains("Codex still is")));
    assert!(!store.get_always_included().contains("Claude Code"));
    key(&ui, &surface, Key::Escape);
    assert_eq!(store.get_sheet(), "");
}

#[test]
fn review_back_and_change_return_to_the_software_step() {
    let (ui, app, surface, sent) = software_setup(serde_json::json!({}), true);
    let store = ui.global::<Store>();
    let review = serde_json::json!({"type": "state", "schema": "cybexos.installer-state.v1", "phase": "review",
        "network": {"connected": true}, "draft": {"screen": "software", "profiles": ["development"], "disk": "/dev/vda"},
        "disks": [{"path": "/dev/vda", "size": 85899345920u64, "available": true, "model": "QA"}],
        "software": {"profiles": ["development"], "online": true}});
    app.borrow_mut().apply_state(state_from(review));
    draw(&surface);
    assert_eq!(store.get_screen(), "review");
    let rows = store.get_summary_right();
    let software = (0..rows.row_count()).map(|i| rows.row_data(i).unwrap()).find(|r| r.label == "Software").unwrap();
    assert_eq!((software.value.as_str(), software.action.as_str()), ("Development", "software"));
    key(&ui, &surface, Key::Escape);
    assert_eq!(sent.take(), [serde_json::json!({"action": "back"})]);
    store.invoke_change("software".into());
    assert_eq!(sent.take(), [serde_json::json!({"action": "back"})]);
    store.invoke_change("account".into());
    assert_eq!(sent.take(), [serde_json::json!({"action": "back"}), serde_json::json!({"action": "draft", "values": {"screen": "account"}})]);
}
