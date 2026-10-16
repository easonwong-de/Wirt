import React, { useCallback, useEffect, useState } from "react";
import { ExtensionItem } from "@/components/ExtensionItem";
import { Icon } from "@/components/Icon";
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
					<header className={styles.popupHeader}>
						<button
							type="button"
							className={styles.iconButton}
							onClick={() => setActiveExtension(null)}
							title={i18n.t("backTooltip")}
							aria-label={i18n.t("backTooltip")}
						>
							<Icon type="back" size={13} />
						</button>
						<div className={styles.extensionIcon}>
							<Icon type="extension" size={16} />
						</div>
						<span className={styles.headerTitle}>
							{activeExtension.name}
						</span>
					</header>
					<hr className={styles.divider} />
					<div className={styles.frameContainer}>
						<iframe
							className={styles.popupFrame}
							src={`ext-ui://${activeExtension.id}/${activeExtension.popupPath}`}
							sandbox="allow-scripts allow-forms allow-same-origin"
							title={activeExtension.name}
						/>
					</div>
				</>
			) : connectionState === "disconnected" ? (
				<div className={styles.disconnectedContainer}>
					<div className={styles.disconnectedIcon}>
						<Icon type="application" size={40} />
					</div>
					<div className={styles.disconnectedStatusRow}>
						<span className={styles.statusIndicator} />
						<span className={styles.disconnectedStatusText}>
							{i18n.t("hostNotConnectedTitle")}
						</span>
						<button
							type="button"
							className={styles.iconButton}
							onClick={() => void loadExtensions()}
							title={i18n.t("refreshTooltip")}
							aria-label={i18n.t("refreshTooltip")}
						>
							<Icon type="reload" size={12} />
						</button>
					</div>
					<span className={styles.disconnectedInstruction}>
						{i18n.t("hostNotConnectedInstruction")}
					</span>
				</div>
			) : connectionState === "connected" ? (
				<>
					<header className={styles.header}>
						<span className={styles.headerTitle}>
							{i18n.t("installedExtensionsTitle")}
						</span>
						<div className={styles.headerActions}>
							<button
								type="button"
								className={styles.iconButton}
								onClick={() => void loadExtensions()}
								title={i18n.t("refreshTooltip")}
								aria-label={i18n.t("refreshTooltip")}
							>
								<Icon type="reload" size={12} />
							</button>
							<button
								type="button"
								className={styles.iconButton}
								onClick={() => void handleOpenHostApp()}
								title={i18n.t("openHostAppTooltip")}
								aria-label={i18n.t("openHostAppTooltip")}
							>
								<Icon type="cog" size={13} />
							</button>
						</div>
					</header>
					<hr className={styles.divider} />
					{extensions.length === 0 ? (
						<div className={styles.emptyContainer}>
							<div className={styles.emptyIcon}>
								<Icon type="empty" size={38} />
							</div>
							<span className={styles.emptyTitle}>
								{i18n.t("emptyExtensionsTitle")}
							</span>
							<span className={styles.emptySubtitle}>
								{i18n.t("emptyExtensionsSubtitle")}
							</span>
						</div>
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
