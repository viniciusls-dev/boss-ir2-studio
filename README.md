# IR-2 Studio

A native Mac app for viewing and controlling your BOSS IR-2 over USB. Read both channels, adjust your sound, save presets, and inspect official `.alb` backup files. Choose a light theme, a dark theme, or follow your Mac’s appearance.

Requires **macOS 26 or later**.

> The app’s interface is currently in Portuguese. The instructions below include the labels you will see on screen.

## Build and run

With Xcode and Swift installed, open a terminal in the project folder and run:

```bash
./scripts/run.sh
```

This builds the app, creates `work/IR2Studio.app`, signs it for local use, checks the signature, and opens its window. Quit any running copy before launching a new build.

To build without opening the app:

```bash
./scripts/run.sh --build-only
```

The generated files in `work/` are excluded from Git. This local build is not signed for distribution or notarized by Apple.

You can also open `Package.swift` in Xcode or run `swift run`. To browse or edit the source in VS Code, open the project folder.

### Create download packages

Run `./scripts/package-preview.sh` to build an optimized Apple Silicon app and produce a ZIP, DMG, and SHA-256 checksums in `dist/`. These are free preview packages with a local signature, **not Apple notarization**. They include [installation instructions](docs/INSTALL.txt). Generated downloads stay outside Git; they can be attached to a GitHub Release. The download names include the app version and preview build number. See the [preview release notes](docs/releases/v0.1.0-preview.2.md).

The packaging script replaces local source paths with `/IR2Studio`, removes debug records from the copied executable before signing, and checks the payload and extracted ZIP for local user or project paths. Intermediate build files remain in `work/` and are not distributed.

## Connect your pedal

1. Install the BOSS IR-2 driver for macOS, set the pedal’s USB mode to **VENDOR**, and connect it to your Mac with a USB cable.
2. Open **My IR-2 (`Meu IR-2`)**. The app tries to connect in read-only mode. Use **Connect (`Conectar`)** to try again or **Disconnect (`Desconectar`)** to end the connection.
3. The app reads both channels once when it connects, then applies changes reported by the pedal in real time. There is **no periodic polling or screen reload**. The time shown is the last successful reading or changed value. **Refresh (`Atualizar`)** requests a full reading when needed.
4. Select the Green or Red card to inspect that channel. **Selected (`SELECIONADO`)** marks the channel reported by the pedal. Selecting a card alone does not switch the pedal.
5. Turn on **Edit pedal (`Editar pedal`)** to adjust Gain, Bass, Middle, Treble, Level, Ambience, and the amp model. Use **Select Green/Red (`Selecionar Verde/Vermelho`)** to change the selected channel. This does not turn the effect on or take it out of bypass.
6. Choose **Save as preset (`Salvar como preset`)** to capture the exact settings of both channels. Saving a preset does not change the pedal.

Editing starts disabled each time you connect. The six controls use values from **0 to 127**; the 11 amp models use internal values from **0 to 10**.

Rapid adjustments are combined, with a 180 ms delay after the last change. The app reads each value back from the pedal to confirm it was received. If that check fails, the app marks the displayed settings as out of date and disables editing. Refresh the settings and turn editing back on to continue. Reconnecting does not resend pending changes.

The current edit buffer is separate from each channel’s stored settings. The app checks and updates both when needed. It also checks that the edit buffer matches the selected channel after a switch. These checks confirm parameter values; they do not confirm the physical LED or audible output. Avoid switching channels on the pedal during an update: changes made on the pedal and in the app cannot be applied as a single operation.

### Is the effect on?

