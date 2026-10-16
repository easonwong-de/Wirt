import React from "react";
import { Icon } from "@/components/Icon";
import styles from "@/entrypoints/popup/App.module.css";
import type { ExtensionDescriptor } from "@/types/extension";

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
		>
			<div className={styles.extensionIcon}>
				<Icon type="extension" size={16} />
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
