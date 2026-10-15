import type {
	NativeGenericReply,
	NativeInstallPackageReply,
	NativeMatchingScriptsReply,
	RuntimeMessage,
} from "@/types/extension";

interface AmoApiResponse {
	readonly current_version?: { readonly file?: { readonly url?: string } };
}

interface ScopedShim {
	readonly runtime: {
		readonly id: string;
		readonly sendMessage: (
			payload: Record<string, string | number | boolean | null>,
			callback?: (res: NativeGenericReply) => void,
		) => Promise<NativeGenericReply>;
		readonly onMessage: {
			readonly addListener: () => void;
			readonly removeListener: () => void;
		};
		readonly getURL: (path: string) => string;
	};
	readonly storage: {
		readonly local: {
			readonly get: (
				keys: readonly string[] | string,
				cb?: (
					res: Record<string, string | number | boolean | null>,
				) => void,
			) => Promise<Record<string, string | number | boolean | null>>;
			readonly set: (
				items: Record<string, string | number | boolean | null>,
				cb?: (res: { readonly status: "success" }) => void,
			) => Promise<{ readonly status: "success" }>;
		};
	};
}

const LOG_TAG = "[SafariExtensionHost:Content]";

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

function safeSendMessage<T extends NativeGenericReply>(
	message: RuntimeMessage,
): Promise<T> {
	return new Promise((resolve) => {
		try {
			logInfo("Sending runtime message:", message.type, message);
			const promise = browser.runtime.sendMessage(message) as
				Promise<T> | undefined;
			if (promise && typeof promise.then === "function") {
				promise
					.then((res: T | undefined) => {
						logInfo(
							"Received response for message:",
							message.type,
							res,
						);
						resolve(
							(res ??
								({
									status: "success",
								} as NativeGenericReply)) as T,
						);
					})
					.catch((err) => {
						const msg =
							err instanceof Error ? err.message : String(err);
						logWarn(
							"Runtime message suppressed rejection:",
							message.type,
							msg,
						);
						resolve({ error: msg } as T);
					});
			} else {
				resolve({} as T);
			}
		} catch (err) {
			const msg = err instanceof Error ? err.message : String(err);
			logWarn("Failed to invoke runtime.sendMessage:", msg);
			resolve({ error: msg } as T);
		}
	});
}

function replaceButtonText(element: Element, newText: string): void {
	const targetRegex =
		/download firefox|add to firefox|available on|add to chrome|add to safari|adding to safari|added to safari/i;
	const candidates = element.querySelectorAll("span, div, p");
	let updated = false;

	for (const node of candidates) {
		const text = (node.textContent ?? "").trim();
		if (targetRegex.test(text)) {
			for (const child of Array.from(node.childNodes)) {
				if (
					child.nodeType === Node.TEXT_NODE &&
					(child.textContent ?? "").trim().length > 0
				) {
					child.textContent = newText;
					updated = true;
					break;
				}
			}
			if (!updated && node.children.length === 0) {
				node.textContent = newText;
				updated = true;
				break;
			}
		}
	}

	if (!updated) {
		for (const child of Array.from(element.childNodes)) {
			if (
				child.nodeType === Node.TEXT_NODE &&
				(child.textContent ?? "").trim().length > 0
			) {
				child.textContent = newText;
				updated = true;
				break;
			}
		}
	}

	if (!updated) {
		element.textContent = newText;
	}
}

function hookChromeWebStore(): void {
	const match = window.location.pathname.match(
		/\/detail\/(?:[^\/]+\/)?([a-z0-9]{32})/i,
	);
	if (!match || !match[1]) {
		return;
	}

	const extId = match[1];
	const crxUrl = `https://clients2.google.com/service/update2/crx?response=redirect&os=mac&arch=arm64&os_arch=arm64&nacl_arch=arm&prod=chromecrx&prodchannel=stable&prodversion=130.0.0.0&acceptformat=crx3,puff&x=id%3D${extId}%26installsource%3Dondemand%26uc`;

	const buttons = document.querySelectorAll<HTMLElement>(
		"button, [role='button'], div[ccl-id] button",
	);
	for (const btn of buttons) {
		const text = (btn.textContent ?? "").trim();
		if (
			/available on chrome/i.test(text) ||
			/add to chrome/i.test(text) ||
			/available on/i.test(text)
		) {
			if (btn.dataset.hostHooked === extId) {
				continue;
			}
			btn.dataset.hostHooked = extId;

			logInfo("Hooking Chrome Web Store button for extension:", extId);
			replaceButtonText(btn, "Add to Safari");
			btn.removeAttribute("disabled");
			btn.setAttribute("aria-disabled", "false");
			btn.style.pointerEvents = "auto";
			btn.style.cursor = "pointer";

			btn.addEventListener(
				"click",
				(e: MouseEvent) => {
					e.preventDefault();
					e.stopPropagation();
					e.stopImmediatePropagation();

					logInfo(
						"User clicked Add to Safari for Chrome extension:",
						extId,
					);
					replaceButtonText(btn, "Adding to Safari…");
					btn.style.pointerEvents = "none";

					void safeSendMessage<NativeInstallPackageReply>({
						type: "INSTALL_PACKAGE_FROM_URL",
						downloadUrl: crxUrl,
						referrer: window.location.href,
					}).then((res) => {
						if (res.status === "success") {
							logInfo(
								"Chrome extension installation succeeded:",
								res,
							);
							replaceButtonText(btn, "Added to Safari ✓");
						} else {
							logError(
								"Chrome extension installation failed:",
								res,
							);
							replaceButtonText(btn, "Installation Failed ✕");
							setTimeout(() => {
								replaceButtonText(btn, "Add to Safari");
								btn.style.pointerEvents = "auto";
							}, 3000);
						}
					});
				},
				true,
			);
		}
	}
}

