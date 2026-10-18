import React from "react";
import { Icon } from "@/components/Icon";
import styles from "./DisconnectedView.module.css";

export interface DisconnectedViewProps {
	readonly onRefresh: () => void;
}

export const DisconnectedView: React.FC<DisconnectedViewProps> = ({
	onRefresh,
}) => {
	return (
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
					onClick={onRefresh}
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
	);
};
