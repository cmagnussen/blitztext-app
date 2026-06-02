use anyhow::Result;
use keyring::Entry;

const SERVICE: &str = "app.blitztext.credentials";
const USERNAME: &str = "openai-api-key";

pub fn save_api_key(key: &str) -> Result<()> {
    let entry = Entry::new(SERVICE, USERNAME)?;
    entry.set_password(key)?;
    Ok(())
}

pub fn load_api_key() -> Result<String> {
    let entry = Entry::new(SERVICE, USERNAME)?;
    let password = entry.get_password()?;
    Ok(password)
}

pub fn delete_api_key() -> Result<()> {
    let entry = Entry::new(SERVICE, USERNAME)?;
    entry.delete_credential()?;
    Ok(())
}

pub fn has_api_key() -> bool {
    load_api_key().is_ok()
}
