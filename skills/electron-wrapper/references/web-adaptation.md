# Web App Adaptation

Changes to the existing web app to support running inside Electron while remaining fully functional as a standalone web app.

---

## 1. Electron Detection Utility

Create a utility module for Electron detection. All checks are optional-chained so they're safe in browser environments.

```typescript
// src/lib/electron.ts

type ElectronPlatform = "darwin" | "win32" | "linux" | string;

export function isElectron(): boolean {
  return Boolean(window?.electronAPI?.isElectron);
}

export function getElectronPlatform(): ElectronPlatform | null {
  return window?.electronAPI?.platform ?? null;
}

export function isMacElectron(): boolean {
  return isElectron() && getElectronPlatform() === "darwin";
}

export function applyElectronDocumentAttributes(): void {
  if (!isElectron()) return;
  const platform = getElectronPlatform();
  const root = document.documentElement;
  root.dataset.electron = "true";
  if (platform) {
    root.dataset.platform = platform;
  }
}
```

Call `applyElectronDocumentAttributes()` at app startup (e.g., in your entry file before React renders). This sets `data-electron="true"` and `data-platform="darwin"` on `<html>`, enabling CSS targeting.

---

## 2. Type Declarations

Declare the `window.electronAPI` shape with all properties optional so TypeScript doesn't complain in browser environments:

```typescript
// src/types/electron.d.ts

export {};

declare global {
  interface Window {
    electronAPI?: {
      isElectron?: boolean;
      platform?: string;
      version?: () => Promise<string>;
      update?: {
        check?: () => Promise<void>;
        download?: () => Promise<void>;
        install?: () => Promise<void>;
        onAvailable?: (
          callback: (data: { version: string }) => void
        ) => () => void;
        onProgress?: (
          callback: (data: { percent: number }) => void
        ) => () => void;
        onDownloaded?: (
          callback: (data: { version: string }) => void
        ) => () => void;
        onError?: (
          callback: (data: { message: string }) => void
        ) => () => void;
      };
    };
  }
}
```

Every property is optional (`?`) so `window.electronAPI?.update?.download?.()` works safely in both contexts.

---

## 3. CSS Drag Regions

Electron's frameless/hidden-inset title bar requires explicit CSS regions for window dragging.

### CSS utility classes

If using Tailwind CSS 4, add `@utility` rules in your globals.css:

```css
@utility drag {
  -webkit-app-region: drag;
}

@utility no-drag {
  -webkit-app-region: no-drag;
}
```

For plain CSS or older Tailwind:

```css
.app-window-drag {
  -webkit-app-region: drag;
}

.app-window-no-drag {
  -webkit-app-region: no-drag;
}
```

### Applying drag regions in components

Add the drag class to your app's header/toolbar areas when in Electron. Mark interactive children as no-drag:

```tsx
<header className={clsx(
  "flex shrink-0 items-center px-4 border-b",
  isElectron() && "drag",
  isMacElectron() ? "h-auto pb-3 pt-7" : "h-12",
)}>
  <div className="no-drag">
    <Logo />
  </div>
  <nav className="no-drag">
    <FilterTabs />
  </nav>
</header>
```

### Traffic light clearance (macOS)

**Prefer a taller header over left padding.** With `titleBarStyle: "hiddenInset"` and `trafficLightPosition: { x: 16, y: 12 }`, the traffic light buttons occupy roughly y=12 to y=24. Instead of adding `padding-left: 72px` to dodge them horizontally, make the header tall enough so content sits below them:

```tsx
// Good — taller header, content below traffic lights
isMacElectron() ? "h-auto pb-3 pt-7" : "h-12"

// Avoid — left padding wastes horizontal space in narrow windows
isMacElectron() ? "pl-[72px]" : ""
```

This approach works better for narrow/compact windows where horizontal space is at a premium.

### Dialog backdrop dragging

Make dialog backdrops draggable so users can still drag the window when a modal is open, but mark the dialog content as non-draggable:

```tsx
// In your Dialog component
<DialogBackdrop className={clsx("dialog-backdrop", isElectron() && "drag")} />
<DialogPopup className="no-drag">
  {children}
</DialogPopup>
```

---

## 4. Storage Path Adaptation

Make your server's data directory configurable via environment variable so Electron can redirect storage to `userData`:

```typescript
// In your server's storage module
const DATA_DIR = process.env.APP_DATA_DIR || process.cwd();
const DATA_FILE = path.join(DATA_DIR, ".app-data.json");
```