function hookMozillaAddons(): void {
	const match = window.location.pathname.match(/\/addon\/([^\/]+)/i);
	if (!match || !match[1]) {
		return;
	}

	const addonSlug = match[1];
	const candidates = document.querySelectorAll<HTMLElement>(
		"a, button, [role='button'], .Button--action, .InstallButtonWrapper-download-button",
	);

	for (const el of candidates) {
		const text = (el.textContent ?? "").trim();
		const href = el.getAttribute("href") ?? "";
		const isAmoButton =
			/download firefox/i.test(text) ||
			/add to firefox/i.test(text) ||
			href.includes("mozilla.org/firefox/new");

		if (isAmoButton) {
			if (el.dataset.hostHooked === addonSlug) {
				continue;
			}
			el.dataset.hostHooked = addonSlug;

			logInfo("Hooking Mozilla Add-on button for slug:", addonSlug);
			replaceButtonText(el, "Add to Safari");
			el.removeAttribute("target");
			el.style.cursor = "pointer";

			el.addEventListener(
				"click",
				(e: MouseEvent) => {
					e.preventDefault();
					e.stopPropagation();
					e.stopImmediatePropagation();

					logInfo(
						"User clicked Add to Safari for Mozilla add-on:",
						addonSlug,
					);
					replaceButtonText(el, "Adding to Safari…");
					el.style.pointerEvents = "none";

					let xpiUrl: string | null = null;
					const directAnchor =
						document.querySelector<HTMLAnchorElement>(
							'a[href*="/firefox/downloads/file/"]',
						);
					if (directAnchor && directAnchor.href) {
						xpiUrl = directAnchor.href;
					}

					const fetchUrlPromise: Promise<string> = xpiUrl
						? Promise.resolve(xpiUrl)
						: fetch(
								`https://addons.mozilla.org/api/v5/addons/addon/${addonSlug}/`,
							)
								.then((apiRes) =>
									apiRes.ok
										? (apiRes.json() as Promise<AmoApiResponse>)
										: null,
								)
								.then(
									(apiData) =>
										apiData?.current_version?.file?.url ??
										`https://addons.mozilla.org/firefox/downloads/latest/${addonSlug}/latest.xpi`,
								)
								.catch((fetchErr) => {
									const msg =
										fetchErr instanceof Error
											? fetchErr.message
											: String(fetchErr);
									logWarn("Failed to query AMO API:", msg);
									return `https://addons.mozilla.org/firefox/downloads/latest/${addonSlug}/latest.xpi`;
								});

					void fetchUrlPromise.then((resolvedUrl) => {
						logInfo("Dispatched XPI download URL:", resolvedUrl);
						return safeSendMessage<NativeInstallPackageReply>({
							type: "INSTALL_PACKAGE_FROM_URL",
							downloadUrl: resolvedUrl,
							referrer: window.location.href,
						}).then((res) => {
							if (res.status === "success") {
								logInfo(
									"Mozilla add-on installation succeeded:",
									res,
								);
								replaceButtonText(el, "Added to Safari ✓");
							} else {
								logError(
									"Mozilla add-on installation failed:",
									res,
								);
								replaceButtonText(el, "Installation Failed ✕");
								setTimeout(() => {
									replaceButtonText(el, "Add to Safari");
									el.style.pointerEvents = "auto";
								}, 3000);
							}
						});
					});
				},
				true,
			);
		}
	}

	const notices = document.querySelectorAll<HTMLElement>(
		".Notice-warning, .AMOPromotion",
	);
	for (const notice of notices) {
		if (/need firefox|download firefox/i.test(notice.textContent ?? "")) {
			notice.style.display = "none";
		}
	}
}

