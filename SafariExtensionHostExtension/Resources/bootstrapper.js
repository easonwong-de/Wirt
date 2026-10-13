(() => {
	function interceptDownloadClicks() {
		document.addEventListener(
			"click",
			(event) => {
				const anchor = event.target.closest("a[href]");
				if (!anchor) return;

				const href = anchor.href;
				if (!href) return;

				try {
					const url = new URL(href, window.location.href);
					const isCrx = url.pathname.endsWith(".crx");
					const isXpi = url.pathname.endsWith(".xpi");
					const isChromeStore =
						url.hostname === "clients2.google.com" &&
						url.pathname.includes("/service/update2/crx");

					if (isCrx || isXpi || isChromeStore) {
						event.preventDefault();
						event.stopPropagation();
						browser.runtime.sendMessage({
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

	function hookStorefronts() {
		if (window.location.hostname === "chromewebstore.google.com") {
			const match = window.location.pathname.match(
				/\/detail\/[^\/]+\/([a-z0-9]{32})/i,
			);
			if (match) {
				const extId = match[1];
				const crxUrl = `https://clients2.google.com/service/update2/crx?response=redirect&prodversion=120.0&acceptformat=crx2,crx3&x=id%3D${extId}%26uc`;
				document.addEventListener(
					"click",
					(e) => {
						const btn = e.target.closest("button, [role='button']");
						if (!btn) return;
						const text = btn.textContent?.toLowerCase() || "";
						if (
							text.includes("add to chrome") ||
							text.includes("install")
						) {
							e.preventDefault();
							e.stopPropagation();
							browser.runtime.sendMessage({
								type: "INSTALL_PACKAGE_FROM_URL",
								downloadUrl: crxUrl,
								referrer: window.location.href,
							});
						}
					},
					true,
				);
			}
		}
	}

	async function initialiseMatchingScripts() {
		try {
			const response = await browser.runtime.sendMessage({
				type: "GET_MATCHING_SCRIPTS",
				url: window.location.href,
			});

			if (!response?.matchingExtensions) return;

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
		} catch (_) {}
	}

	function createShim(extensionId) {
		return {
			runtime: {
				id: extensionId,
				sendMessage: (payload, callback) => {
					const promise = browser.runtime.sendMessage({
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
						const p = browser.runtime.sendMessage({
							type: "STORAGE_GET",
							extensionId,
							area: "local",
							keys,
						});
						if (cb) p.then(cb);
						return p;
					},
					set: (items, cb) => {
						const p = browser.runtime.sendMessage({
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
			console.error(
				`[SafariExtensionHost] Error executing script for ${extensionId}:`,
				e,
			);
		}
	}

	interceptDownloadClicks();
	hookStorefronts();
	initialiseMatchingScripts();
})();
