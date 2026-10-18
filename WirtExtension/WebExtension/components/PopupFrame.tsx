import React from "react";
import styles from "./PopupFrame.module.css";

export interface PopupFrameProps {
	readonly srcDoc: string;
	readonly title: string;
}

export const PopupFrame: React.FC<PopupFrameProps> = ({ srcDoc, title }) => {
	return (
		<div className={styles.frameContainer}>
			<iframe
				className={styles.popupFrame}
				srcDoc={srcDoc}
				sandbox="allow-scripts allow-forms allow-same-origin"
				title={title}
			/>
		</div>
	);
};
