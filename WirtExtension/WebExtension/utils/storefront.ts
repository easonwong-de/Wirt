import type {
	ExtensionDescriptor,
	NativeInstalledExtensionsReply,
	NativeInstallPackageReply,
	NativeUninstallPackageReply,
} from "@/types/extension";

interface AmoApiResponse {
	readonly guid?: string;
	readonly slug?: string;
	readonly name?: string | Record<string, string>;
	readonly current_version?: { readonly file?: { readonly url?: string } };
}

interface AmoMetadata {
	readonly guid?: string;
	readonly slug: string;
	readonly name?: string;
	readonly names?: readonly string[];
	readonly xpiUrl?: string;
}

const amoMetadataCache = new Map<string, AmoMetadata>();
const amoPendingFetches = new Map<string, Promise<AmoMetadata | null>>();

let cachedInstalledExtensions: readonly ExtensionDescriptor[] = [];
let hasFetchedInstalled = false;

export function fetchInstalledExtensions(): Promise<
	readonly ExtensionDescriptor[]
> {
	return safeSendMessage<NativeInstalledExtensionsReply>({
		type: "GET_INSTALLED_EXTENSIONS",
	}).then((res) => {
		if (res.extensions && Array.isArray(res.extensions)) {
			cachedInstalledExtensions = res.extensions;
			hasFetchedInstalled = true;
		}
		return cachedInstalledExtensions;
	});
}

function fetchAmoMetadata(addonSlug: string): Promise<AmoMetadata | null> {
	const normalizedSlug = addonSlug.toLowerCase();
	const cached = amoMetadataCache.get(normalizedSlug);
	if (cached) {
		return Promise.resolve(cached);
	}

	const pending = amoPendingFetches.get(normalizedSlug);
	if (pending) {
		return pending;
	}

	const promise = fetch(
		`https://addons.mozilla.org/api/v5/addons/addon/${encodeURIComponent(normalizedSlug)}/`,
	)
		.then((res) =>
			res.ok ? (res.json() as Promise<AmoApiResponse>) : null,
		)
		.then((data) => {
			if (!data) {
				const fallbackMeta: AmoMetadata = { slug: normalizedSlug };
				amoMetadataCache.set(normalizedSlug, fallbackMeta);
				return fallbackMeta;
			}
			let name: string | undefined;
			let names: string[] = [];
			if (typeof data.name === "string") {
				name = data.name;
				names = [data.name];
			} else if (data.name && typeof data.name === "object") {
				names = Object.values(data.name).filter(
					(v): v is string => typeof v === "string",
				);
				name = data.name["en-US"] ?? data.name["en-GB"] ?? names[0];
			}
			const meta: AmoMetadata = {
				guid: typeof data.guid === "string" ? data.guid : undefined,
				slug:
					typeof data.slug === "string" ? data.slug : normalizedSlug,
				name,
				names,
				xpiUrl: data.current_version?.file?.url,
			};
			amoMetadataCache.set(normalizedSlug, meta);
			return meta;
		})
		.catch((err) => {
			const msg = err instanceof Error ? err.message : String(err);
			logWarn("Failed to query AMO API:", msg);
			const fallbackMeta: AmoMetadata = { slug: normalizedSlug };
			amoMetadataCache.set(normalizedSlug, fallbackMeta);
			return fallbackMeta;
		})
		.finally(() => {
			amoPendingFetches.delete(normalizedSlug);
		});

	amoPendingFetches.set(normalizedSlug, promise);
	return promise;
}

function findInstalledChromeExtension(
	extId: string,
): ExtensionDescriptor | undefined {
	const lowerId = extId.toLowerCase();
	return cachedInstalledExtensions.find(
		(ext) => ext.id.toLowerCase() === lowerId,
	);
}

function findInstalledMozillaExtension(
	addonSlug: string,
	meta?: AmoMetadata | null,
): ExtensionDescriptor | undefined {
	const targetSlug = (meta?.slug ?? addonSlug).toLowerCase();
	const targetGuid = meta?.guid?.toLowerCase();
	const targetNames = (meta?.names ?? (meta?.name ? [meta.name] : [])).map(
		(n) => n.toLowerCase(),
	);

	return cachedInstalledExtensions.find((ext) => {
		const extId = ext.id.toLowerCase();
		const extName = ext.name.toLowerCase();

		if (targetGuid && extId === targetGuid) return true;
		if (extId === targetSlug) return true;
		if (extId.startsWith(`${targetSlug}-`)) return true;
		if (
			targetNames.some(
				(n) =>
					extName === n || extName.includes(n) || n.includes(extName),
			)
		) {
			return true;
		}
		return false;
	});
}

