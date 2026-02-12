# Build & Distribution

Server bundling, Bun binary packaging, CI/CD workflows, code signing, and icon generation.

---

## 1. Server Bundle Script

Bundle the Bun web server into a single file for packaging:

```typescript
// scripts/build-server.ts
import { mkdir, rm } from "fs/promises";
import path from "path";

async function main(): Promise<void> {
  const outDir = path.join(import.meta.dir, "..", "resources", "server");

  await rm(outDir, { recursive: true, force: true });
  await mkdir(outDir, { recursive: true });

  const result = await Bun.build({
    entrypoints: [path.join(import.meta.dir, "..", "src", "index.ts")],
    target: "bun",
    minify: true,
    outdir: outDir,
    define: {
      "process.env.NODE_ENV": JSON.stringify("production"),
    },
  });

  if (!result.success) {
    console.error("Server build failed");
    process.exit(1);
  }

  console.log(`Server bundle written to ${outDir}`);
}

main().catch((error) => {
  console.error("Server build error:", error);
  process.exit(1);
});
```

This produces `resources/server/index.js` — a single file that the bundled Bun binary runs in the packaged app.

---

## 2. Bun Binary Download Script

Downloads platform-specific Bun binaries for bundling into the Electron app:

```typescript
// scripts/download-bun.ts
import { mkdir, unlink } from "fs/promises";
import { existsSync } from "fs";
import path from "path";

const BUN_VERSION = "1.2.5"; // pin to match your dev version

const PLATFORMS = [
  { platform: "darwin", arch: "arm64", file: "bun-darwin-aarch64.zip" },
  { platform: "darwin", arch: "x64", file: "bun-darwin-x64.zip" },
  { platform: "win32", arch: "x64", file: "bun-windows-x64.zip" },
] as const;

const RESOURCES_DIR = path.join(import.meta.dir, "..", "resources", "bun");

async function downloadBun(
  platform: string,
  arch: string,
  file: string,
  force: boolean = false
): Promise<void> {
  const url = `https://github.com/oven-sh/bun/releases/download/bun-v${BUN_VERSION}/${file}`;
  const outDir = path.join(RESOURCES_DIR, `${platform}-${arch}`);
  const zipPath = path.join(outDir, file);
  const bunExecutable = platform === "win32" ? "bun.exe" : "bun";
  const bunPath = path.join(outDir, bunExecutable);

  if (existsSync(bunPath) && !force) {
    console.log(`Bun already exists for ${platform}-${arch}, skipping...`);
    return;
  }

  console.log(`Downloading Bun for ${platform}-${arch}...`);
  await mkdir(outDir, { recursive: true });

  const response = await fetch(url);
  if (!response.ok) throw new Error(`Failed to download: ${response.status}`);

  await Bun.write(zipPath, response);

  // Extract and flatten
  const proc = Bun.spawn(["unzip", "-o", zipPath, "-d", outDir], {
    cwd: outDir,
    stdout: "inherit",
    stderr: "inherit",
  });
  await proc.exited;

  // Move binary from extracted subdirectory to outDir root
  const extractedDir = path.join(outDir, file.replace(".zip", ""));
  const extractedBun = path.join(extractedDir, bunExecutable);

  if (existsSync(extractedBun)) {
    const moveProc = Bun.spawn(["mv", extractedBun, bunPath]);
    await moveProc.exited;
    const rmProc = Bun.spawn(["rm", "-rf", extractedDir]);
    await rmProc.exited;
  }

  await unlink(zipPath);

  if (platform !== "win32") {
    const chmodProc = Bun.spawn(["chmod", "+x", bunPath]);
    await chmodProc.exited;
  }

  console.log(`Bun ready at ${bunPath}`);
}

async function main(): Promise<void> {
  const args = process.argv.slice(2);
  let platforms = PLATFORMS;
  const force = args.includes("--force");

  // --current: download only for the current platform
  if (args.includes("--current")) {
    const currentPlatform = process.platform;
    const currentArch = process.arch === "arm64" ? "arm64" : "x64";
    platforms = PLATFORMS.filter(
      (p) => p.platform === currentPlatform && p.arch === currentArch
    );
  }

  // --platform darwin --arch arm64: for CI cross-builds
  const platformIdx = args.indexOf("--platform");
  const archIdx = args.indexOf("--arch");
  if (platformIdx !== -1 && archIdx !== -1) {
    const targetPlatform = args[platformIdx + 1];
    const targetArch = args[archIdx + 1];
    platforms = PLATFORMS.filter(
      (p) => p.platform === targetPlatform && p.arch === targetArch
    );
  }

  for (const { platform, arch, file } of platforms) {
    await downloadBun(platform, arch, file, force);
  }
}

