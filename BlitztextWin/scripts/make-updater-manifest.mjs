// Erzeugt das latest.json, das tauri-plugin-updater erwartet.
// Nutzung: node scripts/make-updater-manifest.mjs <tag> <ausgabedatei>
//
// Die Signatur ist der Inhalt der vom Bundler erzeugten .sig-Datei, nicht
// ihr Pfad. Die Version kommt aus tauri.conf.json und ist durch den
// Versions-Guard garantiert identisch mit dem Tag.
import { readFileSync, writeFileSync, readdirSync } from "node:fs";
import { join } from "node:path";

const REPOSITORY = "geninOne/blitztext-app";
const NSIS_ORDNER = "src-tauri/target/release/bundle/nsis";

const [, , tag, ausgabe] = process.argv;
if (!tag || !ausgabe) {
  console.error("Nutzung: node scripts/make-updater-manifest.mjs <tag> <ausgabedatei>");
  process.exit(2);
}

let dateien = [];
try {
  dateien = readdirSync(NSIS_ORDNER);
} catch (err) {
  if (err.code === 'ENOENT') {
    console.error(
      `Kein signiertes NSIS-Setup in ${NSIS_ORDNER}. Gefunden: nichts`
    );
    process.exit(1);
  }
  throw err;
}

const setup = dateien.find((name) => name.endsWith("-setup.exe"));

if (!setup) {
  console.error(
    `Kein NSIS-Setup in ${NSIS_ORDNER}. Gefunden: ${dateien.join(", ") || "nichts"}`
  );
  process.exit(1);
}

// Der Name der Signatur wird aus dem Setup-Namen abgeleitet, nicht unabhaengig
// gesucht. Bei einem alten Artefakt im Ordner wuerden zwei getrennte Suchen
// sonst die URL der einen Version mit der Signatur einer anderen paaren. Das
// faellt erst beim Nutzer auf, weil die jq-Pruefung im Workflow nur sieht, dass
// beide Felder gefuellt sind.
const signaturDatei = `${setup}.sig`;

if (!dateien.includes(signaturDatei)) {
  console.error(
    `Zum Setup ${setup} fehlt die Signatur ${signaturDatei} in ${NSIS_ORDNER}. `
      + `Gefunden: ${dateien.join(", ") || "nichts"}`
  );
  process.exit(1);
}

const version = JSON.parse(readFileSync("src-tauri/tauri.conf.json", "utf8")).version;
const signature = readFileSync(join(NSIS_ORDNER, signaturDatei), "utf8").trim();

const manifest = {
  version,
  notes: `Blitztext ${tag}`,
  pub_date: new Date().toISOString(),
  platforms: {
    "windows-x86_64": {
      signature,
      url: `https://github.com/${REPOSITORY}/releases/download/${tag}/${setup}`,
    },
  },
};

writeFileSync(ausgabe, JSON.stringify(manifest, null, 2));
console.log(`Manifest geschrieben: ${ausgabe}`);
console.log(JSON.stringify(manifest, null, 2));
