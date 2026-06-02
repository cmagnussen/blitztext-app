use anyhow::Result;
use enigo::{Enigo, Keyboard, Settings, Key, Direction};
use std::thread;
use std::time::Duration;

pub fn simulate_paste() -> Result<()> {
    thread::sleep(Duration::from_millis(100));

    let mut enigo = Enigo::new(&Settings::default())
        .map_err(|e| anyhow::anyhow!("Enigo-Fehler: {e}"))?;

    enigo
        .key(Key::Control, Direction::Press)
        .map_err(|e| anyhow::anyhow!("Tastendruck-Fehler: {e}"))?;
    enigo
        .key(Key::Unicode('v'), Direction::Click)
        .map_err(|e| anyhow::anyhow!("Tastendruck-Fehler: {e}"))?;
    enigo
        .key(Key::Control, Direction::Release)
        .map_err(|e| anyhow::anyhow!("Tastendruck-Fehler: {e}"))?;

    Ok(())
}