main().catch((error) => {
  console.error("Error:", error);
  process.exit(1);
});
```

### CLI flags:
- `--current` — download only for current platform/arch (local dev)
- `--platform darwin --arch arm64` — download specific target (CI)
- `--force` — re-download even if binary exists

---

## 3. Package Scripts

### Root package.json

```json
{
  "scripts": {
    "build": "bun run build.ts",
    "build:server": "bun scripts/build-server.ts",
    "download-bun": "bun scripts/download-bun.ts",
    "electron:dev": "cd electron && npm run dev",
    "electron:build": "bun run build:server && cd electron && npm run build",
    "electron:pack": "bun run build && bun run build:server && cd electron && npm run pack",
    "electron:dist": "bun run build && bun run build:server && cd electron && npm run dist"
  }
}
```

### electron/package.json

```json
{
  "scripts": {
    "dev": "concurrently \"npm run dev:web\" \"npm run dev:electron\"",
    "dev:web": "cd .. && bun run dev",
    "dev:electron": "wait-on http://localhost:3005 && npm run build && ELECTRON_DEV_URL=http://localhost:3005 electron .",
    "build": "tsc -p tsconfig.main.json && tsc -p tsconfig.preload.json",
    "pack": "npm run build && electron-builder --dir",
    "dist": "npm run build && electron-builder",
    "dist:mac": "npm run build && electron-builder --mac",
    "dist:win": "npm run build && electron-builder --win"
  }
}
```

Build pipeline: `build web app` → `build server bundle` → `compile electron TS` → `electron-builder packages everything`

---

## 4. GitHub Actions CI Workflow

```yaml
name: Electron Release

on:
  push:
    tags:
      - 'v*'
  workflow_dispatch:
    inputs:
      version:
        description: 'Version to release (without v prefix)'
        required: false

jobs:
  build-mac:
    runs-on: macos-14
    strategy:
      matrix:
        arch: [arm64, x64]
    steps:
      - uses: actions/checkout@v4

      - name: Setup Bun
        uses: oven-sh/setup-bun@v2
        with:
          bun-version: latest

      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: 20
          cache: npm
          cache-dependency-path: electron/package-lock.json

      - name: Install web dependencies
        run: bun install

      - name: Build web app
        run: bun run build

      - name: Build server bundle
        run: bun run build:server

      - name: Download Bun binary
        run: bun scripts/download-bun.ts --platform darwin --arch ${{ matrix.arch }}

      - name: Install Electron dependencies
        run: cd electron && npm ci

      - name: Import Apple certificates
        env:
          APPLE_CERTIFICATE: ${{ secrets.APPLE_CERTIFICATE }}
          APPLE_CERTIFICATE_PASSWORD: ${{ secrets.APPLE_CERTIFICATE_PASSWORD }}
        run: |
          echo "$APPLE_CERTIFICATE" | base64 --decode > certificate.p12
          security create-keychain -p "" build.keychain
          security default-keychain -s build.keychain
          security unlock-keychain -p "" build.keychain
          security import certificate.p12 -k build.keychain \
            -P "$APPLE_CERTIFICATE_PASSWORD" -T /usr/bin/codesign
          security set-key-partition-list -S apple-tool:,apple:,codesign: \
            -s -k "" build.keychain
          rm certificate.p12

      - name: Build Electron app
        env:
          APPLE_ID: ${{ secrets.APPLE_ID }}
          APPLE_APP_SPECIFIC_PASSWORD: ${{ secrets.APPLE_PASSWORD }}
          APPLE_TEAM_ID: ${{ secrets.APPLE_TEAM_ID }}
          CSC_KEYCHAIN: build.keychain
        run: |
          cd electron
          npm run dist:mac -- --${{ matrix.arch }} --publish never

      - name: Upload artifacts
        uses: actions/upload-artifact@v4
        with:
          name: mac-${{ matrix.arch }}
          path: |
            electron/release/*.dmg
            electron/release/*.zip
            electron/release/*.yml
            electron/release/*.blockmap
          if-no-files-found: error

  build-windows:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4
      - uses: oven-sh/setup-bun@v2
        with:
          bun-version: latest
      - uses: actions/setup-node@v4
        with:
          node-version: 20
          cache: npm
          cache-dependency-path: electron/package-lock.json

      - run: bun install
      - run: bun run build
      - run: bun run build:server
      - run: bun scripts/download-bun.ts --platform win32 --arch x64
      - run: cd electron && npm ci
      - run: cd electron && npm run dist:win -- --publish never

      - uses: actions/upload-artifact@v4
        with:
          name: windows-x64
          path: |
            electron/release/*.exe
            electron/release/*.yml
            electron/release/*.blockmap
          if-no-files-found: error

  publish:
    needs: [build-mac, build-windows]
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
      - uses: actions/checkout@v4

      - uses: actions/download-artifact@v4
        with:
          path: artifacts

      - name: Get version
        id: version
        run: |
          if [ "${{ github.event_name }}" = "workflow_dispatch" ] && \
             [ -n "${{ github.event.inputs.version }}" ]; then
            echo "version=${{ github.event.inputs.version }}" >> $GITHUB_OUTPUT
          else
            echo "version=${GITHUB_REF#refs/tags/v}" >> $GITHUB_OUTPUT
          fi

      - name: Create Release
        uses: softprops/action-gh-release@v2
        with:
          name: Your App v${{ steps.version.outputs.version }}
          draft: true
          files: |
            artifacts/**/*.dmg
            artifacts/**/*.zip
            artifacts/**/*.exe
            artifacts/**/*.yml
            artifacts/**/*.blockmap
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

