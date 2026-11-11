# System Architecture

## 1. System Overview

Wirt runs extension background scripts in WebViews inside a companion macOS app. Content scripts and popups run in Safari.

```mermaid
flowchart LR
    subgraph Safari["Safari Web Extension<br/>(WirtExtension.appex)"]
        direction TB
        Boot["Bootstrapper<br/>(bootstrapper.content.ts)"]
        Worker["Extension Worker<br/>(background.ts)"]
        Handler["Extension Handler<br/>(ExtensionHandler.swift)"]
        Hub["Popup Hub<br/>(popup/App.tsx)"]
        Boot -->|"sendMessage()"| Worker
        Hub -->|"sendMessage()"| Worker
        Worker -->|"sendNativeMessage()"| Handler
    end

    Launchd["launchd"]

    subgraph Host["Host App<br/>(Wirt.app)"]
        direction TB
        Listener["XPC Listener<br/>(ExtensionListener.swift)"]
        Server["HTTP Server<br/>(ExtensionServer.swift)"]
        Supervisor["Extension Runtime<br/>(ExtensionRuntime.swift)"]
        Runtime["Background Runtime (WKWebView)"]
        Storage[("Extension Storage<br/>(ExtensionStorage.swift)")]
        Listener --> Supervisor
        Supervisor --> Runtime
        Listener --> Storage
        Supervisor --> Storage
        Server -.->|"read files"| Storage
    end

    Launchd -->|"spawn"| Host
    Safari ==>|"IPC (NSXPCConnection)"| Host
    Safari -.->|"WebExt UI (HTTP GET)"| Host
```

Two targets:

- `WirtExtension.appex`: Safari extension. Intercepts web requests, handles tabs, forwards messages.
- `Wirt.app`: macOS host app. Runs background WebViews, stores data, serves popup files.

---

## 2. Process Lifecycle and IPC

Host app runs as a `launchd` agent.

```mermaid
sequenceDiagram
    autonumber
    participant User as User
    participant Launcher as Host App (launcher)
    participant Launchd as launchd
    participant Agent as Host App (agent)

    User->>Launcher: Open app
    Launcher->>Launchd: registerAgent()
    Launcher->>Launchd: Look up Mach service
    opt Agent not running
        Launchd->>Agent: Spawn with --background
    end
    Launcher->>Agent: showSettings()
    Agent-->>Launcher: Reply
    Launcher->>Launcher: terminate()
    User->>Agent: Close window
    Agent->>Agent: windowShouldClose()
```

1. `launchd` manages Mach service (`de.easonwong.Wirt.mach`).
2. Safari wakes host on demand via XPC.
3. Host boots background WebViews for all installed extensions.
4. Opening `Wirt.app` calls `showSettings()` on running agent, then quits.
5. Closing settings window hides UI; process stays alive in background.
6. XPC connections are per-request to avoid stale sockets.

---

## 3. Background Script Execution

Host runs background scripts in headless `WKWebView` instances.

```mermaid
flowchart LR
    subgraph SupervisorSub["Extension Runtime<br/>(ExtensionRuntime.swift)"]
        direction TB
        Init["startBackgroundRuntime()"]
        Scheme["WKURLSchemeHandler"]
        Bridge["WKScriptMessageHandler"]
    end

    subgraph RuntimeSub["Background Runtime (WKWebView)"]
        direction TB
        Shim["Shim<br/>(chrome-shim.js)"]
        Script["Background Script<br/>(background.js)"]
    end

    Init -->|"create"| RuntimeSub
    Scheme -->|"ext-bg://"| RuntimeSub
    Bridge <-.->|"hostBridge"| RuntimeSub
```

1. **Origin:** Custom scheme `ext-bg://<id>/` loads local files securely.
2. **CORS:** `webSecurityEnabled: false` allows cross-origin fetch.
3. **Shim:** `chrome-shim.js` injects `chrome.*` and `browser.*` APIs.
4. **Modules:** Renders `<script type="module">` for module workers.
5. **Bridge:** `hostBridge.postMessage()` sends calls to Swift; Swift invokes `__wirtBridgeCallback()` to resolve Promises.

---

## 4. Content Script Injection

Content scripts run directly in webpage DOM.

```mermaid
sequenceDiagram
    autonumber
    participant Page as Webpage DOM
    participant Boot as Bootstrapper<br/>(bootstrapper.content.ts)
    participant Worker as Extension Worker<br/>(background.ts)
    participant Supervisor as Extension Runtime<br/>(ExtensionRuntime.swift)

    Page->>Boot: Document start
    Boot->>Worker: initialiseMatchingScripts()
    Worker->>Supervisor: getMatchingScripts()
    Supervisor-->>Worker: Scripts and styles (with runAt & allFrames)
    Worker-->>Boot: Script payload
    Boot->>Page: Inject styles
    Boot->>Boot: scheduleScriptExecution(runAt)
    Boot->>Boot: evaluateScopedScript()
```

