import React, { useCallback, useEffect, useState } from "react";
import { DisconnectedView } from "@/components/DisconnectedView";
import { EmptyView } from "@/components/EmptyView";
import { ExtensionItem } from "@/components/ExtensionItem";
import { Header } from "@/components/Header";
import { Icon } from "@/components/Icon";
import { PopupFrame } from "@/components/PopupFrame";
import type {
	ActiveTab,
	ExtensionDescriptor,
	NativeInstalledExtensionsReply,
} from "@/types/extension";
import styles from "./App.module.css";

type ConnectionState = "loading" | "connected" | "disconnected";

export const App: React.FC = () => {
	const [connectionState, setConnectionState] =
		useState<ConnectionState>("loading");
	const [extensions, setExtensions] = useState<
		readonly ExtensionDescriptor[]
	>([]);
	const [activeExtension, setActiveExtension] =
		useState<ExtensionDescriptor | null>(null);
	const [popupHtml, setPopupHtml] = useState<string>("");
	const [activeTab, setActiveTab] = useState<ActiveTab | null>(null);

	const loadExtensions = useCallback(async () => {
		try {
			const response = (await browser.runtime.sendMessage({
				type: "GET_INSTALLED_EXTENSIONS",
			})) as NativeInstalledExtensionsReply | undefined;

			if (!response || response.error) {
				setConnectionState("disconnected");
				return;
			}

			setExtensions(response.extensions ?? []);
			setConnectionState("connected");

			const tabs = await browser.tabs.query({
				active: true,
				currentWindow: true,
			});
			if (tabs.length > 0 && tabs[0]) {
				setActiveTab({
					id: tabs[0].id,
					url: tabs[0].url,
					windowId: tabs[0].windowId,
					title: tabs[0].title,
				});
			}
		} catch {
			setConnectionState("disconnected");
		}
	}, []);

	useEffect(() => {
		void loadExtensions();
	}, [loadExtensions]);

	const handleOpenHostApp = useCallback(async () => {
		try {
			await browser.runtime.sendMessage({ type: "OPEN_HOST_APP" });
		} catch {
			// Ignored
		}
	}, []);

	const handleExtensionClick = useCallback(
		async (ext: ExtensionDescriptor) => {
			if (ext.actionType === "popup") {
				setActiveExtension(ext);
				setPopupHtml("");
				try {
					const res = (await browser.runtime.sendMessage({
						type: "GET_POPUP_RESOURCES",
						extensionId: ext.id,
						popupPath: ext.popupPath,
					})) as { readonly html?: string } | undefined;
					setPopupHtml(
						res?.html ??
							"<html><body><p>Popup could not be loaded.</p></body></html>",
					);
				} catch {
					setPopupHtml(
						"<html><body><p>Failed to load popup.</p></body></html>",
					);
				}
				return;
			}

			if (ext.actionType === "click") {
				try {
					await browser.runtime.sendMessage({
						type: "DISPATCH_ACTION_CLICK",
						extensionId: ext.id,
						tab: activeTab ?? undefined,
					});
				} finally {
					window.close();
				}
			}
		},
		[activeTab],
	);

	return (
		<div className={styles.container}>
			{activeExtension !== null ? (
				<>
					<Header
						title={activeExtension.name}
						iconUrl={activeExtension.iconUrl}
						onActionClick={() => setActiveExtension(null)}
						actionIcon={<Icon type="close" size={11} />}
						actionTooltip={i18n.t("closeTooltip")}
					/>
					<PopupFrame
						srcDoc={popupHtml}
						title={activeExtension.name}
					/>
				</>
			) : connectionState === "disconnected" ? (
				<DisconnectedView onRefresh={() => void loadExtensions()} />
			) : connectionState === "connected" ? (
				<>
					<Header
						title={i18n.t("installedExtensionsTitle")}
						icon={<Icon type="extension" size={16} />}
						onActionClick={() => void handleOpenHostApp()}
						actionIcon={<Icon type="cog" size={13} />}
						actionTooltip={i18n.t("openHostAppTooltip")}
					/>
					{extensions.length === 0 ? (
						<EmptyView />
					) : (
						<div className={styles.extensionList}>
							{extensions.map((ext) => (
								<ExtensionItem
									key={ext.id}
									extension={ext}
									onClick={handleExtensionClick}
								/>
							))}
						</div>
					)}
				</>
			) : null}
		</div>
	);
};

export default App;
