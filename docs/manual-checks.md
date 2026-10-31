# Manual release checks

These checks need a real desktop or a disposable macOS system.

Finder Services, **Repair Command Line Tool**, the clean-volume pkg install,
and the zip first launch are release gates for 0.2.0.

The Dock drag-and-drop checks (sections 1 to 4) are **work in progress**. The
Dock path is experimental and not a gate for 0.2.0. Keep the steps for when
that path is finished.

Run them against the 0.2.0 artifacts:

- `dist/AES Open Crypt 0.2.0.pkg` — primary install
- `dist/AES Open Crypt 0.2.0.zip` — portable install
- `dist/AES Open Crypt.app` — built app

## Setup

```bash
mkdir -p ~/Desktop/aes-manual
cd ~/Desktop/aes-manual
for i in $(seq 1 11); do printf 'file %s\n' "$i" > "f$i.txt"; done
printf 'secret\n' > secret.txt
shasum -a 256 *.txt > before.sha
```

Install the app and launch it once. For the WIP Dock checks, right-click its
Dock icon and choose **Options → Keep in Dock**. The app quits after the last
window closes by design.

## 1. Dock drop: one file (WIP)

1. Quit the app.
2. Drag `secret.txt` onto the Dock icon.
3. Enter a password twice and click Start.

Expected: the app opens with one Encrypt row; the row succeeds;
`secret.txt.aes` appears next to the input; `shasum -a 256 secret.txt`
matches `before.sha`.

4. Quit. Drag `secret.txt.aes` onto the Dock icon.

Expected: Decrypt is preselected. Because `secret.txt` already exists, the
output is `secret (1).txt` (the app never overwrites).

## 2. Dock drop: five and ten files (WIP)

1. Drag `f1.txt` through `f5.txt` onto the Dock icon.
2. Start with one password.

Expected: five rows, all succeed, five `.aes` files, inputs unchanged.

3. Repeat with all ten `f1.txt` through `f10.txt`.

Expected: ten rows, all succeed. No file is skipped.

## 3. Dock drop: eleven files (WIP)

1. Drag all eleven files onto the Dock icon.

Expected: one message, **Maximum of 10 files at a time is allowed.**; no rows are added; no
output files are created.

```bash
find ~/Desktop/aes-manual -name '*.aes' -print
```

## 4. Drop while a batch is running (WIP)

1. Start an encrypt batch with a large file (200 MB or more) so there is
   time to act.
2. While progress is moving, drag another file onto the window or the Dock
   icon.

Expected: the notice **Finish the current batch first.**; the running batch
is untouched; the new file is not added; the current batch finishes normally.

3. Repeat with eleven files while the batch is running.

Expected: the same notice, no partial loss.

## 5. Finder Services

1. Launch the app once so macOS registers its services.
2. Select one or more files in Finder.
3. Right-click → **Services** → **Encrypt with AES Open Crypt**.
4. Repeat with `.aes` files and **Decrypt with AES Open Crypt**.

Expected: the app opens with the selection as a batch in the chosen mode.

If the items are missing from the Services menu: **System Settings → Keyboard
→ Keyboard Shortcuts → Services** and enable them.

5. Select a plain file and an `.aes` file, then choose the Encrypt service.

Expected: both rows appear; the `.aes` row says it is already encrypted;
Start is disabled. Nothing runs.

## 6. Repair Command Line Tool

Check the current link:

```bash
readlink /usr/local/bin/aesopen
/usr/local/bin/aesopen --version
```

**Missing link:** remove it, launch the app, then **AES Open Crypt → Repair
Command Line Tool**.

```bash
sudo rm /usr/local/bin/aesopen
```

Expected: an alert says the tool was repaired; `readlink` points into
`AES Open Crypt.app/Contents/Resources/bin/aesopen`.

**Moved app:** move the app to another folder, launch it from there, and
repair. Expected: the link points at the new location.

**Unrelated file:** create a decoy, then repair.

