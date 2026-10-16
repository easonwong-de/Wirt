import type {
	ActiveTab,
	NativeActionClickReply,
	NativeGenericReply,
	NativeInstalledExtensionsReply,
	NativeInstallPackageReply,
	NativeMatchingScriptsReply,
	NativeOpenHostAppReply,
	RuntimeMessage,
} from "@/types/extension";

const LOG_TAG = "[Wirt:Background]";

function logInfo(
	...args: readonly (string | number | boolean | null | undefined | object)[]
): void {
	console.log(LOG_TAG, ...args);
}

function logWarn(
	...args: readonly (string | number | boolean | null | undefined | object)[]
): void {
	console.warn(LOG_TAG, ...args);
}

function logError(
	...args: readonly (string | number | boolean | null | undefined | object)[]
): void {
	console.error(LOG_TAG, ...args);
}

type NativeEnvelope =
	| { readonly type: "GET_INSTALLED_EXTENSIONS" }
	| {
			readonly type: "DISPATCH_ACTION_CLICK";
			readonly extensionId: string;
			readonly tab?: ActiveTab;
	  }
	| { readonly type: "OPEN_HOST_APP" }
	| { readonly type: "GET_MATCHING_SCRIPTS"; readonly url: string }
	| {
			readonly type: "RUNTIME_SEND_MESSAGE";
			readonly extensionId: string;
			readonly source: {
				readonly tabId?: number;
				readonly frameId?: number;
				readonly url?: string;
			};
			readonly payload: Record<string, string | number | boolean | null>;
	  }
	| {
			readonly type: "INSTALL_PACKAGE_FROM_URL";
			readonly downloadUrl: string;
			readonly referrer?: string;
	  };

function sendNativeEnvelope<T extends NativeGenericReply>(
	envelope: NativeEnvelope,
): Promise<T> {
	return new Promise((resolve) => {
		try {
			logInfo("Dispatching native message:", envelope.type, envelope);
			browser.runtime.sendNativeMessage(
				"application.id",
				envelope,
				(response: T | undefined) => {
					const err = browser.runtime.lastError;
					if (err) {
						logError(
							"Native messaging error for",
							envelope.type,
							err.message || String(err),
						);
						const fallback: NativeGenericReply = {
							error: err.message || String(err),
						};
						resolve(fallback as T);
					} else {
						logInfo(
							"Received native response for",
							envelope.type,
							response,
						);
						resolve(
							(response ??
								({
									status: "success",
								} as NativeGenericReply)) as T,
						);
					}
				},
			);
		} catch (err) {
			const message = err instanceof Error ? err.message : String(err);
			logError("Failed to invoke sendNativeMessage:", message);
			const fallback: NativeGenericReply = { error: message };
			resolve(fallback as T);
		}
	});
}

export default defineBackground(() => {
	logInfo("Background service worker initialised");

	browser.runtime.onMessage.addListener(
		(
			request: RuntimeMessage | null | undefined,
			sender: Browser.runtime.MessageSender,
			sendResponse: (response: NativeGenericReply) => void,
		): boolean => {
			if (!request || !request.type) {
				return false;
			}

			logInfo(
				"Received runtime message:",
				request.type,
				"from sender:",
				sender.url || `tab:${sender.tab?.id ?? "unknown"}`,
			);

			if (request.type === "GET_INSTALLED_EXTENSIONS") {
				sendNativeEnvelope<NativeInstalledExtensionsReply>({
					type: "GET_INSTALLED_EXTENSIONS",
				})
					.then((res) => sendResponse(res))
					.catch((err: Error | string) => {
						const message =
							err instanceof Error ? err.message : String(err);
						logError("Error in GET_INSTALLED_EXTENSIONS:", message);
						sendResponse({ error: message });
					});
				return true;
			}

			if (request.type === "DISPATCH_ACTION_CLICK") {
				sendNativeEnvelope<NativeActionClickReply>({
					type: "DISPATCH_ACTION_CLICK",
					extensionId: request.extensionId,
					tab: request.tab,
				})
					.then((res) => sendResponse(res))
					.catch((err: Error | string) => {
						const message =
							err instanceof Error ? err.message : String(err);
						logError("Error in DISPATCH_ACTION_CLICK:", message);
						sendResponse({ error: message });
					});
				return true;
			}

			if (request.type === "OPEN_HOST_APP") {
				sendNativeEnvelope<NativeOpenHostAppReply>({
					type: "OPEN_HOST_APP",
				})
					.then((res) => sendResponse(res))
					.catch((err: Error | string) => {
						const message =
							err instanceof Error ? err.message : String(err);
						logError("Error in OPEN_HOST_APP:", message);
						sendResponse({ error: message });
					});
				return true;
			}

			if (request.type === "GET_MATCHING_SCRIPTS") {
				sendNativeEnvelope<NativeMatchingScriptsReply>({
					type: "GET_MATCHING_SCRIPTS",
					url: request.url,
				})
					.then((res) => sendResponse(res))
					.catch((err: Error | string) => {
						const message =
							err instanceof Error ? err.message : String(err);
						logError("Error in GET_MATCHING_SCRIPTS:", message);
						sendResponse({ matchingExtensions: [] });
					});
				return true;
			}

			if (request.type === "RUNTIME_SEND_MESSAGE") {
				sendNativeEnvelope<NativeGenericReply>({
					type: "RUNTIME_SEND_MESSAGE",
					extensionId: request.extensionId,
					source: {
						tabId: sender.tab?.id,
						frameId: sender.frameId,
						url: sender.url,
					},
					payload: request.payload,
				})
					.then((res) => sendResponse(res))
					.catch((err: Error | string) => {
						const message =
							err instanceof Error ? err.message : String(err);
						logError("Error in RUNTIME_SEND_MESSAGE:", message);
						sendResponse({ error: message });
					});
				return true;
			}

			if (request.type === "INSTALL_PACKAGE_FROM_URL") {
				logInfo("Installing package from URL:", request.downloadUrl);
				sendNativeEnvelope<NativeInstallPackageReply>({
					type: "INSTALL_PACKAGE_FROM_URL",
					downloadUrl: request.downloadUrl,
					referrer: request.referrer,
				})
					.then((res) => {
						logInfo("Installation completed with response:", res);
						sendResponse(res);
					})
					.catch((err: Error | string) => {
						const message =
							err instanceof Error ? err.message : String(err);
						logError("Error in INSTALL_PACKAGE_FROM_URL:", message);
						sendResponse({ error: message });
					});
				return true;
			}

			return false;
		},
	);

	browser.webNavigation.onBeforeNavigate.addListener((details) => {
		if (details.frameId !== 0) {
			return;
		}
		try {
			const url = new URL(details.url);
			const isCrx = url.pathname.endsWith(".crx");
			const isXpi =
				url.pathname.endsWith(".xpi") ||
				url.pathname.includes("/downloads/file/");

			if (isCrx || isXpi) {
				logInfo(
					"Navigation interceptor matched package URL:",
					details.url,
				);
				void sendNativeEnvelope<NativeInstallPackageReply>({
					type: "INSTALL_PACKAGE_FROM_URL",
					downloadUrl: details.url,
				});
			}
		} catch (err) {
			const message = err instanceof Error ? err.message : String(err);
			logWarn("Error parsing navigation URL:", message);
		}
	});
});
