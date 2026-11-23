# Windows installer

`church-service-timer.iss` is the [Inno Setup](https://jrsoftware.org/isinfo.php) script that `scripts/Package-Windows.ps1` runs. It installs for the current user by default, adds Start menu and optional desktop shortcuts, and upgrades in place (same `AppId`).

## The look

With Inno Setup **6.6 or newer** (`#if VER >= 0x06060000`; the script then defines `Cinematic`) the setup window is dark and has artwork:

| Page | What shows |
|---|---|
| Welcome | Tall picture (the stage clock, ring and app icon), a two-line plain explanation, and an honest note that the installer is not code-signed. |
| Inner pages (folder, tasks, ready) | The app icon as a small picture at the top right. |
| Installing | Six scenes in a wide strip above the progress bar, with a caption under each: the countdown, the red over-time screen, the flip clock, Slides, phones and web screens, the looks. The scene changes as the copy passes each sixth (`CurInstallProgressChanged`); it is a plain cut, not a fade. |
| Finished | Its own tall picture (a closed ring and tick), "Church Service Timer is ready", the launch tick box and the guide address. |

With an older compiler the script builds the plain modern wizard it had before. If a picture cannot be loaded at run time, the slideshow or the finished picture is skipped and the wizard stays as setup draws it. A `/SILENT` or `/VERYSILENT` install runs none of the picture code (`WizardSilent`). The in-app **Download and install** starts the installer with no arguments, so it shows these pages like a double-click.

Nothing about what is installed, where, or how upgrades and uninstalls behave depends on the artwork.

## The pictures

All are in `art/`, drawn by `tool/make_installer_art.py` from the app's fonts and icon (`assets/fonts`, `play/graphics/icon-512.png`) and screenshots in `test/goldens` (the song slide uses a CC0 photo credited in `docs/LYRICS-PHOTOS.md`). Nothing is downloaded and the script uses no random numbers, so it gives the same files every time.

```
pip install pillow numpy
python3 tool/make_installer_art.py
```

| Files | Size | Used for |
|---|---|---|
| `welcome-220/331/441/551.png` | 164:314 proportion, 220 to 551 px wide | `WizardImageFile`, Welcome page. Setup picks the smallest that fits, so 100% to 250% Windows scaling stays sharp. |
| `ready-220/331/441/551.png` | same | Finished page, chosen in `[Code]` by the picture area's width. |
| `header-64/80/96/128/160.png` | square, transparent corners | `WizardSmallImageFile`. |
| `scene-1.png` to `scene-6.png` | 1000 x 333 | The slideshow, unpacked from the installer at start (`dontcopy`). |

The tall pictures and scenes are 256-colour PNGs to keep the installer small (about 1.1 MB for everything). `test/repo/installer_script_test.dart` checks every file the script names exists with the right size.

## Previews

`python3 tool/make_installer_preview.py <folder>` draws mock-ups of each page from these files and the words in the script. They are previews, not screenshots: the window frame, fonts, dark colours and the window size at each Windows scale are approximations.

## Compiler version

CI installs Inno Setup with `choco install innosetup` and does not pin a version, so it gets the newest release. The new look needs 6.6 or newer. Features used: PNG wizard images and a list of files per image directive (6.5 and 6.1), `WizardStyle=modern dark` (6.6), `TBitmapImage.PngImage`, `MulDiv`, `WizardSilent`, `ExtractTemporaryFile`, `CurInstallProgressChanged` (fixed in 6.5.4). Nothing has been compiled yet: the first proof is a test build on GitHub (**Actions › Build and test › Run workflow**, Windows on), then running the installer once.
