(() => {
	if (!window.location.protocol.startsWith("http")) {
		return;
	}

	const LOG_TAG = "[SafariExtensionHost:Content]";

	function logInfo(...args) {
		console.log(LOG_TAG, ...args);
	}

	function logWarn(...args) {
		console.warn(LOG_TAG, ...args);
	}

	function logError(...args) {
		console.error(LOG_TAG, ...args);
	}

	logInfo("Bootstrapper content script active on:", window.location.href);

	function safeSendMessage(message) {
		return new Promise((resolve) => {
			try {
				logInfo("Sending runtime message:", message.type, message);
				const promise = browser.runtime.sendMessage(message);
				if (promise && typeof promise.then === "function") {
					promise
						.then((res) => {
							logInfo(
								"Received response for message:",
								message.type,
								res,
							);
							resolve(res || {});
						})
						.catch((err) => {
							logWarn(
								"Runtime message suppressed rejection:",
								message.type,
								err,
							);
							resolve({});
						});
				} else {
					resolve({});
				}
			} catch (err) {
				logWarn("Failed to invoke runtime.sendMessage:", err);
				resolve({});
			}
		});
	}

	function replaceButtonText(element, newText) {
		const targetRegex =
			/download firefox|add to firefox|available on|add to chrome|add to safari|adding to safari|added to safari/i;
		const candidates = element.querySelectorAll("span, div, p");
		let updated = false;

		for (const node of candidates) {
			const text = (node.textContent || "").trim();
			if (targetRegex.test(text)) {
				for (const child of node.childNodes) {
					if (
						child.nodeType === Node.TEXT_NODE &&
						child.textContent.trim().length > 0
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
			for (const child of element.childNodes) {
				if (
					child.nodeType === Node.TEXT_NODE &&
					child.textContent.trim().length > 0
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

	function hookChromeWebStore() {
		const match = window.location.pathname.match(
			/\/detail\/(?:[^\/]+\/)?([a-z0-9]{32})/i,
		);
		if (!match) return;

		const extId = match[1];
		const crxUrl = `https://clients2.google.com/service/update2/crx?response=redirect&os=mac&arch=arm64&os_arch=arm64&nacl_arch=arm&prod=chromecrx&prodchannel=stable&prodversion=130.0.0.0&acceptformat=crx3,puff&x=id%3D${extId}%26installsource%3Dondemand%26uc`;

		const buttons = document.querySelectorAll(
			"button, [role='button'], div[ccl-id] button",
		);
		for (const btn of buttons) {
			const text = (btn.textContent || "").trim();
			if (
				/available on chrome/i.test(text) ||
				/add to chrome/i.test(text) ||
				/available on/i.test(text)
			) {
				if (btn.dataset.hostHooked === extId) continue;
				btn.dataset.hostHooked = extId;

				logInfo(
					"Hooking Chrome Web Store button for extension:",
					extId,
				);
				replaceButtonText(btn, "Add to Safari");
				btn.removeAttribute("disabled");
				btn.setAttribute("aria-disabled", "false");
				btn.style.pointerEvents = "auto";
				btn.style.cursor = "pointer";

				btn.addEventListener(
					"click",
					async (e) => {
						e.preventDefault();
						e.stopPropagation();
						e.stopImmediatePropagation();

						logInfo(
							"User clicked Add to Safari for Chrome extension:",
							extId,
						);
						replaceButtonText(btn, "Adding to Safari…");
						btn.style.pointerEvents = "none";

						const res = await safeSendMessage({
							type: "INSTALL_PACKAGE_FROM_URL",
							downloadUrl: crxUrl,
							referrer: window.location.href,
						});

						if (res && res.status === "success") {
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
					},
					true,
				);
			}
		}
	}

	function hookMozillaAddons() {
		const match = window.location.pathname.match(/\/addon\/([^\/]+)/i);
		if (!match) return;

		const addonSlug = match[1];
		const candidates = document.querySelectorAll(
			"a, button, [role='button'], .Button--action, .InstallButtonWrapper-download-button",
		);

		for (const el of candidates) {
			const text = (el.textContent || "").trim();
			const href = el.getAttribute("href") || "";
			const isAmoButton =
				/download firefox/i.test(text) ||
				/add to firefox/i.test(text) ||
				href.includes("mozilla.org/firefox/new");

			if (isAmoButton) {
				if (el.dataset.hostHooked === addonSlug) continue;
				el.dataset.hostHooked = addonSlug;

				logInfo("Hooking Mozilla Add-on button for slug:", addonSlug);
				replaceButtonText(el, "Add to Safari");
				el.removeAttribute("target");
				el.style.cursor = "pointer";

				el.addEventListener(
					"click",
					async (e) => {
						e.preventDefault();
						e.stopPropagation();
						e.stopImmediatePropagation();

						logInfo(
							"User clicked Add to Safari for Mozilla add-on:",
							addonSlug,
						);
						replaceButtonText(el, "Adding to Safari…");
						el.style.pointerEvents = "none";

						let xpiUrl = null;
						const directAnchor = document.querySelector(
							'a[href*="/firefox/downloads/file/"]',
						);
						if (directAnchor && directAnchor.href) {
							xpiUrl = directAnchor.href;
						}

						if (!xpiUrl) {
							try {
								logInfo(
									"Fetching Mozilla add-on metadata from API for:",
									addonSlug,
								);
								const apiRes = await fetch(
									`https://addons.mozilla.org/api/v5/addons/addon/${addonSlug}/`,
								);
								if (apiRes.ok) {
									const apiData = await apiRes.json();
									xpiUrl =
										apiData?.current_version?.file?.url;
								}
							} catch (fetchErr) {
								logWarn("Failed to query AMO API:", fetchErr);
							}
						}

						if (!xpiUrl) {
							xpiUrl = `https://addons.mozilla.org/firefox/downloads/latest/${addonSlug}/latest.xpi`;
						}

						logInfo("Dispatched XPI download URL:", xpiUrl);
						const res = await safeSendMessage({
							type: "INSTALL_PACKAGE_FROM_URL",
							downloadUrl: xpiUrl,
							referrer: window.location.href,
						});

						if (res && res.status === "success") {
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
					},
					true,
				);
			}
		}

		const notices = document.querySelectorAll(
			".Notice-warning, .AMOPromotion",
		);
		for (const notice of notices) {
			if (
				/need firefox|download firefox/i.test(notice.textContent || "")
			) {
				notice.style.display = "none";
			}
		}
	}

	function hookStorefronts() {
		const host = window.location.hostname;
		if (
			host !== "chromewebstore.google.com" &&
			host !== "addons.mozilla.org"
		) {
			return;
		}

		function scanAndHook() {
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

		observer.observe(document.documentElement || document.body, {
			childList: true,
			subtree: true,
		});
	}

	function interceptDownloadClicks() {
		document.addEventListener(
			"click",
			(event) => {
				const anchor = event.target.closest("a[href]");
				if (!anchor) return;

				const href = anchor.getAttribute("href") || anchor.href;
				if (!href) return;

				try {
					const url = new URL(href, window.location.href);
					const isCrx = url.pathname.endsWith(".crx");
					const isXpi =
						url.pathname.endsWith(".xpi") ||
						url.pathname.includes("/downloads/file/");

					if (isCrx || isXpi) {
						logInfo(
							"Direct package download link clicked:",
							url.href,
						);
						event.preventDefault();
						event.stopPropagation();
						safeSendMessage({
							type: "INSTALL_PACKAGE_FROM_URL",
							downloadUrl: url.href,
							referrer: window.location.href,
						});
					}
				} catch (_) {}
			},
			true,
		);
	}

	async function initialiseMatchingScripts() {
		try {
			logInfo(
				"Requesting matched scripts for URL:",
				window.location.href,
			);
			const response = await safeSendMessage({
				type: "GET_MATCHING_SCRIPTS",
				url: window.location.href,
			});

			if (
				!response?.matchingExtensions ||
				response.matchingExtensions.length === 0
			) {
				logInfo(
					"No matching third-party extension scripts for this page.",
				);
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
			logError("Failed to initialise matching scripts:", err);
		}
	}

	function createShim(extensionId) {
		return {
			runtime: {
				id: extensionId,
				sendMessage: (payload, callback) => {
					logInfo(
						`[Hosted:${extensionId}] runtime.sendMessage called with:`,
						payload,
					);
					const promise = safeSendMessage({
						type: "RUNTIME_SEND_MESSAGE",
						extensionId,
						payload,
					});
					if (typeof callback === "function") {
						promise
							.then((res) => callback(res))
							.catch(() => callback(null));
					}
					return promise;
				},
				onMessage: {
					addListener: () => {},
					removeListener: () => {},
				},
				getURL: (path) =>
					`ext-res://${extensionId}/${path.replace(/^\//, "")}`,
			},
			storage: {
				local: {
					get: (keys, cb) => {
						const p = safeSendMessage({
							type: "STORAGE_GET",
							extensionId,
							area: "local",
							keys,
						});
						if (cb) p.then(cb);
						return p;
					},
					set: (items, cb) => {
						const p = safeSendMessage({
							type: "STORAGE_SET",
							extensionId,
							area: "local",
							items,
						});
						if (cb) p.then(cb);
						return p;
					},
				},
			},
		};
	}

	function evaluateScopedScript(code, extensionId, scriptPath) {
		logInfo(
			`Evaluating script for hosted extension: ${extensionId} (${scriptPath || "inline"})`,
		);
		const shim = createShim(extensionId);
		try {
			const runner = new Function(
				"chrome",
				"browser",
				"window",
				"document",
				`${code}\n//# sourceURL=ext://${extensionId}/${scriptPath || "content.js"}`,
			);
			runner(shim, shim, window, document);
		} catch (e) {
			logError(`Error executing script for ${extensionId}:`, e);
		}
	}

	interceptDownloadClicks();
	hookStorefronts();
	initialiseMatchingScripts();
})();