```bash
printf '#!/bin/sh\necho unrelated\n' | sudo tee /usr/local/bin/aesopen
sudo chmod +x /usr/local/bin/aesopen
```

Expected: an alert says the path cannot be replaced; the decoy keeps its
contents. Remove the decoy afterwards.

**Non-writable `/usr/local/bin`:** make it read-only and repair.

```bash
sudo chmod 555 /usr/local/bin
```

Expected: the app asks for administrator privileges, then creates the link.
Restore with `sudo chmod 775 /usr/local/bin`.

## 7. Clean-volume pkg install

Use a macOS VM (UTM, Parallels, or VMware) or a spare Mac. Do not test this
over the working install.

1. Copy `AES Open Crypt 0.2.0.pkg` to the clean system.
2. Double-click it. If Gatekeeper blocks the unsigned package, right-click
   it and choose **Open**, or run:

   ```bash
   sudo installer -pkg "AES Open Crypt 0.2.0.pkg" -target /
   ```

3. Verify:

   ```bash
   pkgutil --pkg-info dev.aesopencrypt.pkg
   ls -l "/Applications/AES Open Crypt.app/Contents/Resources/bin/aesopen"
   readlink /usr/local/bin/aesopen
   aesopen --version
   ```

Expected: the app is in `/Applications`; the symlink exists;
`aesopen --version` prints `aesopen 0.2.0`.

4. Conflict test: put an unrelated file at `/usr/local/bin/aesopen`, then
   install again. Expected: the install succeeds, the app is installed, and
   the unrelated file is left untouched.

## 8. Zip first launch on a clean account

Create a temporary **Standard** user in **System Settings → Users & Groups**.
Log in as that user, unzip the portable build, and put the app in
`~/Applications` (a standard user cannot write `/Applications` without
authorization).

Launch the app. Expected, in order:

1. If `/usr/local/bin` is writable: the link is created and
   `aesopen --version` works.
2. Otherwise, if `~/.local/bin` is writable and on `PATH`: the link is
   created there.
3. Otherwise: one alert with the exact `sudo mkdir -p ... && sudo ln -sfn ...`
   command; the app still opens.

To force case 2 on an admin account:

```bash
sudo chmod 555 /usr/local/bin
mkdir -p ~/.local/bin
# make sure ~/.local/bin is on PATH, then launch the app
```

Restore with `sudo chmod 775 /usr/local/bin`. Delete the temporary user
afterwards.

## 9. Intel Mac (x86_64)

The 0.2.0 artifacts are universal (`arm64` + `x86_64`). This check needs an
Intel Mac with macOS 13 or later. It is the only way to test the native
`x86_64` slice and AES Crypt 3.14, which is Intel-only.

1. Transfer both artifacts and check the hashes:

   ```bash
   shasum -a 256 "AES Open Crypt 0.2.0.pkg" "AES Open Crypt 0.2.0.zip"
   ```

   Expected:

   ```
   c3c15b2ca3bc3b7bd9ab1559e7e2ea0838f9891b5e3b00b53f83b4025e866891  AES Open Crypt 0.2.0.pkg
   adb45a257f9971e4659f4ab079489022b2b75e88644877bbb0b144eb9d4ed9f0  AES Open Crypt 0.2.0.zip
   ```

2. Install the package. If Gatekeeper blocks it, right-click and choose
   **Open**, or run:

   ```bash
   sudo installer -pkg "AES Open Crypt 0.2.0.pkg" -target /
   ```

3. Verify the install and the architecture:

   ```bash
   pkgutil --pkg-info dev.aesopencrypt.pkg
   lipo -archs "/Applications/AES Open Crypt.app/Contents/MacOS/AESOpenCrypt"
   lipo -archs "/Applications/AES Open Crypt.app/Contents/Resources/bin/aesopen"
   readlink /usr/local/bin/aesopen
   aesopen --version
   ```

   Expected: both `lipo` lines print `x86_64 arm64`; the link points into
   `/Applications/AES Open Crypt.app`; the version prints `aesopen 0.2.0`.

