import type { NativeGenericReply } from "@/types/extension";

export interface StorageAreaShim {
	readonly get: (
		keys?: unknown,
		cb?: (res: Record<string, unknown>) => void,
	) => Promise<Record<string, unknown>>;
	readonly set: (
		items: Record<string, unknown>,
		cb?: (res: { readonly status: "success" }) => void,
	) => Promise<{ readonly status: "success" }>;
	readonly remove: (
		keys: readonly string[] | string,
		cb?: (res: { readonly status: "success" }) => void,
	) => Promise<{ readonly status: "success" }>;
	readonly clear: (
		cb?: (res: { readonly status: "success" }) => void,
	) => Promise<{ readonly status: "success" }>;
}

export interface RuntimePortShim {
	readonly name: string;
	readonly onMessage: {
		readonly addListener: (fn: (msg: unknown) => void) => void;
		readonly removeListener: (fn: (msg: unknown) => void) => void;
	};
	readonly onDisconnect: {
		readonly addListener: (fn: () => void) => void;
		readonly removeListener: (fn: () => void) => void;
	};
	readonly postMessage: (msg: unknown) => void;
	readonly disconnect: () => void;
}

export interface ScopedShim {
	readonly runtime: {
		readonly id: string;
		readonly sendMessage: (
			payload: unknown,
			callback?: (res: NativeGenericReply) => void,
		) => Promise<NativeGenericReply>;
		readonly connect: (
			extensionIdOrInfo?: string | { readonly name?: string },
			connectInfo?: { readonly name?: string },
		) => RuntimePortShim;
		readonly onConnect: {
			readonly addListener: (fn: (port: RuntimePortShim) => void) => void;
			readonly removeListener: (
				fn: (port: RuntimePortShim) => void,
			) => void;
		};
		readonly onMessage: {
			readonly addListener: () => void;
			readonly removeListener: () => void;
		};
		readonly getURL: (path: string) => string;
	};
	readonly storage: {
		readonly local: StorageAreaShim;
		readonly sync: StorageAreaShim;
	};
	readonly i18n?: {
		readonly getMessage: (
			messageName: string,
			substitutions?: unknown,
		) => string;
		readonly getUILanguage: () => string;
		readonly getAcceptLanguages: (
			callback?: (languages: readonly string[]) => void,
		) => Promise<readonly string[]>;
	};
}