The app does **not yet read or control the effect’s on/bypass state**. A USB connection and a selected channel do not mean the effect is on. Check the pedal’s CHECK indicator: green/red indicates the effect is on, while an unlit indicator can mean bypass. Use the physical pedal switch to turn the effect back on when it is in bypass. See the [BOSS IR-2 Owner’s Manual](https://static.roland.com/assets/media/pdf/IR-2_eng03_W.pdf).

## Manage presets

- **New preset (`Novo preset`)** creates a preset stored on your Mac. Changes in the local preset editor are not sent to the pedal automatically.
- **Save as preset (`Salvar como preset`)** on the pedal screen captures both channels using their exact 0–127 values.
- **Export (`Exportar`)** saves a preset as a JSON file—a text file containing its settings. **Import preset JSON (`Importar preset JSON…`)** adds a copy to your library.
- In the local editor, the button next to Export applies **both channels** to the pedal. It is available only when pedal editing is enabled and no other operation is running. Each setting is read back for confirmation. If an update fails, some settings may already have changed; the app stops sending and asks you to refresh.
- Your library is stored at `~/Library/Application Support/IR2Studio/presets.json`.

Your personal library is not included in Git or download packages. The JSON files in `Presets/` are deliberately shared examples, including the *Someday* preset. Local `.alb` backups, copies named `presets.json`, credential files, and signing identities are ignored by Git to help prevent accidental commits. Ignore rules do not remove files that were already committed.

Preset JSON files use IR-2 Studio’s own format. They cannot be used to restore the pedal through the official IR Loader.

The [example presets](Presets/README.md) include a CLEAN / BRIT starting point inspired by Nickelback's *Someday*, with suggestions for an external Tone Ink Cold Shot overdrive.

### Presets from the earlier prototype

Older presets keep their original 0–100 scale, shown in the editor. When you apply them to the pedal, the values are converted to 0–127. If an older file has no Ambience setting, it defaults to 50 on its original scale.

The old amp labels `TWD` and `ACOUSTIC` are converted to `TWEED` and `CLEAN`. `ACOUSTIC` was a prototype label, not an IR-2 amp model.

## View official `.alb` backups

Choose **Open backup (`Abrir backup .alb…`)** in the sidebar. The viewer shows the selected channel, both Gain values, and the underlying channel parameters. Click the filename in the sidebar to reopen the last backup you loaded.

This is a snapshot of the file, not a live reading. Opening a backup does not change the file, your preset library, or the pedal. The reader checks the fields needed for display; it does not validate the cabinet impulse responses (IRs) or determine whether a file is safe to restore.

## Appearance and controls

At the bottom of the sidebar, choose **System (`Sistema`)**, **Light (`Claro`)**, or **Dark (`Escuro`)**. Your choice is remembered between launches. System follows your Mac’s appearance; Light and Dark affect only IR-2 Studio.

Drag the knobs to adjust values, or use the sliders below them. Sliders also support keyboard navigation.

## Testing and technical details

```bash
swift build
swift test
```

The integration was tested with a connected IR-2, including:

- Reading both channels.
- Changing Green channel Gain from 0 to 1 and back to 0, checking both the stored value and the current edit buffer.
- Switching from Green to Red and back to Green, checking the channel selection and edit buffer after each switch. These were data checks, not physical LED or listening tests.
- Capturing and applying a two-channel preset, then disconnecting and reconnecting.

Automated tests cover backup parsing, device identification, message integrity checks, MIDI messages split across packets, response timeouts, cancellation, queued edits, reconnection, failed readback checks, compatibility with older presets, and event updates without background reloads.

See [USB protocol notes](docs/USB.md) for sources, addresses, and hardware test results. That technical document is currently in Portuguese.

The numeric parameter scale does not imply a linear change in sound. MIDI updates do not measure how long the pedal takes to save settings permanently.

## Current limits

The app does not update firmware, perform factory resets, restore full backups, or load cabinet IRs.

IR-2 Studio is an independent project and is not an official BOSS or Roland product.

## Source code guide

The app icon and its generation prompt are in `Resources/`. To rebuild the macOS icon after replacing `Resources/AppIcon.png`, run `./scripts/build-icon.sh`, then rebuild the app. The icon script uses the macOS tools `sips` and `iconutil`.

| File | Purpose |
|---|---|
| `IR2Protocol.swift` | MIDI SysEx messages, validation, and parameter definitions |
| `IR2MIDITransport.swift` | Core MIDI connections and incoming data |
| `IR2Session.swift` | Requests, timeouts, reading, and verified writing |
| `PedalStore.swift` | Connection state, automatic refresh, and queued changes |
| `LivePedalView.swift` | Controls for the connected pedal |
| `IR2Backup.swift` / `BackupView.swift` | Reading and displaying `.alb` backups |
| `Preset.swift` / `PresetStore.swift` | Preset library and compatibility with older files |
| `ContentView.swift` / `StudioStyle.swift` | Navigation, local editor, and themes |
