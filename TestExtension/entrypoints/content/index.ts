import "./style.css";
import type { CounterState } from "@/types/extension";
import { getStoredState, sendCounterMessage } from "@/utils/storage";

const OVERLAY_ID = "wirt-test-overlay";

function updateOverlayUI(state: CounterState): void {
	const numEl = document.getElementById("wirt-overlay-number-value");
	const metaEl = document.getElementById("wirt-overlay-meta-value");
	if (numEl) {
		numEl.textContent = String(state.count);
		if (state.count > 0) {
			numEl.style.color = "#30d158";
		} else if (state.count < 0) {
			numEl.style.color = "#ff453a";
		} else {
			numEl.style.color = "#0a84ff";
		}
	}
	if (metaEl) {
		metaEl.textContent = `from: ${state.lastModifiedBy}`;
	}
}

async function mountOverlay(): Promise<void> {
	if (document.getElementById(OVERLAY_ID)) {
		return;
	}

	const container = document.createElement("div");
	container.id = OVERLAY_ID;

	const title = document.createElement("div");
	title.className = "wirt-overlay-title";
	title.textContent = "Wirt Test Overlay";

	const numberEl = document.createElement("div");
	numberEl.id = "wirt-overlay-number-value";
	numberEl.className = "wirt-overlay-number";
	numberEl.textContent = "0";

	const metaEl = document.createElement("div");
	metaEl.id = "wirt-overlay-meta-value";
	metaEl.className = "wirt-overlay-meta";
	metaEl.textContent = "from: initial";

	// Section 1: Runtime Messages
	const msgSection = document.createElement("div");
	msgSection.className = "wirt-overlay-section";

	const msgLabel = document.createElement("div");
	msgLabel.className = "wirt-overlay-section-label";
	msgLabel.textContent = "Runtime Message";

	const msgControls = document.createElement("div");
	msgControls.className = "wirt-overlay-controls";

	const decBtn = document.createElement("button");
	decBtn.className = "wirt-overlay-btn";
	decBtn.textContent = "-1";
	decBtn.addEventListener("click", async () => {
		const res = await sendCounterMessage({
			type: "INCREMENT_COUNT",
			delta: -1,
			source: "content",
		});
		if (res.status === "ok" && typeof res.count === "number") {
			updateOverlayUI({
				count: res.count,
				lastModifiedBy: "content",
				lastModifiedAt: new Date().toISOString(),
			});
		}
	});

	const incBtn = document.createElement("button");
	incBtn.className = "wirt-overlay-btn";
	incBtn.textContent = "+1";
	incBtn.addEventListener("click", async () => {
		const res = await sendCounterMessage({
			type: "INCREMENT_COUNT",
			delta: 1,
			source: "content",
		});
		if (res.status === "ok" && typeof res.count === "number") {
			updateOverlayUI({
				count: res.count,
				lastModifiedBy: "content",
				lastModifiedAt: new Date().toISOString(),
			});
		}
	});

	msgControls.appendChild(decBtn);
	msgControls.appendChild(incBtn);
	msgSection.appendChild(msgLabel);
	msgSection.appendChild(msgControls);

	// Section 2: Port Stream Connection
	const portSection = document.createElement("div");
	portSection.className = "wirt-overlay-section";

	const portLabel = document.createElement("div");
	portLabel.className = "wirt-overlay-section-label";
	portLabel.textContent = "Port Stream";

	const portControls = document.createElement("div");
	portControls.className = "wirt-overlay-controls";

	const portDecBtn = document.createElement("button");
	portDecBtn.className = "wirt-overlay-btn";
	portDecBtn.textContent = "-1";
	portDecBtn.addEventListener("click", () => {
		try {
			const port = browser.runtime.connect?.({
				name: "content-counter-stream",
			});
			port?.postMessage?.({ type: "PORT_STREAM_UPDATE", delta: -1 });
			setTimeout(() => port?.disconnect?.(), 50);
		} catch (err) {
			console.warn("browser.runtime.connect error:", err);
		}
	});

	const portIncBtn = document.createElement("button");
	portIncBtn.className = "wirt-overlay-btn";
	portIncBtn.textContent = "+1";
	portIncBtn.addEventListener("click", () => {
		try {
			const port = browser.runtime.connect?.({
				name: "content-counter-stream",
			});
			port?.postMessage?.({ type: "PORT_STREAM_UPDATE", delta: 1 });
			setTimeout(() => port?.disconnect?.(), 50);
		} catch (err) {
			console.warn("browser.runtime.connect error:", err);
		}
	});

	portControls.appendChild(portDecBtn);
	portControls.appendChild(portIncBtn);
	portSection.appendChild(portLabel);
	portSection.appendChild(portControls);

	container.appendChild(title);
	container.appendChild(numberEl);
	container.appendChild(metaEl);
	container.appendChild(msgSection);
	container.appendChild(portSection);

	(document.body || document.documentElement).appendChild(container);

	// Load initial state via storage API
	const initial = await getStoredState();
	updateOverlayUI(initial);
}

export default defineContentScript({
	matches: ["<all_urls>"],
	runAt: "document_idle",
	main() {
		if (!window.location.protocol.startsWith("http")) {
			return;
		}

		void mountOverlay();

		// Listen to storage changes across all pages/popups/background
		browser.storage?.onChanged?.addListener((changes) => {
			if (changes.counterState?.newValue) {
				updateOverlayUI(changes.counterState.newValue as CounterState);
			}
		});
	},
});
