import type { NativeMatchingScriptsReply } from "@/types/extension";

export async function initialiseMatchingScripts(): Promise<void> {
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

		const isMainFrame = window.self === window.top;

		for (const ext of response.matchingExtensions) {
			if (ext.styles) {
				for (const cssText of ext.styles) {
					const injectStyle = () => {
						const style = document.createElement("style");
						style.setAttribute("data-hosted-ext", ext.id);
						style.textContent = cssText;
						(
							document.head || document.documentElement
						)?.appendChild(style);
					};
					if (document.head || document.documentElement) {
						injectStyle();
					} else {
						document.addEventListener(
							"DOMContentLoaded",
							injectStyle,
							{ once: true },
						);
					}
				}
			}

			if (ext.scripts) {
				for (const scriptItem of ext.scripts) {
					if (!isMainFrame && scriptItem.allFrames === false) {
						continue;
					}
					scheduleScriptExecution(scriptItem.runAt, () => {
						evaluateScopedScript(
							scriptItem.code,
							ext.id,
							scriptItem.path,
						);
					});
				}
			}
		}
	} catch (err) {
		const msg = err instanceof Error ? err.message : String(err);
		logError("Failed to initialise matching scripts:", msg);
	}
}
