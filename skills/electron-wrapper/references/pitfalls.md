# Pitfalls & Gotchas

Every known issue encountered when wrapping a Bun web app in Electron, with symptoms and proven solutions.

---

## 1. ESM vs CJS Module Conflicts

**Problem:** Modern npm packages (`get-port`, `electron-store`) are ESM-only, but Electron's Node.js environment defaults to CommonJS.

**Symptoms:**
```
Error [ERR_REQUIRE_ESM]: require() of ES Module .../get-port/index.js not supported
```

**Solution:** Add `"type": "module"` to `electron/package.json` so Node.js treats `.js` files as ESM:
```json
{
  "type": "module",
  "main": "dist/main/index.js"
}
```

**Gotcha within the gotcha:** Some packages like `electron-updater` are still CJS. When importing from an ESM context, use the default import pattern:
```typescript
// Fails — named import from CJS module in ESM context
import { autoUpdater } from "electron-updater";

// Works — default import, then destructure
import electronUpdater from "electron-updater";
const { autoUpdater } = electronUpdater;
```

---

## 2. Preload Scripts Must Be Bundled as a Single CJS File

**Problem:** Electron's sandboxed preload scripts use a restricted `preloadRequire` that can **only** load built-in Electron modules (`electron`, `events`, `timers`, `url`). Multi-file CJS with relative `require()` calls will fail at runtime — even though `tsc` compiles it successfully.

**Symptoms:**
```
Unable to load preload script: /path/to/preload/index.js
Error: module not found: ../shared/types.js
```
Or, if not using sandbox:
```
SyntaxError: Cannot use import statement outside a module
```

**Solution:** Use **esbuild** to bundle the preload into a single CJS file with `electron` as an external:

```json
{
  "scripts": {
    "build:preload": "esbuild src/preload/index.ts --bundle --platform=node --format=cjs --outfile=dist/preload/index.js --external:electron"
  }
}
```

This inlines all local imports (shared types, constants) into one file while keeping `require("electron")` as a runtime dependency that the sandbox can resolve.

**Why not tsc?** Even with `"module": "CommonJS"` in tsconfig, tsc produces multiple output files with `require("../shared/types.js")` calls. The sandboxed preload's restricted require cannot resolve these paths.

**Keep tsc for type checking only:**
```json
{
  "scripts": {
    "typecheck": "tsc -p tsconfig.main.json --noEmit && tsc -p tsconfig.preload.json --noEmit"
  }
}
```

The preload tsconfig still needs `"module": "CommonJS"` for accurate type checking:
```json
// tsconfig.preload.json
{
  "compilerOptions": {
    "module": "CommonJS",
    "moduleResolution": "Node",
    "outDir": "dist/preload",
    "rootDir": "src"
  }
}
```

The main process tsconfig stays ESM:
```json
// tsconfig.main.json
{
  "compilerOptions": {
    "module": "NodeNext",
    "moduleResolution": "NodeNext",
    "outDir": "dist/main",
    "rootDir": "src/main"
  }
}
```

---

## 3. `__dirname` Unavailable in ESM

**Problem:** ESM modules don't have `__dirname` or `__filename` globals. Many Electron patterns rely on `__dirname` for resolving paths to preload scripts, assets, and resources.

**Symptoms:**
```
ReferenceError: __dirname is not defined
```

**Solution:** Reconstruct from `import.meta.url`:
```typescript
import path from "path";
import { fileURLToPath } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
```

Add this polyfill at the top of every main process file that needs path resolution.

---

## 4. Dev Mode MIME Type Errors

**Problem:** Running Electron's internal Bun server alongside the web dev server causes module serving issues. The bundled server serves built assets, not the dev server's HMR-enhanced modules.

**Symptoms:**
```
Failed to load module script: Expected a JavaScript module script but the server responded with a MIME type of "text/html"
```

**Solution:** In dev mode, don't start the internal Bun server. Instead, connect Electron to the external dev server via an environment variable:

```typescript
// main/index.ts
const DEV_SERVER_URL = process.env.ELECTRON_DEV_URL;
const isDev = !!DEV_SERVER_URL;

async function getServerPort(): Promise<number> {
  if (isDev && DEV_SERVER_URL) {
    const url = new URL(DEV_SERVER_URL);
    return parseInt(url.port, 10) || 3000;
  }
  return startServer(); // production: spawn bundled Bun
}
```

Dev script uses `concurrently` + `wait-on`:
```json
{
  "scripts": {
    "dev": "concurrently \"npm run dev:web\" \"npm run dev:electron\"",
    "dev:web": "cd .. && bun run dev",
    "dev:electron": "wait-on http://localhost:3005 && npm run build && ELECTRON_DEV_URL=http://localhost:3005 electron ."
  }
}
```

---

## 5. Bun Version Must Match Features

**Problem:** The bundled Bun binary must support the same APIs your server uses. Older versions may lack features like the `routes` API in `Bun.serve()`.

**Symptoms:**
```
TypeError: Expected fetch() to be a function
```
(Or other cryptic errors from missing API support.)

**Solution:** Pin the Bun version in your download script and keep it aligned with your development version:
```typescript
const BUN_VERSION = "1.2.5"; // must support your server's API surface
```