function replaceButtonText(element: Element, newText: string): void {
	const htmlEl = element as HTMLElement;
	if (htmlEl.dataset?.wirtLabel === "true") {
		htmlEl.textContent = newText;
		element.setAttribute("aria-label", newText);
		return;
	}

	const tagged = element.querySelector<HTMLElement>(
		"[data-wirt-label='true']",
	);
	if (tagged) {
		tagged.textContent = newText;
		element.setAttribute("aria-label", newText);
		return;
	}

	const candidates = element.querySelectorAll<HTMLElement>(
		"span, div, p, b, strong",
	);
	let targetNode: HTMLElement | null = null;

	for (const node of candidates) {
		const text = (node.textContent ?? "").trim();
		if (text.length > 0 && node.children.length === 0) {
			targetNode = node;
			break;
		}
	}

	if (!targetNode) {
		for (const node of candidates) {
			const text = (node.textContent ?? "").trim();
			if (
				text.length > 0 &&
				!node.querySelector("svg, img, picture, canvas")
			) {
				targetNode = node;
				break;
			}
		}
	}

	if (targetNode) {
		targetNode.dataset.wirtLabel = "true";
		targetNode.textContent = newText;
		element.setAttribute("aria-label", newText);
		return;
	}

	for (const child of Array.from(element.childNodes)) {
		if (
			child.nodeType === Node.TEXT_NODE &&
			(child.textContent ?? "").trim().length > 0
		) {
			child.textContent = newText;
			element.setAttribute("aria-label", newText);
			return;
		}
	}

	htmlEl.dataset.wirtLabel = "true";
	element.textContent = newText;
	element.setAttribute("aria-label", newText);
}

function findChromeStoreActionButton(extId: string): HTMLElement | null {
	const bound = document.querySelectorAll<HTMLElement>(
		"button[data-wirt-bound='true']",
	);
	for (const btn of Array.from(bound)) {
		if (btn.dataset.wirtExtId === extId) {
			return btn;
		}
	}

	const h1 = document.querySelector<HTMLElement>("h1");
	if (h1) {
		let hero = h1.parentElement;
		while (hero && hero !== document.body && hero.tagName !== "MAIN") {
			const buttons = Array.from(
				hero.querySelectorAll<HTMLElement>("button"),
			);
			const actionBtn = buttons.find((btn) => {
				if (btn.dataset.wirtBound === "true") return true;
				if (
					btn.closest(
						"header, nav, [role='banner'], [role='navigation'], [role='tablist']",
					)
				) {
					return false;
				}
				if (
					btn.getAttribute("role") === "tab" ||
					btn.getAttribute("aria-haspopup") === "menu" ||
					btn.getAttribute("aria-haspopup") === "dialog"
				) {
					return false;
				}
				if (btn.querySelector("svg")) {
					return false;
				}
				const text = (btn.textContent ?? "").trim();
				return text.length > 0;
			});
			if (actionBtn) {
				return actionBtn;
			}
			hero = hero.parentElement;
		}
	}

	const main = document.querySelector<HTMLElement>("main");
	if (main) {
		const candidates = Array.from(
			main.querySelectorAll<HTMLElement>("button"),
		).filter((btn) => {
			if (btn.dataset.wirtBound === "true") return true;
			if (
				btn.closest(
					"header, nav, [role='banner'], [role='navigation'], [role='tablist']",
				)
			) {
				return false;
			}
			if (
				btn.getAttribute("role") === "tab" ||
				btn.getAttribute("aria-haspopup") === "menu" ||
				btn.getAttribute("aria-haspopup") === "dialog"
			) {
				return false;
			}
			if (btn.querySelector("svg")) {
				return false;
			}
			return (btn.textContent ?? "").trim().length > 0;
		});
		const disabled = candidates.find(
			(b) =>
				b.hasAttribute("disabled") ||
				b.getAttribute("aria-disabled") === "true",
		);
		if (disabled) {
			return disabled;
		}
		if (candidates.length === 1) {
			return candidates[0] ?? null;
		}
	}

	return null;
}

