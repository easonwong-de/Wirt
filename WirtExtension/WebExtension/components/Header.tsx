import React from "react";
import { Icon } from "@/components/Icon";
import styles from "./Header.module.css";

export interface HeaderProps {
	readonly title: string;
	readonly icon?: React.ReactNode;
	readonly iconUrl?: string;
	readonly onActionClick?: () => void;
	readonly actionIcon?: React.ReactNode;
	readonly actionTooltip?: string;
}

export const Header: React.FC<HeaderProps> = ({
	title,
	icon,
	iconUrl,
	onActionClick,
	actionIcon,
	actionTooltip,
}) => {
	const renderIcon = () => {
		if (icon) {
			return icon;
		}
		if (iconUrl) {
			return <img src={iconUrl} alt="" className={styles.iconImage} />;
		}
		return <Icon type="extension" size={16} />;
	};

	return (
		<>
			<header className={styles.header}>
				<div className={styles.titleGroup}>
					<div className={styles.titleIcon}>{renderIcon()}</div>
					<span className={styles.headerTitle}>{title}</span>
				</div>
				{onActionClick && actionIcon ? (
					<button
						type="button"
						className={styles.iconButton}
						onClick={onActionClick}
						title={actionTooltip}
						aria-label={actionTooltip}
					>
						{actionIcon}
					</button>
				) : null}
			</header>
			<hr className={styles.divider} />
		</>
	);
};
