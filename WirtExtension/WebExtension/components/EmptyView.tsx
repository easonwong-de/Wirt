import React from "react";
import { Icon } from "@/components/Icon";
import styles from "./EmptyView.module.css";

export const EmptyView: React.FC = () => {
	return (
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
	);
};
