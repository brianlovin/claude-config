# Main Process

Annotated implementation patterns for each Electron main process file.

---

## src/main/index.ts — App Entry Point

The entry point handles app lifecycle, dev/production mode switching, single-instance locking, and IPC registration.

```typescript
import path from "path";
import { fileURLToPath } from "url";
import { app, ipcMain } from "electron";
import log from "electron-log";
import { startServer, stopServer } from "./bun-server.js";
import { createWindow, getMainWindow } from "./window.js";
import {
  setupAutoUpdater,
  checkForUpdates,
  downloadUpdate,
  installUpdate,
} from "./updater.js";

log.transports.file.level = "info";
log.info("App starting...");

// ESM __dirname polyfill (see pitfalls §3)
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Dev mode: connect to external dev server instead of spawning Bun
const DEV_SERVER_URL = process.env.ELECTRON_DEV_URL;
const isDev = !!DEV_SERVER_URL;

let appPort: number | null = null;

async function getServerPort(): Promise<number> {
  if (isDev && DEV_SERVER_URL) {
    log.info("Dev mode: connecting to", DEV_SERVER_URL);
    const url = new URL(DEV_SERVER_URL);
    return parseInt(url.port, 10) || 3000;
  }
  return startServer();
}

// Single-instance lock — prevent multiple windows fighting over the server
const gotLock = app.requestSingleInstanceLock();

if (!gotLock) {
  log.info("Another instance is running, quitting...");
  app.quit();
} else {
  // Focus existing window when user tries to open a second instance
  app.on("second-instance", () => {
    const window = getMainWindow();
    if (window) {
      if (window.isMinimized()) window.restore();
      window.focus();
    }
  });

  app.whenReady().then(async () => {
    try {
      appPort = await getServerPort();
      createWindow(appPort);

      // Auto-updater only in packaged builds
      if (app.isPackaged) {
        setupAutoUpdater();
        setTimeout(() => checkForUpdates(), 5000); // delay avoids startup congestion
      }
    } catch (error) {
      log.error("Failed to start app:", error);
      app.quit();
    }
  });

  // macOS: re-create window when dock icon clicked
  app.on("activate", () => {
    if (!getMainWindow() && appPort) {
      createWindow(appPort);
    }
  });

  // Non-macOS: quit when all windows closed
  app.on("window-all-closed", () => {
    if (process.platform !== "darwin") {
      app.quit();
    }
  });

  // Clean up Bun server on quit (skip in dev — we didn't start it)
  app.on("before-quit", () => {
    if (!isDev) {
      stopServer();
    }
  });

  // IPC handlers for renderer → main communication
  ipcMain.handle("update:check", () => checkForUpdates());
  ipcMain.handle("update:download", () => downloadUpdate());
  ipcMain.handle("update:install", () => installUpdate());
  ipcMain.handle("app:version", () => app.getVersion());
}
```

### Key patterns:
- **Dev URL detection** via environment variable — never start the internal server in dev mode (see pitfalls §4)
- **Single-instance lock** prevents port conflicts when user double-launches
- **Store port at app level** — resolve once, reuse in `activate` handler instead of re-entering `startServer()`
- **Delayed update check** (`setTimeout 5s`) avoids competing with app startup
- **IPC handlers** registered at top level, available regardless of window state

---

## src/main/bun-server.ts — Server Spawning

Manages the lifecycle of the bundled Bun server process.