The Bun server process receives `APP_DATA_DIR` from Electron's main process (see main-process.md §bun-server). In web mode, it falls back to `process.cwd()`.

Namespace the env var per project (e.g., `MY_APP_DATA_DIR`) to avoid conflicts.

---

## 5. Static Asset Serving in Production

In production mode, the Bun server needs to serve the built web assets (HTML, JS, CSS). The static directory path comes from an environment variable since the packaged app's file layout differs from development.

```typescript
// In your server's request handler
const STATIC_DIR = process.env.APP_STATIC_DIR;

// Serve static files from the build output
if (STATIC_DIR) {
  const filePath = path.join(STATIC_DIR, url.pathname);
  const resolved = path.resolve(filePath);

  // Security: prevent directory traversal
  if (resolved.startsWith(path.resolve(STATIC_DIR))) {
    const file = Bun.file(resolved);
    if (await file.exists()) {
      return new Response(file);
    }
  }
}
```

In development, the dev server handles this automatically with HMR.

---

## 6. Auto-Update UI

### useElectronUpdater hook

A React hook that subscribes to update events from the preload bridge:

```tsx
type UpdateStatus = "available" | "downloading" | "ready";

function useElectronUpdater(devOverride: UpdateStatus | null) {
  const [status, setStatus] = useState<UpdateStatus | null>(null);
  const [version, setVersion] = useState<string | null>(null);
  const [progress, setProgress] = useState(0);

  useEffect(() => {
    if (!isElectron()) return;
    const api = window.electronAPI?.update;
    if (!api) return;

    const unsubs: (() => void)[] = [];

    if (api.onAvailable) {
      unsubs.push(
        api.onAvailable((data) => {
          setVersion(data.version);
          setStatus("available");
        })
      );
    }
    if (api.onProgress) {
      unsubs.push(
        api.onProgress((data) => {
          setStatus("downloading");
          setProgress(Math.round(data.percent));
        })
      );
    }
    if (api.onDownloaded) {
      unsubs.push(api.onDownloaded(() => setStatus("ready")));
    }
    if (api.onError) {
      unsubs.push(
        api.onError((data) => {
          console.error("Auto-update error:", data.message);
          setStatus(null);
        })
      );
    }

    return () => unsubs.forEach((fn) => fn());
  }, []);

  // Allow dev tools to override the state for testing
  const effective = devOverride ?? status;
  if (!effective) return null;

  return {
    status: effective,
    version: devOverride ? "0.0.0-dev" : version,
    progress: devOverride === "downloading" ? 42 : progress,
    download: () => window.electronAPI?.update?.download?.(),
    install: () => window.electronAPI?.update?.install?.(),
  };
}
```

### Update notification component

A minimal pill-shaped notification that appears when an update is available:

```tsx
function UpdatePill({ updater }: { updater: NonNullable<ReturnType<typeof useElectronUpdater>> }) {
  return (
    <div className="update-pill">
      {updater.status === "available" && (
        <>
          <span>v{updater.version} available</span>
          <button onClick={updater.download}>Update</button>
        </>
      )}
      {updater.status === "downloading" && (
        <span>Downloading... {updater.progress}%</span>
      )}
      {updater.status === "ready" && (
        <>
          <span>Update ready</span>
          <button onClick={updater.install}>Restart</button>
        </>
      )}
    </div>
  );
}
```

### DevTools override for testing

Add a keyboard shortcut (e.g., Shift+U) that cycles through update states for testing the UI without a real update:

```tsx
function DevTools() {
  const [updateOverride, setUpdateOverride] = useState<UpdateStatus | null>(null);

  useHotkeys("shift+u", () => {
    setUpdateOverride((prev) => {
      if (prev === null) return "available";
      if (prev === "available") return "downloading";
      if (prev === "downloading") return "ready";
      return null;
    });
  });

  // Pass updateOverride to useElectronUpdater
}
```

---

## 7. Environment-Based Feature Gating

Use `isElectron()` to gate features that only make sense in one context:

```typescript
// Demo mode doesn't apply in Electron (user has their own data)
export function resolveDemoMode(): boolean {
  if (isElectron()) return false;
  // ... web-specific demo logic
}

// "Hosted environment" features (analytics, etc.) don't apply in Electron
export function isHostedEnvironment(): boolean {
  if (isElectron()) return false;
  // ... check for hosted domain
}
```

The general principle: Electron users have the app installed locally with their own data, so hosted/demo/marketing features should be disabled.