4. CLI round trip and AES Crypt 3.14 cross-check:

   ```bash
   printf 'intel test\n' > /tmp/intel.txt
   aesopen encrypt --password test --format v2 -o /tmp/intel.aes /tmp/intel.txt
   aesopen decrypt --password test -o /tmp/intel.out /tmp/intel.aes
   cmp /tmp/intel.txt /tmp/intel.out

   /Applications/AESCrypt.app/Contents/MacOS/aescrypt \
       -d -p test -o /tmp/intel.314.txt /tmp/intel.aes
   cmp /tmp/intel.txt /tmp/intel.314.txt
   ```

   Expected: both `cmp` commands are silent. `--format v2` is explicit here
   because AES Crypt 3.14 cannot read format 3; the CLI default is v3.

5. Zip first launch: quit the app, unzip the portable build, move it to
   `~/Applications`, and launch it. Follow the expected link behavior in
   section 8.

## 10. UI appearance and window behavior

Run on a real desktop in both light and dark mode (System Settings → Appearance).

1. **First launch.** Clear the app's preferences and saved state, then launch:

   ```bash
   defaults delete dev.aesopencrypt.app 2>/dev/null
   rm -rf "$HOME/Library/Saved Application State/dev.aesopencrypt.app.savedState"
   ```

   Expected: a 600×660 window, centered, with no title bar strip and no window
   title. The traffic lights float over the top-left; the header starts 32pt
   below the window top. Nothing is clipped.

2. **Resize.** Drag any window edge or corner, and use the green traffic
   light. Expected: the window resizes freely above its minimum (about
   520×620 of content); the file list grows and scrolls; the form and footer
   stay visible. Quit and relaunch: the resized frame is restored.

3. **Drag the window.** Click an empty part of the background and drag.
   Expected: the window moves without a title bar.

4. **Palette.** In light and dark mode, check the header, password fields,
   format picker, primary button, status pills, and footer. Expected: a deep
   muted teal accent, no stock bright blue, readable secondary text, and
   visible borders. The row remove button is a muted red and the success
   check a brighter green. Hover the question mark next to **Format** to see
   the v2/v3 explanation. Run `swift test --filter ThemePaletteTests` to check
   the contrast floors.

5. **Batch states.** Check each state in both modes: empty; one file; ten
   files; mixed batch (mode picker); working with percent; cancel; finished
   with the summary (the summary row with **Show in Finder** and **Done**
   sits between the file card and the password fields); weak password (an
   amber suggestion under the password field, and **Encrypt** stays enabled);
   wrong password (error and a **Retry** button under the password field, no
   summary row; press Return after typing the password to retry); corrupt
   file (amber issue text); invalid `.aes`; eleven files (**Maximum of 10
   files at a time is allowed.**). On a fresh launch the Format picker starts
   on **Strong (v3)**; choosing **Compatible (v2)** persists after quit and
   relaunch.

6. **Accessibility.** With VoiceOver, the eye buttons announce **Show
   password** / **Hide password**, the row remove button announces **Remove
   <file name>**, and the success and failure icons announce **Finished**,
   **Failed**, or **Wrong password**. Enable **Increase Contrast**, **Reduce
   Transparency**, and **Reduce Motion**: text stays readable, and the drop
   target and row hover changes are instant or subtle.

7. **Long content.** Use a long file name and the longest error or issue
   message. Expected: names truncate in the middle, messages wrap, and
   nothing is clipped at the minimum window size.

## What to report

For each check: pass or fail, macOS version, app version, the exact message
text, a screenshot, and:

```bash
ls -l /usr/local/bin/aesopen
readlink /usr/local/bin/aesopen
aesopen --version
```

For a failure, add the Console.app log filtered by `AESOpenCrypt` and the
steps that led to it.

## What can be automated

`open -a "AES Open Crypt.app" <files>` exercises the same open handler as a
Dock drop. It can check the 1/5/10/11-file limits and the drop-while-working
notice without dragging. It does not test the Dock drag path, the Services
menu, or the Repair alert. The Dock drag path is work in progress.