Re-download when updating:
```bash
bun scripts/download-bun.ts --current --force
```

---

## 6. nvm/Node.js PATH Issues in Spawned Processes

**Problem:** When spawning child processes from Electron or test scripts, `node`/`npm` may not be found if using nvm with lazy shell loading.

**Symptoms:**
```
env: node: No such file or directory
```

**Solution:** For test scripts and build tooling, use `bash -lc` to run commands through a login shell that loads nvm:
```typescript
const proc = spawn({
  cmd: ["bash", "-lc", command],
  cwd: projectDir,
  stdout: "pipe",
  stderr: "pipe",
});
```

This isn't an issue in production since Electron bundles its own Node.js and you bundle the Bun binary.

---

## 7. Storage Paths (CWD Is Wrong in Packaged Apps)

**Problem:** Web apps commonly store data relative to `process.cwd()`, but packaged Electron apps have an unpredictable CWD (often `/` or the app bundle path).

**Symptoms:** Data files written to unexpected locations, data not persisting between launches, or permission errors writing to read-only directories.

**Solution:** Make storage paths configurable via environment variable, defaulting to CWD for web mode:

```typescript
// In your server's storage module
const DATA_DIR = process.env.APP_DATA_DIR || process.cwd();
const DATA_FILE = path.join(DATA_DIR, ".app-data.json");
```

Set the env var when spawning the Bun server from Electron:
```typescript
serverProcess = spawn(bunPath, ["run", serverPath, "--port", String(port)], {
  env: {
    ...process.env,
    APP_DATA_DIR: app.getPath("userData"), // ~/Library/Application Support/AppName
  },
});
```

---

## 8. White Flash on Window Open

**Problem:** BrowserWindow shows a white rectangle before the web content loads, creating a jarring flash — especially in dark-themed apps.

**Symptoms:** Brief white flash visible when launching the app or creating new windows.

**Solution:** Combine three techniques:

```typescript
const mainWindow = new BrowserWindow({
  show: false,                    // 1. Don't show immediately
  backgroundColor: "#0a0a0a",    // 2. Match your app's background color
  // ...
});

mainWindow.once("ready-to-show", () => {
  mainWindow.show();             // 3. Show only when content is painted
});
```

Choose a `backgroundColor` that matches your app's default theme (dark or light).

---

## 9. Dev Server Port Mismatch

**Problem:** Electron's dev URL defaults to `localhost:3000`, but the web app's dev server may run on a different port (configured in `package.json` or `.env`).

**Symptoms:**
```
Failed to load URL: http://localhost:3000/login with error: ERR_CONNECTION_REFUSED
```

**Solution:** Before setting constants, check the web app's actual dev port in its `package.json` dev script or `.env` file. Common patterns:
```json
"dev": "next dev -p 3010"
"dev": "vite --port 5173"
```

Match this in Electron's constants:
```typescript
export const URLS = {
  PRODUCTION: "https://www.yourapp.com",
  DEVELOPMENT: "http://localhost:3010", // Must match web app's dev port
};
```

---

## 10. Do NOT Use BrowserView

**Problem:** `BrowserView` was deprecated in Electron 30 and removed in later versions. It also doesn't receive the preload script from the parent BrowserWindow, so `window.electron` will be undefined.

**Symptoms:** `window.electron` is undefined in the web app even though the preload compiles correctly. Or deprecation warnings/errors on newer Electron versions.

**Solution:** Load the web app URL directly in the `BrowserWindow` via `mainWindow.loadURL()`. The BrowserWindow already has the preload configured in its `webPreferences`, so `contextBridge.exposeInMainWorld()` works correctly.

```typescript
// Wrong — BrowserView doesn't inherit preload from parent window
const view = new BrowserView({ webPreferences: { /* no preload */ } });
mainWindow.setBrowserView(view);
view.webContents.loadURL(appUrl);

// Right — load directly in the BrowserWindow
mainWindow.loadURL(appUrl);
```

---

## 11. electron-builder `${platform}` !== Node.js `process.platform`

**Problem:** electron-builder's `${platform}` macro resolves to `mac`/`linux`/`win`, but Node.js (and the Bun download script) uses `darwin`/`linux`/`win32`. If you use `${platform}` in `extraResources` paths for the Bun binary, the path won't match the actual directory and the binary silently won't be bundled.

**Symptoms:**
```
Error: spawn /Applications/Your App.app/Contents/Resources/bun/bun ENOENT
```
The app starts, tries to spawn the Bun server, but the binary is missing from the packaged app. Locally-built dev mode works fine since it uses a different code path.

**Solution:** Put the Bun `extraResources` entry in platform-specific sections with hardcoded platform prefixes:

```yaml
# Wrong — ${platform} resolves to "mac", not "darwin"
extraResources:
  - from: ../resources/bun/${platform}-${arch}/
    to: bun/

# Right — use platform-specific sections with correct prefixes
mac:
  extraResources:
    - from: ../resources/bun/darwin-${arch}/
      to: bun/

win:
  extraResources:
    - from: ../resources/bun/win32-${arch}/
      to: bun/
```

Platform-independent resources (server bundle, web app dist) can stay in the top-level `extraResources`.
