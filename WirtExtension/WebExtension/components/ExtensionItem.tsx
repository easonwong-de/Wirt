import React from "react";
import { Icon } from "@/components/Icon";
import type { ExtensionDescriptor } from "@/types/extension";
import styles from "./ExtensionItem.module.css";

export interface ExtensionItemProps {
	readonly extension: ExtensionDescriptor;
	readonly onClick: (extension: ExtensionDescriptor) => void;
}

export const ExtensionItem: React.FC<ExtensionItemProps> = ({
	extension,
	onClick,
}) => {
	const hasAction =
		extension.actionType === "popup" || extension.actionType === "click";

	const getActionTooltip = (): string | undefined => {
		if (extension.actionType === "popup") {
			return i18n.t("openPopupActionTooltip");
		}
		if (extension.actionType === "click") {
			return i18n.t("triggerActionTooltip");
		}
		return undefined;
	};

	return (
		<div
			className={
				hasAction
					? styles.extensionItemInteractive
					: styles.extensionItemDisabled
			}
			onClick={() => void onClick(extension)}
			role={hasAction ? "button" : undefined}
			tabIndex={hasAction ? 0 : undefined}
			title={getActionTooltip()}
		>
			<div className={styles.extensionIcon}>
				{extension.iconUrl ? (
					<img
						src={extension.iconUrl}
						alt=""
						className={styles.iconImage}
					/>
				) : (
					<Icon type="extension" size={16} />
				)}
			</div>
			<span className={styles.extensionName}>{extension.name}</span>
			{extension.badgeText ? (
				<span
					className={styles.badge}
					style={{
						backgroundColor: extension.badgeColor || undefined,
					}}
				>
					{extension.badgeText}
				</span>
			) : null}
		</div>
	);
};