1. `bootstrapper.content.ts` runs on `<all_urls>` at `document_start`.
2. Bootstrapper asks host for scripts matching URL.
3. Matches respect `run_at` (`start`, `end`, `idle`) and `all_frames`.
4. CSS injects via `<style>` tags.
5. Scripts evaluate inside isolated function wrappers.

---

## 5. Inter-Process Messaging

Content scripts and host runtime communicate via native message bus.

```mermaid
sequenceDiagram
    autonumber
    participant Content as Content Script
    participant Worker as Worker (background.ts)
    participant Handler as Handler (Safari)
    participant Host as Host (Wirt.app)
    participant WebView as Background (WKWebView)

    Content->>Worker: sendMessage()
    Worker->>Handler: sendNativeMessage()
    Handler->>Host: XPC message
    Host->>WebView: eval onMessage
    WebView-->>Host: postMessage reply
    Host-->>Handler: XPC reply
    Handler-->>Worker: Native reply
    Worker-->>Content: Resolve promise
```

### IPC Envelope

```json
{
	"correlationId": "e5c2b0d3-1111-4444-8888-abcdef012345",
	"extensionId": "ext_sample",
	"payload": { "action": "checkRule" },
	"source": { "tabId": 14, "frameId": 0, "url": "https://example.co.uk" },
	"type": "RUNTIME_SEND_MESSAGE"
}
```

- Content script calls `browser.runtime.sendMessage()`.
- Worker forwards via `sendNativeMessage()`.
- `ExtensionHandler` routes over XPC to host app.
- Host runs script in target `WKWebView` and returns reply.

---

## 6. Toolbar Actions and Popups

Safari has one toolbar icon. Wirt popup hub hosts all extensions.

```mermaid
sequenceDiagram
    autonumber
    participant User
    participant Hub as Hub (App.tsx)
    participant Host as Host (Wirt.app)
    participant Server as HTTP Server
    participant Frame as Popup (iframe)

    User->>Hub: Click extension
    Hub->>Host: GET_POPUP_RESOURCES (XPC)
    Host-->>Hub: Return token URL
    Hub->>Frame: Set iframe src
    Frame->>Server: HTTP GET files
    Server-->>Frame: Return files
    Frame->>Hub: postMessage(API request)
    Hub->>Host: XPC call
    Host-->>Hub: Reply
    Hub-->>Frame: postMessage(reply)
```

- **Popup (`actionType: "popup"`):**
    1. Hub requests popup URL with token via XPC.
    2. Hub sets `iframe.src = "http://127.0.0.1:<port>/<token>/<id>/<path>"`.
    3. `ExtensionServer.swift` serves files on `127.0.0.1`. Validates `Host` and token.
    4. Popup uses `window.parent.postMessage()` for API calls.
    5. Hub forwards calls to host via XPC and returns replies.
- **Click (`actionType: "click"`):**
  Hub triggers `chrome.action.onClicked` in background runtime.
- **None (`actionType: "none"`):**
  Row disabled.

---

## 7. Package Installation and Storage

Host downloads, validates, unpacks, and stores extensions atomically.

```mermaid
flowchart LR
    subgraph Trigger["Bootstrapper<br/>(bootstrapper.content.ts)"]
        direction TB
        Link["interceptDownloadClicks()"]
        Store["hookStorefronts()"]
    end

    subgraph Package["Installer Service<br/>(ExtensionInstaller.swift)"]
        direction TB
        Download["URLSession.download()"]
        Stage["Extract to .staging_<uuid>"]
        Resolve["Resolve Canonical ID"]
        Commit["Atomic Move to Extensions/<id>"]
        Download --> Stage
        Stage --> Resolve
        Resolve --> Commit
    end

    subgraph StorageEngine["Storage Service<br/>(ExtensionStorage.swift)"]
        direction TB
        JSONStore[("Application Support/Wirt/Storage/<id>.json")]
    end

    subgraph Supervisor["Extension Runtime<br/>(ExtensionRuntime.swift)"]
        direction TB
        Start["startBackgroundRuntime()"]
    end

    Trigger -->|"sendMessage()"| Package
    Package --> Supervisor
    Supervisor <--> StorageEngine
```

1. **Interception:** Content script intercepts `.crx`/`.xpi` links and store install buttons.
2. **Staging:** Unpacks package into `.staging_<uuid>` after stripping CRX headers.
3. **ID Resolution:** Extracts ID from manifest or calculates SHA-256 base32 hash.
4. **Commit:** Renames staging folder to `Extensions/<id>/`.
5. **Storage:** `ExtensionStorage` persists `chrome.storage` data in `Storage/<id>.json`.