function hookStorefronts(): void {
	const host = window.location.hostname;
	if (host !== "chromewebstore.google.com" && host !== "addons.mozilla.org") {
		return;
	}

	function scanAndHook(): void {
		if (window.location.hostname === "chromewebstore.google.com") {
			hookChromeWebStore();
		} else if (window.location.hostname === "addons.mozilla.org") {
			hookMozillaAddons();
		}
	}

	scanAndHook();

	const observer = new MutationObserver(() => {
		scanAndHook();
	});

	const rootElement = document.documentElement || document.body;
	if (rootElement) {
		observer.observe(rootElement, { childList: true, subtree: true });
	}
}

function interceptDownloadClicks(): void {
	document.addEventListener(
		"click",
		(event: MouseEvent) => {
			const target = event.target as HTMLElement | null;
			const anchor = target?.closest(
				"a[href]",
			) as HTMLAnchorElement | null;
			if (!anchor) {
				return;
			}

			const href = anchor.getAttribute("href") || anchor.href;
			if (!href) {
				return;
			}

			try {
				const url = new URL(href, window.location.href);
				const isCrx = url.pathname.endsWith(".crx");
				const isXpi =
					url.pathname.endsWith(".xpi") ||
					url.pathname.includes("/downloads/file/");

				if (isCrx || isXpi) {
					logInfo("Direct package download link clicked:", url.href);
					event.preventDefault();
					event.stopPropagation();
					void safeSendMessage<NativeInstallPackageReply>({
						type: "INSTALL_PACKAGE_FROM_URL",
						downloadUrl: url.href,
						referrer: window.location.href,
					});
				}
			} catch {
				// Ignored
			}
		},
		true,
	);
}

function createShim(extensionId: string): ScopedShim {
	return {
		runtime: {
			id: extensionId,
			sendMessage: (
				payload: Record<string, string | number | boolean | null>,
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
			onMessage: { addListener: () => {}, removeListener: () => {} },
			getURL: (path: string) =>
				`ext-res://${extensionId}/${path.replace(/^\//, "")}`,
		},
		storage: {
			local: {
				get: (
					keys: readonly string[] | string,
					cb?: (
						res: Record<string, string | number | boolean | null>,
					) => void,
				) => {
					const promise = safeSendMessage<
						Record<string, string | number | boolean | null>
					>({
						type: "STORAGE_GET",
						extensionId,
						area: "local",
						keys,
					});
					if (cb) {
						promise.then(cb);
					}
					return promise;
				},
				set: (
					items: Record<string, string | number | boolean | null>,
					cb?: (res: { readonly status: "success" }) => void,
				) => {
					const promise = safeSendMessage<{
						readonly status: "success";
					}>({
						type: "STORAGE_SET",
						extensionId,
						area: "local",
						items,
					});
					if (cb) {
						promise.then(cb);
					}
					return promise;
				},
			},
		},
	};
}

function evaluateScopedScript(
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

async function initialiseMatchingScripts(): Promise<void> {
	try {
		logInfo("Requesting matched scripts for URL:", window.location.href);
		const response = await safeSendMessage<NativeMatchingScriptsReply>({
			type: "GET_MATCHING_SCRIPTS",
			url: window.location.href,
		});

		if (
			!response.matchingExtensions ||
			response.matchingExtensions.length === 0
		) {
			logInfo("No matching third-party extension scripts for this page.");
			return;
		}

		logInfo(
			"Found matching extensions:",
			response.matchingExtensions.map((e) => e.id),
		);

		for (const ext of response.matchingExtensions) {
			if (ext.styles) {
				for (const cssText of ext.styles) {
					const style = document.createElement("style");
					style.setAttribute("data-hosted-ext", ext.id);
					style.textContent = cssText;
					(document.head || document.documentElement).appendChild(
						style,
					);
				}
			}

			if (ext.scripts) {
				for (const scriptItem of ext.scripts) {
					evaluateScopedScript(
						scriptItem.code,
						ext.id,
						scriptItem.path,
					);
				}
			}
		}
	} catch (err) {
		const msg = err instanceof Error ? err.message : String(err);
		logError("Failed to initialise matching scripts:", msg);
	}
}

export default defineContentScript({
	matches: ["<all_urls>"],
	runAt: "document_start",
	allFrames: true,
	main() {
		if (!window.location.protocol.startsWith("http")) {
			return;
		}

		logInfo("Bootstrapper content script active on:", window.location.href);

		interceptDownloadClicks();
		hookStorefronts();
		void initialiseMatchingScripts();
	},
});