```typescript
import { spawn, type ChildProcess } from "child_process";
import path from "path";
import { app } from "electron";
import log from "electron-log";
import getPort from "get-port";

let serverProcess: ChildProcess | null = null;
let currentPort: number | null = null;

function getBunPath(): string {
  const platform = process.platform;
  const arch = process.arch === "arm64" ? "arm64" : "x64";
  const platformArch = `${platform}-${arch}`;
  const bunExecutable = platform === "win32" ? "bun.exe" : "bun";

  if (app.isPackaged) {
    // In packaged app: resources are in process.resourcesPath
    return path.join(process.resourcesPath, "bun", bunExecutable);
  }

  // In development: resources are relative to electron/ dir
  return path.join(
    app.getAppPath(),
    "..",
    "resources",
    "bun",
    platformArch,
    bunExecutable
  );
}

function getServerPath(): string {
  return path.join(process.resourcesPath, "server", "index.js");
}

export async function startServer(): Promise<number> {
  if (serverProcess) {
    log.info("Server already running on port", currentPort);
    return currentPort!;
  }

  const port = await getPort({ port: [3000, 3001, 3002, 3003, 3004] });
  const bunPath = getBunPath();
  const serverPath = getServerPath();
  const dataDir = app.getPath("userData");

  log.info("Starting Bun server...");
  log.info("Bun path:", bunPath);
  log.info("Server path:", serverPath);
  log.info("Port:", port);

  const staticDir = app.isPackaged
    ? path.join(process.resourcesPath, "dist")
    : path.join(app.getAppPath(), "..", "dist");

  serverProcess = spawn(bunPath, ["run", serverPath, "--port", String(port)], {
    env: {
      ...process.env,
      APP_DATA_DIR: dataDir,         // Persistent storage (see pitfalls §7)
      APP_STATIC_DIR: staticDir,     // Static assets path
      NODE_ENV: "production",
    },
    stdio: ["ignore", "pipe", "pipe"],
  });

  serverProcess.stdout?.on("data", (data) => {
    log.info("[server]", data.toString().trim());
  });

  serverProcess.stderr?.on("data", (data) => {
    log.error("[server]", data.toString().trim());
  });

  serverProcess.on("error", (error) => {
    log.error("Failed to start server:", error);
    serverProcess = null;
    currentPort = null;
  });

  serverProcess.on("exit", (code, signal) => {
    log.info(`Server exited with code ${code}, signal ${signal}`);
    serverProcess = null;
    currentPort = null;
  });

  currentPort = port;
  await waitForServer(port);
  return port;
}

async function waitForServer(
  port: number,
  timeout: number = 30000
): Promise<void> {
  const start = Date.now();
  const url = `http://localhost:${port}`;

  while (Date.now() - start < timeout) {
    try {
      const response = await fetch(url);
      if (response.ok) {
        log.info("Server is ready");
        return;
      }
    } catch {
      // Server not ready yet
    }
    await new Promise((resolve) => setTimeout(resolve, 100));
  }

  throw new Error(`Server failed to start within ${timeout}ms`);
}

export function stopServer(): void {
  if (serverProcess) {
    log.info("Stopping server...");
    serverProcess.kill("SIGTERM");
    serverProcess = null;
    currentPort = null;
  }
}
```

### Key patterns:
- **`getBunPath()`** resolves differently for packaged vs dev — packaged uses `process.resourcesPath`, dev uses relative paths from `app.getAppPath()`
- **`getServerPath()`** only needs the production path — `startServer()` is never called in dev mode (the `ELECTRON_DEV_URL` path skips it)
- **`getPort()`** avoids conflicts by trying a list of preferred ports
- **Environment variables** pass data dir and static dir to the Bun server
- **`waitForServer()`** polls with fetch until the server responds (100ms interval, 30s timeout)
- **`stopServer()`** sends SIGTERM for clean shutdown

---

## src/main/window.ts — Window Management

```typescript
import path from "path";
import { fileURLToPath } from "url";
import { BrowserWindow, shell } from "electron";
import Store from "electron-store";
import log from "electron-log";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

interface WindowBounds {
  x?: number;
  y?: number;
  width: number;
  height: number;
}

const store = new Store<{ windowBounds: WindowBounds }>();
let mainWindow: BrowserWindow | null = null;

export function createWindow(port: number): BrowserWindow {
  const bounds = store.get("windowBounds", {
    width: 1200,
    height: 800,
    x: undefined,
    y: undefined,
  });

  mainWindow = new BrowserWindow({
    ...bounds,
    minWidth: 800,
    minHeight: 600,
    title: "Your App",
    titleBarStyle: process.platform === "darwin" ? "hiddenInset" : "default",
    trafficLightPosition: { x: 16, y: 16 },
    webPreferences: {
      preload: path.join(__dirname, "..", "preload", "index.js"),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
    },
    show: false,                  // Prevent white flash (see pitfalls §8)
    backgroundColor: "#0a0a0a",   // Match your app's background
  });

  mainWindow.once("ready-to-show", () => {
    mainWindow?.show();
  });

  // Persist window bounds for next launch
  mainWindow.on("close", () => {
    if (mainWindow) {
      store.set("windowBounds", mainWindow.getBounds());
    }
  });

  mainWindow.on("closed", () => {
    mainWindow = null;
  });

  // External links open in default browser
  mainWindow.webContents.setWindowOpenHandler(({ url }) => {
    shell.openExternal(url);
    return { action: "deny" };
  });

  // Prevent navigation away from the app
  mainWindow.webContents.on("will-navigate", (event, url) => {
    const serverUrl = `http://localhost:${port}`;
    if (!url.startsWith(serverUrl)) {
      event.preventDefault();
      shell.openExternal(url);
    }
  });

  mainWindow.loadURL(`http://localhost:${port}`);
  return mainWindow;
}

