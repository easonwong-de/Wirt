let nativePort = null;
const pendingResponses = new Map();

function connectNativePort() {
	nativePort = browser.runtime.connectNative("application.id");

	nativePort.onMessage.addListener((envelope) => {
		handleNativeEnvelope(envelope);
	});

	nativePort.onDisconnect.addListener(() => {
		nativePort = null;
		setTimeout(connectNativePort, 1500);
	});
}

function handleNativeEnvelope(envelope) {
	if (
		envelope.correlationId &&
		pendingResponses.has(envelope.correlationId)
	) {
		const resolver = pendingResponses.get(envelope.correlationId);
		pendingResponses.delete(envelope.correlationId);
		resolver(envelope.payload);
		return;
	}

	if (envelope.type === "UPDATE_BADGE") {
		browser.action.setBadgeText({ text: envelope.text || "" });
		if (envelope.color) {
			browser.action.setBadgeBackgroundColor({ color: envelope.color });
		}
	}
}

function sendNativeEnvelope(envelope) {
	return new Promise((resolve) => {
		const correlationId = crypto.randomUUID();
		envelope.correlationId = correlationId;
		pendingResponses.set(correlationId, resolve);
		if (nativePort) {
			nativePort.postMessage(envelope);
		} else {
			resolve({ error: "Native port disconnected" });
		}
	});
}

browser.runtime.onMessage.addListener((request, sender, sendResponse) => {
	if (request.type === "GET_INSTALLED_EXTENSIONS") {
		sendNativeEnvelope({ type: "GET_INSTALLED_EXTENSIONS" }).then(
			sendResponse,
		);
		return true;
	}

	if (request.type === "DISPATCH_ACTION_CLICK") {
		sendNativeEnvelope({
			type: "DISPATCH_ACTION_CLICK",
			extensionId: request.extensionId,
			tab: request.tab,
		}).then(sendResponse);
		return true;
	}

	if (request.type === "GET_MATCHING_SCRIPTS") {
		sendNativeEnvelope({
			type: "GET_MATCHING_SCRIPTS",
			url: request.url,
		}).then(sendResponse);
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
		}).then(sendResponse);
		return true;
	}

	if (request.type === "INSTALL_PACKAGE_FROM_URL") {
		sendNativeEnvelope({
			type: "INSTALL_PACKAGE_FROM_URL",
			downloadUrl: request.downloadUrl,
			referrer: request.referrer,
		}).then(sendResponse);
		return true;
	}
});

browser.webNavigation.onBeforeNavigate.addListener((details) => {
	if (details.frameId !== 0) return;
	const url = new URL(details.url);
	if (url.pathname.endsWith(".crx") || url.pathname.endsWith(".xpi")) {
		sendNativeEnvelope({
			type: "INSTALL_PACKAGE_FROM_URL",
			downloadUrl: details.url,
		});
		browser.tabs.update(details.tabId, { url: "about:blank" });
	}
});

browser.tabs.onUpdated.addListener((tabId, changeInfo, tab) => {
	if (changeInfo.status === "complete" || changeInfo.url) {
		if (nativePort) {
			nativePort.postMessage({
				type: "TAB_UPDATED",
				tabId,
				changeInfo,
				tab,
			});
		}
	}
});

browser.tabs.onRemoved.addListener((tabId, removeInfo) => {
	if (nativePort) {
		nativePort.postMessage({
			type: "TAB_REMOVED",
			tabId,
			removeInfo,
		});
	}
});

connectNativePort();
