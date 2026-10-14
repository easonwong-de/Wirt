const LOG_TAG = "[SafariExtensionHost:Background]";

function logInfo(...args) {
	console.log(LOG_TAG, ...args);
}

function logWarn(...args) {
	console.warn(LOG_TAG, ...args);
}

function logError(...args) {
	console.error(LOG_TAG, ...args);
}

logInfo("Background service worker initialised");

function sendNativeEnvelope(envelope) {
	return new Promise((resolve) => {
		try {
			logInfo("Dispatching native message:", envelope.type, envelope);
			browser.runtime.sendNativeMessage(
				"application.id",
				envelope,
				(response) => {
					const err = browser.runtime.lastError;
					if (err) {
						logError(
							"Native messaging error for",
							envelope.type,
							err.message || err,
						);
						resolve({ error: err.message || String(err) });
					} else {
						logInfo(
							"Received native response for",
							envelope.type,
							response,
						);
						resolve(response || {});
					}
				},
			);
		} catch (err) {
			logError("Failed to invoke sendNativeMessage:", err);
			resolve({ error: String(err) });
		}
	});
}

browser.runtime.onMessage.addListener((request, sender, sendResponse) => {
	if (!request || !request.type) return false;

	logInfo(
		"Received runtime message:",
		request.type,
		"from sender:",
		sender.url || `tab:${sender.tab?.id || "unknown"}`,
	);

	if (request.type === "GET_INSTALLED_EXTENSIONS") {
		sendNativeEnvelope({ type: "GET_INSTALLED_EXTENSIONS" })
			.then((res) => sendResponse(res))
			.catch((err) => {
				logError("Error in GET_INSTALLED_EXTENSIONS:", err);
				sendResponse({ error: String(err) });
			});
		return true;
	}

	if (request.type === "DISPATCH_ACTION_CLICK") {
		sendNativeEnvelope({
			type: "DISPATCH_ACTION_CLICK",
			extensionId: request.extensionId,
			tab: request.tab,
		})
			.then((res) => sendResponse(res))
			.catch((err) => {
				logError("Error in DISPATCH_ACTION_CLICK:", err);
				sendResponse({ error: String(err) });
			});
		return true;
	}

	if (request.type === "GET_MATCHING_SCRIPTS") {
		sendNativeEnvelope({
			type: "GET_MATCHING_SCRIPTS",
			url: request.url,
		})
			.then((res) => sendResponse(res))
			.catch((err) => {
				logError("Error in GET_MATCHING_SCRIPTS:", err);
				sendResponse({ matchingExtensions: [] });
			});
		return true;
	}

	if (request.type === "RUNTIME_SEND_MESSAGE") {
		sendNativeEnvelope({
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
			.catch((err) => {
				logError("Error in RUNTIME_SEND_MESSAGE:", err);
				sendResponse({ error: String(err) });
			});
		return true;
	}

	if (request.type === "INSTALL_PACKAGE_FROM_URL") {
		logInfo("Installing package from URL:", request.downloadUrl);
		sendNativeEnvelope({
			type: "INSTALL_PACKAGE_FROM_URL",
			downloadUrl: request.downloadUrl,
			referrer: request.referrer,
		})
			.then((res) => {
				logInfo("Installation completed with response:", res);
				sendResponse(res);
			})
			.catch((err) => {
				logError("Error in INSTALL_PACKAGE_FROM_URL:", err);
				sendResponse({ error: String(err) });
			});
		return true;
	}

	return false;
});

browser.webNavigation.onBeforeNavigate.addListener((details) => {
	if (details.frameId !== 0) return;
	try {
		const url = new URL(details.url);
		const isCrx = url.pathname.endsWith(".crx");
		const isXpi =
			url.pathname.endsWith(".xpi") ||
			url.pathname.includes("/downloads/file/");

		if (isCrx || isXpi) {
			logInfo("Navigation interceptor matched package URL:", details.url);
			sendNativeEnvelope({
				type: "INSTALL_PACKAGE_FROM_URL",
				downloadUrl: details.url,
			});
		}
	} catch (err) {
		logWarn("Error parsing navigation URL:", err);
	}
});