export function getMainWindow(): BrowserWindow | null {
  return mainWindow;
}
```

### Key patterns:
- **`electron-store`** persists window position/size across launches
- **`titleBarStyle: "hiddenInset"`** on macOS gives the native traffic light buttons with content extending behind the title bar
- **`trafficLightPosition`** offsets the traffic lights to align with your app's header
- **Security config**: `contextIsolation: true`, `nodeIntegration: false`, `sandbox: true` — never weaken these
- **Navigation guards** prevent the window from navigating away from localhost and open external links in the default browser

---

## src/main/updater.ts — Auto-Update

```typescript
import electronUpdater, { type UpdateInfo, type ProgressInfo } from "electron-updater";
import log from "electron-log";
import { getMainWindow } from "./window.js";

// CJS import pattern (see pitfalls §1)
const { autoUpdater } = electronUpdater;

export function setupAutoUpdater(): void {
  autoUpdater.logger = log;
  autoUpdater.autoDownload = false; // let user choose when to download

  autoUpdater.on("checking-for-update", () => {
    sendToRenderer("update:checking");
  });

  autoUpdater.on("update-available", (info: UpdateInfo) => {
    log.info("Update available:", info.version);
    sendToRenderer("update:available", { version: info.version });
  });

  autoUpdater.on("update-not-available", () => {
    sendToRenderer("update:not-available");
  });

  autoUpdater.on("download-progress", (progress: ProgressInfo) => {
    sendToRenderer("update:progress", { percent: progress.percent });
  });

  autoUpdater.on("update-downloaded", (info: UpdateInfo) => {
    log.info("Update downloaded:", info.version);
    sendToRenderer("update:downloaded", { version: info.version });
  });

  autoUpdater.on("error", (error: Error) => {
    log.error("Update error:", error);
    sendToRenderer("update:error", { message: error.message });
  });
}

function sendToRenderer(channel: string, data?: unknown): void {
  const window = getMainWindow();
  if (window) {
    window.webContents.send(channel, data);
  }
}

export function checkForUpdates(): void {
  autoUpdater.checkForUpdates();
}

export function downloadUpdate(): void {
  autoUpdater.downloadUpdate();
}

export function installUpdate(): void {
  autoUpdater.quitAndInstall();
}
```

### Key patterns:
- **`autoDownload: false`** — User-initiated downloads give a better UX than surprise background updates
- **Event flow**: `checking` → `available`/`not-available` → (user clicks download) → `progress` → `downloaded` → (user clicks install) → `quitAndInstall()`
- **`sendToRenderer()`** bridges main → renderer via `webContents.send()`
- The renderer invokes `update:check`, `update:download`, `update:install` via IPC handlers in `index.ts`

---

## src/preload/index.ts — Context Bridge

The preload script exposes a safe API to the renderer via `contextBridge`. It must compile to CommonJS (see pitfalls §2).

```typescript
import { contextBridge, ipcRenderer, type IpcRendererEvent } from "electron";

type IpcHandler<T = void> = (event: IpcRendererEvent, data: T) => void;

const electronAPI = {
  isElectron: true,
  platform: process.platform,
  version: () => ipcRenderer.invoke("app:version") as Promise<string>,

  update: {
    check: () => ipcRenderer.invoke("update:check"),
    download: () => ipcRenderer.invoke("update:download"),
    install: () => ipcRenderer.invoke("update:install"),

    // Each listener returns an unsubscribe function
    onAvailable: (callback: (data: { version: string }) => void) => {
      const handler: IpcHandler<{ version: string }> = (_, data) =>
        callback(data);
      ipcRenderer.on("update:available", handler);
      return () => ipcRenderer.removeListener("update:available", handler);
    },
    onProgress: (callback: (data: { percent: number }) => void) => {
      const handler: IpcHandler<{ percent: number }> = (_, data) =>
        callback(data);
      ipcRenderer.on("update:progress", handler);
      return () => ipcRenderer.removeListener("update:progress", handler);
    },
    onDownloaded: (callback: (data: { version: string }) => void) => {
      const handler: IpcHandler<{ version: string }> = (_, data) =>
        callback(data);
      ipcRenderer.on("update:downloaded", handler);
      return () => ipcRenderer.removeListener("update:downloaded", handler);
    },
    onError: (callback: (data: { message: string }) => void) => {
      const handler: IpcHandler<{ message: string }> = (_, data) =>
        callback(data);
      ipcRenderer.on("update:error", handler);
      return () => ipcRenderer.removeListener("update:error", handler);
    },
  },
};

contextBridge.exposeInMainWorld("electronAPI", electronAPI);
```

### Key patterns:
- **`contextBridge.exposeInMainWorld()`** — The only safe way to expose functionality to the renderer
- **Unsubscribe pattern** — Each `on*` method returns a cleanup function, compatible with React's `useEffect` cleanup
- **`ipcRenderer.invoke()`** for renderer → main (request/response)
- **`ipcRenderer.on()`** for main → renderer (push events)
- Never expose `ipcRenderer` directly — always wrap in specific methods
