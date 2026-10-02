//! Diagnostics that remain available through Files after a sideloaded app closes.

use std::fs::File;
use std::io::{self, Write};
use std::path::Path;

pub(crate) fn init_log() {
    let path = omsi_launcher_lib::in_process_log_path();
    let mut builder =
        env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("info"));
    match open_log(&path) {
        Ok(file) => {
            builder.target(env_logger::Target::Pipe(Box::new(Tee { file: Some(file) })));
            builder.write_style(env_logger::WriteStyle::Never);
        }
        Err(e) => eprintln!(
            "openOMSI: cannot write the game log at {}: {e}",
            path.display()
        ),
    }
    builder.init();
}

fn open_log(path: &Path) -> io::Result<File> {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)?;
    }
    let previous = path.with_file_name("game-prev.log");
    match std::fs::rename(path, previous) {
        Ok(()) => {}
        Err(e) if e.kind() == io::ErrorKind::NotFound => {}
        Err(e) => return Err(e),
    }
    File::create(path)
}

struct Tee {
    file: Option<File>,
}

impl Write for Tee {
    fn write(&mut self, bytes: &[u8]) -> io::Result<usize> {
        let stderr = io::stderr().write_all(bytes);
        if let Some(file) = self.file.as_mut() {
            // Keep completed records out of user-space buffers before a crash or OS kill.
            if let Err(e) = file.write_all(bytes).and_then(|_| file.flush()) {
                self.file = None;
                eprintln!("openOMSI: the game log cannot be written any more: {e}");
            }
        }
        stderr?;
        Ok(bytes.len())
    }

    fn flush(&mut self) -> io::Result<()> {
        if let Some(file) = self.file.as_mut() {
            file.flush()?;
        }
        io::stderr().flush()
    }
}
