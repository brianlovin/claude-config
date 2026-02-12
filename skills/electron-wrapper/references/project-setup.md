# Project Setup

How to set up the Electron subproject alongside an existing Bun web app.

---

## Directory Structure

Create an `electron/` directory at the root of your project:

```
your-app/
├── electron/
│   ├── package.json
│   ├── package-lock.json
│   ├── tsconfig.main.json
│   ├── tsconfig.preload.json
│   ├── electron-builder.yml
│   ├── entitlements.mac.plist
│   ├── assets/
│   │   ├── app-icon.png          (512x512+ source icon)
│   │   ├── app-icon.icns         (generated for macOS)
│   │   └── icon.ico              (generated for Windows)
│   ├── src/
│   │   ├── main/
│   │   │   ├── index.ts          (app entry point)
│   │   │   ├── bun-server.ts     (server spawning)
│   │   │   ├── window.ts         (window management)
│   │   │   └── updater.ts        (auto-update)
│   │   └── preload/
│   │       └── index.ts          (context bridge)
│   └── scripts/
│       └── generate-icons.mjs    (icon generation)
├── scripts/
│   ├── build-server.ts           (Bun.build() for server bundle)
│   └── download-bun.ts           (Bun binary downloader)
├── resources/
│   ├── bun/
│   │   ├── darwin-arm64/bun
│   │   ├── darwin-x64/bun
│   │   └── win32-x64/bun.exe
│   └── server/
│       └── index.js              (bundled server output)
├── dist/                          (web app build output)
├── src/                           (your existing web app)
└── package.json
```

---

## electron/package.json

Use **npm** (not Bun) for the Electron subproject. Bun's module resolution conflicts with electron-builder's packaging expectations.

```json
{
  "name": "your-app-electron",
  "version": "0.1.0",
  "private": true,
  "repository": "github:your-org/your-app",
  "type": "module",
  "main": "dist/main/index.js",
  "scripts": {
    "dev": "concurrently \"npm run dev:web\" \"npm run dev:electron\"",
    "dev:web": "cd .. && bun run dev",
    "dev:electron": "wait-on http://localhost:3005 && npm run build && ELECTRON_DEV_URL=http://localhost:3005 electron .",
    "build": "tsc -p tsconfig.main.json && esbuild src/preload/index.ts --bundle --platform=node --format=cjs --outfile=dist/preload/index.js --external:electron",
    "icons": "node scripts/generate-icons.mjs",
    "pack": "npm run build && electron-builder --dir",
    "dist": "npm run build && electron-builder",
    "dist:mac": "npm run build && electron-builder --mac",
    "dist:win": "npm run build && electron-builder --win"
  },
  "dependencies": {
    "electron-log": "^5.2.4",
    "electron-store": "^10.0.0",
    "electron-updater": "^6.3.9",
    "get-port": "^7.1.0"
  },
  "devDependencies": {
    "concurrently": "^9.1.2",
    "electron": "^33.2.0",
    "electron-builder": "^25.1.8",
    "esbuild": "^0.27.3",
    "png-to-ico": "^3.0.0",
    "typescript": "^5.8.3",
    "wait-on": "^8.0.3"
  }
}
```

Key decisions:
- **`"type": "module"`** — Required so Node.js treats compiled `.js` as ESM (see pitfalls §1)
- **`"repository"`** — Required by electron-builder for GitHub releases publish provider
- **`"main"`** — Points to compiled entry point
- **npm, not Bun** — electron-builder expects npm-style `node_modules` layout

---

## TypeScript Configs

Two separate configs are required because the main process uses ESM while preload scripts must be CJS (see pitfalls §2).

