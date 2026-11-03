# MSFS 2024 GPU memory warning patch

Stops Microsoft Flight Simulator 2024 from showing this toast every few seconds:

> Resource usage exceeds GPU memory capacity, lower graphics settings for better performance

Only this one notification is removed, and its sound with it. Every other notification still appears.

## Usage

1. Download `gpu-warning-patch-vX.Y.Z.zip` from [Releases](../../releases/latest) and extract it.
2. Close the sim, open PowerShell in the extracted folder and run:

```powershell
.\Patch-GpuMemWarning.ps1                       # apply
.\Patch-GpuMemWarning.ps1 -Revert               # undo, restoring the original files
.\Patch-GpuMemWarning.ps1 -GameDir "D:\MSFS2024"   # if your install isn't found automatically
```

If PowerShell refuses to run the script, start it with `powershell -ExecutionPolicy Bypass -File .\Patch-GpuMemWarning.ps1`.

**Re-run it after every sim update.** Updates replace the patched files. It's safe to run any number of times: files that are already patched are skipped. If an update changes the code the patch looks for, the script stops with an error and changes nothing.

### Finding the install

- **Microsoft Store / Xbox app:** found automatically, including installs moved to another drive.
- **Steam:** found by searching your Steam libraries. This route hasn't been tested yet. If the script can't find the UI files, pass `-GameDir`.

## How it works

The sim raises the warning from native code. It reaches the UI as an ordinary notification (text key `SYSTEM.NOTIF_LOW_GPU_MEMORY_CAPACITY_DESC`), which the notifications page's JavaScript turns into a toast.

The script adds one guard to the start of `NewNotification` and `UpdateNotificationData` in `Packages\fs-base-ui\html_ui\Global\lib.js` and `lib.bundle.js`:

```js
/*nogpuwarn*/if(/LOW_GPU_MEMORY|exceeds GPU memory/i.test(JSON.stringify(t)))return;
```

- **Any language.** It matches the text key, so it works whatever language the sim uses. The English text is a fallback.
- **No toast, no sound.** It returns before the toast is created and before the sound plays.
- **Backed up.** Each file is saved next to itself as `*.orig` before the first edit, and `-Revert` puts those back.
- **Harmless to the package.** These UI files aren't in the package's file manifest, so editing them doesn't trip its integrity checks.

### Why not something else

| Approach | Problem |
|---|---|
| Patch the executable | The Store build is encrypted on disk, and offsets change with every update |
| Fake a bigger VRAM budget | Hides the warning, but the engine then overcommits VRAM and stutters more |
| Replace the notification layout | Hides every system notification, not just this one |
| Blank the text string | The toast still appears, just empty |

## Debugging the UI yourself

The sim runs the Coherent GT inspector on port 19999:

- `http://127.0.0.1:19999/pagelist.json` lists the live UI pages.
- `http://127.0.0.1:19999/inspector/Main.html?page=N` opens an inspector for page N.

`PageAgent.getResourceTree` shows which scripts a page really loads; the in-game notifications page uses `lib.js`, not `lib.bundle.js`. `PageAgent.reload.invoke({ignoreCache: true})` reloads one page without restarting the sim.

## License

[MIT](LICENSE)
