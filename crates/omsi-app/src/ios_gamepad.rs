//! Apple GameController snapshots, including the Simulator's forwarded controllers.

pub(crate) const BUTTON_COUNT: usize = 14;

/// Must match OpenOMSI_Gamepad in ios/game_controller.h.
#[repr(C)]
#[derive(Clone, Copy)]
struct Snapshot {
    id: u64,
    buttons: u32,
    axes: [f32; 6],
    name: [u8; 128],
}

impl Default for Snapshot {
    fn default() -> Self {
        Self {
            id: 0,
            buttons: 0,
            axes: [0.0; 6],
            name: [0; 128],
        }
    }
}

#[cfg(target_os = "ios")]
extern "C" {
    fn openomsi_poll_gamepads(out: *mut Snapshot, capacity: usize) -> usize;
}

#[derive(Clone, Debug)]
pub(crate) struct Pad {
    id: u64,
    pub name: String,
    pub axes: [f32; 6],
    buttons: u32,
}

impl From<Snapshot> for Pad {
    fn from(raw: Snapshot) -> Self {
        let end = raw
            .name
            .iter()
            .position(|b| *b == 0)
            .unwrap_or(raw.name.len());
        let name = String::from_utf8_lossy(&raw.name[..end]).into_owned();
        let mut axes = raw.axes;
        for (i, value) in axes.iter_mut().enumerate() {
            *value = if value.is_finite() {
                value.clamp(if i < 4 { -1.0 } else { 0.0 }, 1.0)
            } else {
                0.0
            };
        }
        Self {
            id: raw.id,
            name: if name.is_empty() {
                "Gamepad".into()
            } else {
                name
            },
            axes,
            buttons: raw.buttons & ((1 << BUTTON_COUNT) - 1),
        }
    }
}

pub(crate) struct Gamepads {
    pub pads: Vec<Pad>,
    focused: bool,
    trace: Option<([f32; 3], std::time::Instant)>,
}

impl Default for Gamepads {
    fn default() -> Self {
        Self {
            pads: Vec::new(),
            focused: true,
            trace: None,
        }
    }
}

impl Gamepads {
    pub fn set_focus(&mut self, focused: bool) {
        self.focused = focused;
    }

    pub fn poll(&mut self) -> Vec<(String, usize, bool)> {
        #[cfg(target_os = "ios")]
        let pads = {
            let mut raw = [Snapshot::default(); 8];
            // SAFETY: the bridge writes at most capacity fully initialized snapshots;
            // the caller owns their storage, and no Objective-C pointers escape.
            let count =
                unsafe { openomsi_poll_gamepads(raw.as_mut_ptr(), raw.len()) }.min(raw.len());
            raw[..count].iter().copied().map(Pad::from).collect()
        };
        #[cfg(not(target_os = "ios"))]
        let pads = Vec::new();
        self.update(pads)
    }

    fn update(&mut self, mut next: Vec<Pad>) -> Vec<(String, usize, bool)> {
        if !self.focused {
            next.clear();
        }
        let mut events = Vec::new();
        // Release the old controller before processing newly connected devices, even if
        // both have the same vendor name or the OS changes their enumeration order.
        for old in &self.pads {
            let buttons = next
                .iter()
                .find(|p| p.id == old.id)
                .map(|p| p.buttons)
                .unwrap_or(0);
            for button in 0..BUTTON_COUNT {
                let bit = 1 << button;
                if old.buttons & bit != 0 && buttons & bit == 0 {
                    events.push((old.name.clone(), button, false));
                }
            }
        }
        for pad in &next {
            let old = self.pads.iter().find(|p| p.id == pad.id);
            if old.is_none() {
                log::info!(
                    "game controller connected: {} (Apple GameController)",
                    pad.name
                );
            }
            let buttons = old.map(|p| p.buttons).unwrap_or(0);
            for button in 0..BUTTON_COUNT {
                let bit = 1 << button;
                if pad.buttons & bit != 0 && buttons & bit == 0 {
                    events.push((pad.name.clone(), button, true));
                }
            }
        }
        if std::env::var_os("OMSI_CONTROLLER_TRACE").is_some() {
            let values = next
                .first()
                .map(|p| [p.axes[0], p.axes[4], p.axes[5]])
                .unwrap_or([0.0; 3]);
            let changed = self.trace.as_ref().is_none_or(|(last, at)| {
                at.elapsed().as_secs_f32() >= 0.5
                    && values.iter().zip(last).any(|(a, b)| (a - b).abs() >= 0.05)
            });
            if changed {
                log::info!(
                    "game controller input: steering {:.2}, brake {:.2}, throttle {:.2}",
                    values[0],
                    values[1],
                    values[2]
                );
                self.trace = Some((values, std::time::Instant::now()));
            }
        }
        self.pads = next;
        events
    }
}

/// Defaults share the touch controls' bus-independent actions. Saved bindings win.
pub(crate) fn default_action(button: usize) -> Option<&'static str> {
    [
        "pad_door_1",
        "pad_parking_brake",
        "pad_horn",
        "pad_auto_start",
        "pad_blink_left",
        "pad_blink_right",
        "pad_camera",
        "pad_pause",
        "pad_look_reset",
        "pad_stop_brake",
        "pad_drive",
        "pad_reverse",
        "pad_neutral",
        "pad_door_2",
    ]
    .get(button)
    .copied()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn pad(id: u64, buttons: u32) -> Pad {
        Pad {
            id,
            name: "Xbox".into(),
            buttons,
            axes: [0.5, 0.0, 0.0, 0.0, 0.3, 0.8],
        }
    }

    #[test]
    fn disconnect_and_focus_loss_release_buttons_and_axes() {
        let mut pads = Gamepads::default();
        assert_eq!(pads.update(vec![pad(1, 4)]), vec![("Xbox".into(), 2, true)]);
        assert!(pads.update(vec![pad(1, 4)]).is_empty());
        pads.set_focus(false);
        assert_eq!(
            pads.update(vec![pad(1, 4)]),
            vec![("Xbox".into(), 2, false)]
        );
        assert!(pads.pads.is_empty());
        pads.set_focus(true);
        pads.update(vec![pad(1, 4)]);
        assert_eq!(pads.update(Vec::new()), vec![("Xbox".into(), 2, false)]);
        assert!(pads.pads.is_empty());
    }

    #[test]
    fn reordered_devices_do_not_repeat_presses_and_replacements_release() {
        let mut pads = Gamepads::default();
        pads.update(vec![pad(1, 4), pad(2, 1)]);
        assert!(pads.update(vec![pad(2, 1), pad(1, 4)]).is_empty());
        assert_eq!(
            pads.update(vec![pad(3, 0)]),
            vec![("Xbox".into(), 0, false), ("Xbox".into(), 2, false)]
        );
    }

    #[test]
    fn native_layout_and_invalid_values_are_bounded() {
        assert_eq!(std::mem::size_of::<Snapshot>(), 168);
        assert_eq!(std::mem::offset_of!(Snapshot, name), 36);
        let pad = Pad::from(Snapshot {
            axes: [f32::NAN, 2.0, -2.0, 0.0, -1.0, 3.0],
            ..Default::default()
        });
        assert_eq!(pad.axes, [0.0, 1.0, -1.0, 0.0, 0.0, 1.0]);
        assert_eq!(pad.name, "Gamepad");
    }
}
