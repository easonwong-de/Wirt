(() => {
	const extId = window.__HOST_EXTENSION_ID__ || "unknown";

	const pendingCallbacks = new Map();
	let requestCounter = 0;

	function callHostBridge(api, payload) {
		return new Promise((resolve, reject) => {
			const requestId = `${extId}_${Date.now()}_${++requestCounter}`;
			pendingCallbacks.set(requestId, { resolve, reject });
			window.webkit.messageHandlers.hostBridge.postMessage({
				api,
				extensionId: extId,
				requestId,
				...payload,
			});
		});
	}

	window.__wirtBridgeCallback = (requestId, result, error) => {
		const entry = pendingCallbacks.get(requestId);
		if (!entry) return;
		pendingCallbacks.delete(requestId);
		if (error) {
			entry.reject(new Error(error));
		} else {
			entry.resolve(result);
		}
	};

	window.__wirtDispatchRuntimeMessage = (envelope) => {
		const { correlationId, message, sender } = envelope;
		let isAsync = false;
		let replySent = false;

		const sendResponse = (payload) => {
			if (replySent) return;
			replySent = true;
			window.webkit.messageHandlers.hostBridge.postMessage({
				api: "runtime.onMessage.reply",
				callbackId: correlationId,
				payload: payload ?? {},
			});
		};

		for (const listener of shim.runtime.onMessage.listeners) {
			try {
				const result = listener(message, sender, sendResponse);
				if (result === true) {
					isAsync = true;
				}
			} catch (err) {
				console.error("[Wirt:Shim] onMessage listener error:", err);
			}
		}

		if (!isAsync && !replySent) {
			sendResponse({});
		}
	};

	const storageArea = {
		get(keys, cb) {
			const promise = callHostBridge("storage.get", { keys: keys ?? null });
			if (typeof cb === "function") {
				promise.then((res) => cb(res)).catch(() => cb({}));
			}
			return promise;
		},
		set(items, cb) {
			const promise = callHostBridge("storage.set", { items: items ?? {} });
			if (typeof cb === "function") {
				promise.then(() => cb()).catch(() => cb());
			}
			return promise;
		},
		remove(keys, cb) {
			const keyList = Array.isArray(keys) ? keys : [keys];
			const promise = callHostBridge("storage.remove", { keys: keyList });
			if (typeof cb === "function") {
				promise.then(() => cb()).catch(() => cb());
			}
			return promise;
		},
		clear(cb) {
			const promise = callHostBridge("storage.clear", {});
			if (typeof cb === "function") {
				promise.then(() => cb()).catch(() => cb());
			}
			return promise;
		},
	};

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
				const promise = callHostBridge("runtime.sendMessage", { payload: msg });
				if (typeof cb === "function") {
					promise.then((res) => cb(res)).catch(() => cb(null));
				}
				return promise;
			},
			onMessage: {
				listeners: new Set(),
				addListener(fn) {
					this.listeners.add(fn);
				},
				removeListener(fn) {
					this.listeners.delete(fn);
				},
				hasListener(fn) {
					return this.listeners.has(fn);
				},
			},
			getURL: (path) => `ext-bg://${extId}/${(path || "").replace(/^\//, "")}`,
		},
		storage: {
			local: storageArea,
			sync: storageArea,
			onChanged: {
				listeners: new Set(),
				addListener(fn) {
					this.listeners.add(fn);
				},
				removeListener(fn) {
					this.listeners.delete(fn);
				},
			},
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
				return callHostBridge("tabs.query", { queryInfo }).catch(() => []);
			},
		},
	};

	window.chrome = shim;
	window.browser = shim;
})();
