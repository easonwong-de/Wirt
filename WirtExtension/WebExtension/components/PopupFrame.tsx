import React from "react";
import styles from "./PopupFrame.module.css";

export interface PopupFrameProps {
	readonly srcDoc?: string;
	readonly src?: string;
	readonly title: string;
}

export const PopupFrame: React.FC<PopupFrameProps> = ({
	srcDoc,
	src,
	title,
}) => {
	return (
		<div className={styles.frameContainer}>
			<iframe
				className={styles.popupFrame}
				srcDoc={srcDoc}
				src={src}
				sandbox="allow-scripts allow-forms allow-same-origin allow-modals"
				title={title}
			/>
		</div>
	);
};
