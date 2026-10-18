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
