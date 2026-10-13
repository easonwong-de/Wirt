(() => {
	const extId = window.__HOST_EXTENSION_ID__ || "unknown";

	const shim = {
		runtime: {
			id: extId,
			sendMessage: (targetExtId, message, options, responseCallback) => {
				let msg = message;
				let cb = responseCallback;
				if (typeof targetExtId !== "string") {
					cb = message;
					msg = targetExtId;
				}
				return new Promise((resolve) => {
					window.webkit.messageHandlers.hostBridge.postMessage({
						api: "runtime.sendMessage",
						extensionId: extId,
						payload: msg,
					});
					if (typeof cb === "function") cb(null);
					resolve(null);
				});
			},
			onMessage: {
				listeners: new Set(),
				addListener(fn) {
					this.listeners.add(fn);
				},
				removeListener(fn) {
					this.listeners.delete(fn);
				},
			},
			getURL: (path) => `ext-bg://${extId}/${path.replace(/^\//, "")}`,
		},
		action: {
			setBadgeText: (details) => {
				window.webkit.messageHandlers.hostBridge.postMessage({
					api: "action.setBadgeText",
					extensionId: extId,
					text: details.text,
				});
			},
			setBadgeBackgroundColor: (details) => {
				window.webkit.messageHandlers.hostBridge.postMessage({
					api: "action.setBadgeBackgroundColor",
					extensionId: extId,
					color: details.color,
				});
			},
			onClicked: {
				listeners: new Set(),
				addListener(fn) {
					this.listeners.add(fn);
				},
				removeListener(fn) {
					this.listeners.delete(fn);
				},
			},
		},
		tabs: {
			query: (queryInfo) => {
				return new Promise((resolve) => {
					window.webkit.messageHandlers.hostBridge.postMessage({
						api: "tabs.query",
						extensionId: extId,
						queryInfo,
					});
					resolve([]);
				});
			},
		},
	};

	window.chrome = shim;
	window.browser = shim;
})();
