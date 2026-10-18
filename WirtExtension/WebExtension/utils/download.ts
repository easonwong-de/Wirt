import type { NativeInstallPackageReply } from "@/types/extension";

export function interceptDownloadClicks(): void {
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