### tsconfig.main.json (ESM)

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "NodeNext",
    "moduleResolution": "NodeNext",
    "lib": ["ES2022"],
    "outDir": "dist/main",
    "rootDir": "src/main",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "resolveJsonModule": true,
    "declaration": false,
    "declarationMap": false,
    "sourceMap": true
  },
  "include": ["src/main/**/*"]
}
```

### tsconfig.preload.json (CommonJS)

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "CommonJS",
    "moduleResolution": "Node",
    "lib": ["ES2022", "DOM"],
    "outDir": "dist/preload",
    "rootDir": "src/preload",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "resolveJsonModule": true,
    "declaration": false,
    "declarationMap": false,
    "sourceMap": true
  },
  "include": ["src/preload/**/*"]
}
```

Note `"lib"` includes `"DOM"` for preload (it runs in renderer context) but not for main.

---

## electron-builder.yml

```yaml
appId: com.your-org.your-app
productName: Your App
copyright: Copyright © 2025

directories:
  output: release
  buildResources: assets

files:
  - dist/**/*

extraResources:
  - from: ../resources/server/
    to: server/
  - from: ../dist/
    to: dist/

mac:
  extraResources:
    - from: ../resources/bun/darwin-${arch}/
      to: bun/
  icon: assets/app-icon.icns
  category: public.app-category.utilities
  target:
    - target: dmg
      arch:
        - arm64
        - x64
    - target: zip
      arch:
        - arm64
        - x64
  hardenedRuntime: true
  gatekeeperAssess: false
  entitlements: entitlements.mac.plist
  entitlementsInherit: entitlements.mac.plist
  notarize: true

dmg:
  sign: false
  contents:
    - x: 130
      y: 220
    - x: 410
      y: 220
      type: link
      path: /Applications

win:
  extraResources:
    - from: ../resources/bun/win32-${arch}/
      to: bun/
  icon: assets/icon.ico
  target:
    - target: nsis
      arch:
        - x64
  artifactName: ${productName}-${version}-${arch}.${ext}

nsis:
  oneClick: false
  perMachine: false
  allowToChangeInstallationDirectory: true
  deleteAppDataOnUninstall: false

publish:
  provider: github
  releaseType: draft
```

Key points:
- **`extraResources`** bundles the Bun binary, server bundle, and web app build into the packaged app
- **Bun binary paths use platform-specific sections** — electron-builder's `${platform}` resolves to `mac`/`win`, NOT `darwin`/`win32`. Since the download script uses Node.js platform names (`darwin`, `win32`), the bun `extraResources` entry must go in platform-specific `mac:`/`win:` sections with hardcoded platform prefixes instead of using `${platform}`
- **`notarize: true`** requires Apple credentials in environment (see build-and-distribute.md)
- **`dmg.sign: false`** — DMG signing is unnecessary and can cause issues

---

## entitlements.mac.plist

Required for macOS code signing. The Bun runtime needs JIT and unsigned memory permissions:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.cs.allow-jit</key>
    <true/>
    <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
    <key>com.apple.security.network.server</key>
    <true/>
</dict>
</plist>
```

- **allow-jit** and **allow-unsigned-executable-memory** — Required because the bundled Bun binary uses JIT compilation
- **network.client** and **network.server** — The app runs a local server and makes outbound API calls

---

## Parent Project Changes

### package.json scripts

Add these scripts to the root `package.json`:

```json
{
  "scripts": {
    "build:server": "bun scripts/build-server.ts",
    "download-bun": "bun scripts/download-bun.ts",
    "electron:dev": "cd electron && npm run dev",
    "electron:build": "bun run build:server && cd electron && npm run build",
    "electron:pack": "bun run build && bun run build:server && cd electron && npm run pack",
    "electron:dist": "bun run build && bun run build:server && cd electron && npm run dist"
  }
}
```

### tsconfig.json excludes

Exclude Electron and script directories from your web app's TypeScript config:

```json
{
  "exclude": ["electron", "scripts", "resources"]
}
```

### .gitignore additions

```gitignore
# Electron
electron/dist/
electron/release/
electron/node_modules/
resources/bun/
resources/server/
```

The `resources/` directories contain large binaries and build artifacts that should not be committed.