function hookChromeWebStore(): void {
	const match = window.location.pathname.match(
		/\/detail\/(?:[^\/]+\/)?([a-z0-9]{32})/i,
	);
	if (!match || !match[1]) {
		return;
	}

	const extId = match[1].toLowerCase();
	const targetBtn = findChromeStoreActionButton(extId);

	if (!targetBtn) {
		return;
	}

	const installedExt = findInstalledChromeExtension(extId);
	const isInstalled = Boolean(installedExt);

	targetBtn.removeAttribute("disabled");
	targetBtn.setAttribute("aria-disabled", "false");
	targetBtn.style.pointerEvents = "auto";
	targetBtn.style.cursor = "pointer";

	if (targetBtn.dataset.wirtExtId && targetBtn.dataset.wirtExtId !== extId) {
		targetBtn.dataset.wirtBound = "false";
		targetBtn.dataset.wirtState = "";
	}
	targetBtn.dataset.wirtExtId = extId;

	if (targetBtn.dataset.wirtBusy === "true") {
		return;
	}

	const desiredState = isInstalled ? "installed" : "not_installed";
	if (targetBtn.dataset.wirtState !== desiredState) {
		targetBtn.dataset.wirtState = desiredState;
		replaceButtonText(targetBtn, isInstalled ? "Remove" : "Add to Safari");
	}

	if (targetBtn.dataset.wirtBound === "true") {
		return;
	}
	targetBtn.dataset.wirtBound = "true";

	logInfo("Hooking Chrome Web Store button for extension:", extId);

	targetBtn.addEventListener(
		"click",
		(e: MouseEvent) => {
			e.preventDefault();
			e.stopPropagation();
			e.stopImmediatePropagation();

			if (targetBtn.dataset.wirtBusy === "true") {
				return;
			}

			const currentMatch = window.location.pathname.match(
				/\/detail\/(?:[^\/]+\/)?([a-z0-9]{32})/i,
			);
			const currentExtId =
				currentMatch && currentMatch[1]
					? currentMatch[1].toLowerCase()
					: extId;
			const currentInstalled = findInstalledChromeExtension(currentExtId);

			if (
				targetBtn.dataset.wirtState === "installed" ||
				currentInstalled
			) {
				targetBtn.dataset.wirtBusy = "true";
				targetBtn.style.pointerEvents = "none";
				replaceButtonText(targetBtn, "Removing…");
				logInfo(
					"User clicked Remove for Chrome extension:",
					currentExtId,
				);

				const targetIdToRemove = currentInstalled?.id ?? currentExtId;
				void safeSendMessage<NativeUninstallPackageReply>({
					type: "UNINSTALL_PACKAGE",
					extensionId: targetIdToRemove,
				}).then((res) => {
					if (res.status === "success") {
						logInfo(
							"Chrome extension removal succeeded:",
							currentExtId,
						);
						cachedInstalledExtensions =
							cachedInstalledExtensions.filter(
								(ext) =>
									ext.id.toLowerCase() !==
									targetIdToRemove.toLowerCase(),
							);
						replaceButtonText(targetBtn, "Removed ✓");
						setTimeout(() => {
							targetBtn.dataset.wirtState = "not_installed";
							targetBtn.dataset.wirtBusy = "false";
							replaceButtonText(targetBtn, "Add to Safari");
							targetBtn.style.pointerEvents = "auto";
						}, 1000);
					} else {
						logError("Chrome extension removal failed:", res);
						replaceButtonText(targetBtn, "Removal Failed ✕");
						setTimeout(() => {
							targetBtn.dataset.wirtBusy = "false";
							replaceButtonText(targetBtn, "Remove");
							targetBtn.style.pointerEvents = "auto";
						}, 2000);
					}
				});
			} else {
				targetBtn.dataset.wirtBusy = "true";
				targetBtn.style.pointerEvents = "none";
				replaceButtonText(targetBtn, "Adding to Safari…");
				logInfo(
					"User clicked Add to Safari for Chrome extension:",
					currentExtId,
				);

				const currentCrxUrl = `https://clients2.google.com/service/update2/crx?response=redirect&os=mac&arch=arm64&os_arch=arm64&nacl_arch=arm&prod=chromecrx&prodchannel=stable&prodversion=130.0.0.0&acceptformat=crx3,puff&x=id%3D${currentExtId}%26installsource%3Dondemand%26uc`;

				void safeSendMessage<NativeInstallPackageReply>({
					type: "INSTALL_PACKAGE_FROM_URL",
					downloadUrl: currentCrxUrl,
					referrer: window.location.href,
				}).then((res) => {
					if (res.status === "success") {
						logInfo(
							"Chrome extension installation succeeded:",
							res,
						);
						replaceButtonText(targetBtn, "Added to Safari ✓");
						void fetchInstalledExtensions().then(() => {
							setTimeout(() => {
								targetBtn.dataset.wirtState = "installed";
								targetBtn.dataset.wirtBusy = "false";
								replaceButtonText(targetBtn, "Remove");
								targetBtn.style.pointerEvents = "auto";
							}, 1200);
						});
					} else {
						logError("Chrome extension installation failed:", res);
						replaceButtonText(targetBtn, "Installation Failed ✕");
						setTimeout(() => {
							targetBtn.dataset.wirtBusy = "false";
							replaceButtonText(targetBtn, "Add to Safari");
							targetBtn.style.pointerEvents = "auto";
						}, 2500);
					}
				});
			}
		},
		true,
	);
}