export function createShim(extensionId: string): ScopedShim {
	return {
		runtime: {
			id: extensionId,
			sendMessage: (
				payload: unknown,
				callback?: (res: NativeGenericReply) => void,
			) => {
				logInfo(
					`[Hosted:${extensionId}] runtime.sendMessage called with:`,
					payload,
				);
				const promise = safeSendMessage<NativeGenericReply>({
					type: "RUNTIME_SEND_MESSAGE",
					extensionId,
					payload,
				});
				if (typeof callback === "function") {
					promise
						.then((res) => callback(res))
						.catch(() => callback({}));
				}
				return promise;
			},
			connect: (extensionIdOrInfo, connectInfo) => {
				let targetId = extensionId;
				let info = connectInfo;
				if (
					typeof extensionIdOrInfo === "object" &&
					extensionIdOrInfo !== null
				) {
					info = extensionIdOrInfo;
				} else if (typeof extensionIdOrInfo === "string") {
					targetId = extensionIdOrInfo;
				}
				const portId = `port_${Date.now()}_${Math.random().toString(36).slice(2, 7)}`;
				const messageListeners = new Set<(msg: unknown) => void>();
				const disconnectListeners = new Set<() => void>();

				void safeSendMessage<NativeGenericReply>({
					type: "RUNTIME_PORT_CONNECT",
					extensionId: targetId,
					portId,
					name: info?.name || "",
				});

				return {
					name: info?.name || "",
					onMessage: {
						addListener(fn) {
							messageListeners.add(fn);
						},
						removeListener(fn) {
							messageListeners.delete(fn);
						},
					},
					onDisconnect: {
						addListener(fn) {
							disconnectListeners.add(fn);
						},
						removeListener(fn) {
							disconnectListeners.delete(fn);
						},
					},
					postMessage(msg) {
						void safeSendMessage<NativeGenericReply>({
							type: "RUNTIME_PORT_POST_MESSAGE",
							extensionId: targetId,
							portId,
							payload: msg,
						});
					},
					disconnect() {
						void safeSendMessage<NativeGenericReply>({
							type: "RUNTIME_PORT_DISCONNECT",
							extensionId: targetId,
							portId,
						});
					},
				};
			},
			onConnect: { addListener: () => {}, removeListener: () => {} },
			onMessage: { addListener: () => {}, removeListener: () => {} },
			getURL: (path: string) =>
				`ext-res://${extensionId}/${path.replace(/^\//, "")}`,
		},
		storage: {
			local: makeStorageArea("local"),
			sync: makeStorageArea("sync"),
		},
		i18n: {
			getMessage: (_messageName: string) => "",
			getUILanguage: () => navigator.language || "en",
			getAcceptLanguages: (cb) => {
				const langs = Array.from(navigator.languages || ["en"]);
				if (typeof cb === "function") cb(langs);
				return Promise.resolve(langs);
			},
		},
	};

	function makeStorageArea(area: "local" | "sync"): StorageAreaShim {
		return {
			get: (keys, cb) => {
				const promise = safeSendMessage<Record<string, unknown>>({
					type: "STORAGE_GET",
					extensionId,
					area,
					keys,
				}).then(
					(res) =>
						(res as { data?: Record<string, unknown> }).data ?? {},
				);
				if (cb) {
					promise.then(cb);
				}
				return promise;
			},
			set: (items, cb) => {
				const promise = safeSendMessage<{ readonly status: "success" }>(
					{ type: "STORAGE_SET", extensionId, area, items },
				);
				if (cb) {
					promise.then(cb);
				}
				return promise;
			},
			remove: (keys, cb) => {
				const keyList = Array.isArray(keys) ? keys : [keys];
				const promise = safeSendMessage<{ readonly status: "success" }>(
					{
						type: "STORAGE_REMOVE",
						extensionId,
						area,
						keys: keyList,
					},
				);
				if (cb) {
					promise.then(cb);
				}
				return promise;
			},
			clear: (cb) => {
				const promise = safeSendMessage<{ readonly status: "success" }>(
					{ type: "STORAGE_CLEAR", extensionId, area },
				);
				if (cb) {
					promise.then(cb);
				}
				return promise;
			},
		};
	}
}

export function scheduleScriptExecution(
	runAt: string | undefined,
	fn: () => void,
): void {
	if (runAt === "document_idle") {
		if (typeof window.requestIdleCallback === "function") {
			window.requestIdleCallback(() => fn(), { timeout: 2000 });
		} else {
			setTimeout(fn, 100);
		}
	} else if (runAt === "document_end") {
		if (document.readyState === "loading") {
			document.addEventListener("DOMContentLoaded", () => fn(), {
				once: true,
			});
		} else {
			fn();
		}
	} else {
		fn();
	}
}

export function evaluateScopedScript(
	code: string,
	extensionId: string,
	scriptPath?: string,
): void {
	logInfo(
		`Evaluating script for hosted extension: ${extensionId} (${scriptPath ?? "inline"})`,
	);
	const shim = createShim(extensionId);
	try {
		const runner = new Function(
			"chrome",
			"browser",
			"window",
			"document",
			`${code}\n//# sourceURL=ext://${extensionId}/${scriptPath ?? "content.js"}`,
		);
		runner(shim, shim, window, document);
	} catch (err) {
		const msg = err instanceof Error ? err.message : String(err);
		logError(`Error executing script for ${extensionId}:`, msg);
	}
}