### Key CI decisions:
- **`--publish never`** — Build locally, upload artifacts, create release in a separate job. This avoids giving build machines GitHub token access.
- **Matrix builds** for macOS arm64/x64 — Both run on `macos-14` (Apple Silicon), cross-compilation handles x64
- **Draft release** — Review before publishing to trigger auto-updater

---

## 5. Code Signing (macOS)

### Prerequisites

1. **Apple Developer account** ($99/year)
2. **Developer ID Application certificate** from Apple Developer portal
3. **App-specific password** for notarization

### Certificate export

1. Open Keychain Access
2. Find "Developer ID Application: Your Name" certificate
3. Right-click → Export → save as `.p12` with a password
4. Base64 encode: `base64 -i certificate.p12 | pbcopy`

### Required GitHub secrets

| Secret | Value |
|--------|-------|
| `APPLE_CERTIFICATE` | Base64-encoded .p12 certificate |
| `APPLE_CERTIFICATE_PASSWORD` | Password used when exporting .p12 |
| `APPLE_ID` | Apple ID email |
| `APPLE_PASSWORD` | App-specific password (not account password) |
| `APPLE_TEAM_ID` | Team ID from Apple Developer portal |

### Local signing test

```bash
# Build with signing (credentials in env)
export APPLE_ID="your@email.com"
export APPLE_APP_SPECIFIC_PASSWORD="xxxx-xxxx-xxxx-xxxx"
export APPLE_TEAM_ID="XXXXXXXXXX"
cd electron && npm run dist:mac
```

---

## 6. Icon Generation

### macOS (.icns)

Use `sips` (built into macOS) and `iconutil`:

```bash
# From a 1024x1024 PNG source
mkdir icon.iconset
sips -z 16 16     app-icon.png --out icon.iconset/icon_16x16.png
sips -z 32 32     app-icon.png --out icon.iconset/icon_16x16@2x.png
sips -z 32 32     app-icon.png --out icon.iconset/icon_32x32.png
sips -z 64 64     app-icon.png --out icon.iconset/icon_32x32@2x.png
sips -z 128 128   app-icon.png --out icon.iconset/icon_128x128.png
sips -z 256 256   app-icon.png --out icon.iconset/icon_128x128@2x.png
sips -z 256 256   app-icon.png --out icon.iconset/icon_256x256.png
sips -z 512 512   app-icon.png --out icon.iconset/icon_256x256@2x.png
sips -z 512 512   app-icon.png --out icon.iconset/icon_512x512.png
sips -z 1024 1024 app-icon.png --out icon.iconset/icon_512x512@2x.png
iconutil -c icns icon.iconset -o app-icon.icns
rm -rf icon.iconset
```

### Windows (.ico)

Use `png-to-ico` (Node.js package, added as devDependency):

```javascript
// electron/scripts/generate-icons.mjs
import fs from "fs/promises";
import path from "path";
import { fileURLToPath } from "url";
import pngToIco from "png-to-ico";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const assetsDir = path.resolve(__dirname, "..", "assets");
const inputPng = path.join(assetsDir, "app-icon.png");
const outputIco = path.join(assetsDir, "icon.ico");

const icoBuffer = await pngToIco(inputPng);
await fs.writeFile(outputIco, icoBuffer);
console.log(`Generated ${outputIco}`);
```

Run with `cd electron && npm run icons`.

### Source icon requirements
- PNG format, 1024x1024px minimum (512x512 acceptable)
- No transparency for macOS (Apple's guidelines)
- Place source at `electron/assets/app-icon.png`

---

## 7. Release Process

1. Update version in both `package.json` and `electron/package.json`
2. Commit: `git commit -m "Bump version to X.Y.Z"`
3. Tag: `git tag vX.Y.Z`
4. Push: `git push && git push --tags`
5. CI builds and creates a draft release with artifacts
6. Review the draft release on GitHub
7. Publish the release — this makes it visible to the auto-updater
8. The auto-updater checks `latest.yml`/`latest-mac.yml` from GitHub Releases

electron-updater uses the `publish.provider: github` config in `electron-builder.yml` to find releases. The `latest*.yml` files (uploaded as release artifacts) tell the updater the current version and download URLs.