function hookMozillaAddons(): void {
	const match = window.location.pathname.match(/\/addon\/([^\/]+)/i);
	if (!match || !match[1]) {
		return;
	}

	const addonSlug = decodeURIComponent(match[1]).toLowerCase();
	const meta = amoMetadataCache.get(addonSlug);
	if (!meta && !amoPendingFetches.has(addonSlug)) {
		void fetchAmoMetadata(addonSlug).then(() => {
			hookMozillaAddons();
		});
	}

	const installedExt = findInstalledMozillaExtension(addonSlug, meta);
	const isInstalled = Boolean(installedExt);

	const noticeLinks = document.querySelectorAll<HTMLElement>(
		".Notice a[href*='firefox/new'], .Notice a[href*='firefox.com']",
	);
	for (const link of noticeLinks) {
		const notice = link.closest<HTMLElement>(".Notice");
		if (notice) {
			notice.style.display = "none";
		}
	}

	const wrapper = document.querySelector<HTMLElement>(
		".InstallButtonWrapper",
	);
	if (!wrapper) {
		return;
	}

	const secondaryDl = wrapper.querySelector<HTMLElement>(
		".InstallButtonWrapper-download",
	);
	if (secondaryDl) {
		secondaryDl.style.display = "none";
	}

	const targetBtn = wrapper.querySelector<HTMLElement>(
		"a.Button, button.Button, .GetFirefoxButton a, .AMOPackageInstallButton, a, button",
	);
	if (!targetBtn) {
		return;
	}

	targetBtn.removeAttribute("disabled");
	targetBtn.setAttribute("aria-disabled", "false");
	targetBtn.removeAttribute("target");
	targetBtn.style.pointerEvents = "auto";
	targetBtn.style.cursor = "pointer";

	if (
		targetBtn.dataset.wirtSlug &&
		targetBtn.dataset.wirtSlug !== addonSlug
	) {
		targetBtn.dataset.wirtBound = "false";
		targetBtn.dataset.wirtState = "";
	}
	targetBtn.dataset.wirtSlug = addonSlug;

	if (targetBtn.dataset.wirtBusy === "true") {
		return;
	}

	const desiredState = isInstalled ? "installed" : "not_installed";
	if (targetBtn.dataset.wirtState !== desiredState) {
		targetBtn.dataset.wirtState = desiredState;
		replaceButtonText(targetBtn, isInstalled ? "Remove" : "Add to Safari");
	}

	if (targetBtn.dataset.wirtBound === "true") {
		return;
	}
	targetBtn.dataset.wirtBound = "true";

	logInfo("Hooking Mozilla Add-on button for slug:", addonSlug);

	targetBtn.addEventListener(
		"click",
		(e: MouseEvent) => {
			e.preventDefault();
			e.stopPropagation();
			e.stopImmediatePropagation();

			if (targetBtn.dataset.wirtBusy === "true") {
				return;
			}

			const currentMatch =
				window.location.pathname.match(/\/addon\/([^\/]+)/i);
			const currentSlug =
				currentMatch && currentMatch[1]
					? decodeURIComponent(currentMatch[1]).toLowerCase()
					: addonSlug;
			const currentMeta = amoMetadataCache.get(currentSlug) ?? meta;
			const currentInstalled = findInstalledMozillaExtension(
				currentSlug,
				currentMeta,
			);

			if (
				targetBtn.dataset.wirtState === "installed" ||
				currentInstalled
			) {
				targetBtn.dataset.wirtBusy = "true";
				targetBtn.style.pointerEvents = "none";
				replaceButtonText(targetBtn, "Removing…");
				logInfo("User clicked Remove for Mozilla add-on:", currentSlug);

				const targetIdToRemove =
					currentInstalled?.id ?? currentMeta?.guid ?? currentSlug;
				void safeSendMessage<NativeUninstallPackageReply>({
					type: "UNINSTALL_PACKAGE",
					extensionId: targetIdToRemove,
				}).then((res) => {
					if (res.status === "success") {
						logInfo(
							"Mozilla add-on removal succeeded:",
							currentSlug,
						);
						cachedInstalledExtensions =
							cachedInstalledExtensions.filter(
								(ext) =>
									ext.id.toLowerCase() !==
									targetIdToRemove.toLowerCase(),
							);
						replaceButtonText(targetBtn, "Removed ✓");
						setTimeout(() => {
							targetBtn.dataset.wirtState = "not_installed";
							targetBtn.dataset.wirtBusy = "false";
							replaceButtonText(targetBtn, "Add to Safari");
							targetBtn.style.pointerEvents = "auto";
						}, 1000);
					} else {
						logError("Mozilla add-on removal failed:", res);
						replaceButtonText(targetBtn, "Removal Failed ✕");
						setTimeout(() => {
							targetBtn.dataset.wirtBusy = "false";
							replaceButtonText(targetBtn, "Remove");
							targetBtn.style.pointerEvents = "auto";
						}, 2000);
					}
				});
			} else {
				targetBtn.dataset.wirtBusy = "true";
				targetBtn.style.pointerEvents = "none";
				replaceButtonText(targetBtn, "Adding to Safari…");
				logInfo(
					"User clicked Add to Safari for Mozilla add-on:",
					currentSlug,
				);

				let xpiUrl: string | null = null;
				const directAnchor =
					wrapper.querySelector<HTMLAnchorElement>(
						".InstallButtonWrapper-download-link",
					) ??
					document.querySelector<HTMLAnchorElement>(
						'a[href*="/firefox/downloads/file/"]',
					);
				if (directAnchor && directAnchor.href) {
					xpiUrl = directAnchor.href;
				}

				const fetchUrlPromise: Promise<string> = xpiUrl
					? Promise.resolve(xpiUrl)
					: fetchAmoMetadata(currentSlug).then(
							(fetchedMeta) =>
								fetchedMeta?.xpiUrl ??
								`https://addons.mozilla.org/firefox/downloads/latest/${encodeURIComponent(currentSlug)}/latest.xpi`,
						);

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
							replaceButtonText(targetBtn, "Added to Safari ✓");
							void fetchInstalledExtensions().then(() => {
								setTimeout(() => {
									targetBtn.dataset.wirtState = "installed";
									targetBtn.dataset.wirtBusy = "false";
									replaceButtonText(targetBtn, "Remove");
									targetBtn.style.pointerEvents = "auto";
								}, 1200);
							});
						} else {
							logError(
								"Mozilla add-on installation failed:",
								res,
							);
							replaceButtonText(
								targetBtn,
								"Installation Failed ✕",
							);
							setTimeout(() => {
								targetBtn.dataset.wirtBusy = "false";
								replaceButtonText(targetBtn, "Add to Safari");
								targetBtn.style.pointerEvents = "auto";
							}, 2500);
						}
					});
				});
			}
		},
		true,
	);
}

export function hookStorefronts(): void {
	if (window.top !== window) {
		return;
	}

	const host = window.location.hostname;
	if (host !== "chromewebstore.google.com" && host !== "addons.mozilla.org") {
		return;
	}

	let scanDebounceTimer: ReturnType<typeof setTimeout> | null = null;
	function triggerScan(): void {
		if (scanDebounceTimer !== null) {
			clearTimeout(scanDebounceTimer);
		}
		scanDebounceTimer = setTimeout(() => {
			scanDebounceTimer = null;
			scanAndHook();
		}, 120);
	}

	void fetchInstalledExtensions().then(() => {
		triggerScan();
	});

	window.addEventListener("focus", () => {
		void fetchInstalledExtensions().then(() => {
			triggerScan();
		});
	});

	function scanAndHook(): void {
		if (window.location.hostname === "chromewebstore.google.com") {
			hookChromeWebStore();
		} else if (window.location.hostname === "addons.mozilla.org") {
			hookMozillaAddons();
		}
	}

	scanAndHook();

	const observer = new MutationObserver(() => {
		triggerScan();
	});

	const rootElement = document.documentElement || document.body;
	if (rootElement) {
		observer.observe(rootElement, { childList: true, subtree: true });
	}
}
