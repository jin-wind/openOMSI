//! The launcher and game share one event loop and window on phones and tablets.

use super::*;

#[derive(Default)]
pub(crate) struct Shell {
    launcher: Option<Box<launcher::Launcher>>,
    game: Option<Box<App>>,
}

impl Shell {
    #[cfg(target_os = "ios")]
    pub(crate) fn with_launcher(launcher: launcher::Launcher) -> Self {
        Self {
            launcher: Some(Box::new(launcher)),
            game: None,
        }
    }

    #[cfg(target_os = "ios")]
    pub(crate) fn with_game(game: App) -> Self {
        Self {
            launcher: None,
            game: Some(Box::new(game)),
        }
    }

    fn launcher(&mut self) -> &mut launcher::Launcher {
        if self.launcher.is_none() {
            let args = Args::parse_from(["openomsi"]);
            if let Err(e) = prepare(args, true) {
                log::error!("{e:#}");
            }
            #[cfg(target_os = "android")]
            if let Some(content) = crate::startup::content_dir() {
                crate::android::hide_from_gallery(&content);
            }
            launcher_statics();
            self.launcher = Some(Box::new(launcher::Launcher::new(graphics_instance())));
        }
        self.launcher.as_mut().unwrap()
    }

    fn switch(&mut self, event_loop: &ActiveEventLoop) {
        if self.game.is_some() {
            if !crate::platform::take_leave() {
                return;
            }
            let mut game = self.game.take().unwrap();
            game.exiting(event_loop);
            let window = game.window.take();
            drop(game);
            lan_mods::clean_up();
            log::info!("session ended: back to the launcher");
            let launcher = self.launcher();
            if let Some(window) = window {
                launcher.adopt_window(window);
            }
            launcher.resumed(event_loop);
            return;
        }
        let Some(line) = omsi_launcher_lib::take_in_process_launch() else {
            return;
        };
        #[cfg(target_os = "android")]
        crate::android::prepare_drive();
        log::info!("starting the game: {}", line.join(" "));
        let argv = std::iter::once("openomsi".to_string()).chain(line);
        let args = match Args::try_parse_from(argv) {
            Ok(args) => args,
            Err(e) => {
                log::error!("the launcher's command line: {e}");
                return;
            }
        };
        let game = prepare(args, false).and_then(|prepared| match prepared {
            Some((args, server)) => make_app(args, server),
            None => Ok(None),
        });
        let mut app = match game {
            Ok(Some(app)) => app,
            Ok(None) => return,
            Err(e) => {
                log::error!("the game could not start: {e:#}");
                return;
            }
        };
        let window = self.launcher().release_window();
        app.create_window(event_loop, window);
        self.game = Some(Box::new(app));
    }
}

impl ApplicationHandler for Shell {
    fn resumed(&mut self, event_loop: &ActiveEventLoop) {
        log::info!("app in front");
        match self.game.as_mut() {
            Some(game) => game.resumed(event_loop),
            None => self.launcher().resumed(event_loop),
        }
        self.switch(event_loop);
    }

    fn suspended(&mut self, event_loop: &ActiveEventLoop) {
        log::info!("app in the background");
        match self.game.as_mut() {
            Some(game) => game.suspended(event_loop),
            None => self.launcher().suspended(event_loop),
        }
    }

    fn window_event(&mut self, event_loop: &ActiveEventLoop, id: WindowId, event: WindowEvent) {
        match self.game.as_mut() {
            Some(game) => game.window_event(event_loop, id, event),
            None => self.launcher().window_event(event_loop, id, event),
        }
        self.switch(event_loop);
    }

    fn device_event(
        &mut self,
        event_loop: &ActiveEventLoop,
        id: winit::event::DeviceId,
        event: DeviceEvent,
    ) {
        if let Some(game) = self.game.as_mut() {
            game.device_event(event_loop, id, event);
        }
    }

    fn user_event(&mut self, event_loop: &ActiveEventLoop, event: ()) {
        if let Some(game) = self.game.as_mut() {
            game.user_event(event_loop, event);
        }
        self.switch(event_loop);
    }

    fn about_to_wait(&mut self, event_loop: &ActiveEventLoop) {
        match self.game.as_mut() {
            Some(game) => {
                event_loop.set_control_flow(winit::event_loop::ControlFlow::Poll);
                game.about_to_wait(event_loop);
            }
            None => self.launcher().about_to_wait(event_loop),
        }
        self.switch(event_loop);
    }

    fn memory_warning(&mut self, _event_loop: &ActiveEventLoop) {
        log::warn!("the system is short of memory");
        crate::memory::release_free_memory();
    }

    fn exiting(&mut self, event_loop: &ActiveEventLoop) {
        if let Some(game) = self.game.as_mut() {
            game.exiting(event_loop);
        }
    }
}
