import React from "react";

export type IconType =
	"application" | "reload" | "cog" | "back" | "extension" | "empty";

export interface IconProps {
	readonly type: IconType;
	readonly size?: number;
	readonly className?: string;
}

export const Icon: React.FC<IconProps> = ({ type, size = 16, className }) => {
	if (type === "application") {
		return (
			<svg
				width={size}
				height={size}
				viewBox="0 0 40 40"
				fill="none"
				stroke="currentColor"
				strokeLinecap="round"
				strokeLinejoin="round"
				className={className}
				aria-hidden="true"
			>
				<rect
					x="4"
					y="4"
					width="32"
					height="32"
					rx="8"
					strokeWidth="2.2"
				/>
				<line x1="4" y1="13" x2="36" y2="13" strokeWidth="1.8" />
				<circle
					cx="10"
					cy="8.5"
					r="1.5"
					fill="currentColor"
					stroke="none"
				/>
				<circle
					cx="15"
					cy="8.5"
					r="1.5"
					fill="currentColor"
					stroke="none"
				/>
				<circle
					cx="20"
					cy="8.5"
					r="1.5"
					fill="currentColor"
					stroke="none"
				/>
				<path
					d="M17 21h2a1.5 1.5 0 0 1 3 0h2v2a1.5 1.5 0 0 1 0 3v2h-2a1.5 1.5 0 0 1-3 0h-2v-2a1.5 1.5 0 0 1 0-3z"
					strokeWidth="1.8"
				/>
			</svg>
		);
	}

	if (type === "reload") {
		return (
			<svg
				width={size}
				height={size}
				viewBox="0 0 16 16"
				fill="none"
				stroke="currentColor"
				strokeWidth="2"
				strokeLinecap="round"
				strokeLinejoin="round"
				className={className}
				aria-hidden="true"
			>
				<path d="M2.5 8a5.5 5.5 0 1 0 1.2-3.4" />
				<polyline points="2.5 2.5 2.5 5.5 5.5 5.5" />
			</svg>
		);
	}

	if (type === "cog") {
		return (
			<svg
				width={size}
				height={size}
				viewBox="0 0 16 16"
				fill="none"
				stroke="currentColor"
				strokeWidth="1.8"
				strokeLinecap="round"
				strokeLinejoin="round"
				className={className}
				aria-hidden="true"
			>
				<circle cx="8" cy="8" r="2.5" />
				<path d="M8 1.5v1.2M8 13.3v1.2M1.5 8h1.2M13.3 8h1.2M3.4 3.4l.85.85M11.75 11.75l.85.85M3.4 12.6l.85-.85M11.75 4.25l.85-.85" />
			</svg>
		);
	}

	if (type === "back") {
		return (
			<svg
				width={size}
				height={size}
				viewBox="0 0 16 16"
				fill="none"
				stroke="currentColor"
				strokeWidth="2"
				strokeLinecap="round"
				strokeLinejoin="round"
				className={className}
				aria-hidden="true"
			>
				<polyline points="10 3 5 8 10 13" />
			</svg>
		);
	}

	if (type === "extension") {
		return (
			<svg
				width={size}
				height={size}
				viewBox="0 0 20 20"
				fill="none"
				stroke="currentColor"
				strokeWidth="1.8"
				strokeLinecap="round"
				strokeLinejoin="round"
				className={className}
				aria-hidden="true"
			>
				<path d="M7 14H4a1 1 0 0 1-1-1v-3a2 2 0 0 1 0-4V3a1 1 0 0 1 1-1h3a2 2 0 0 0 4 0h3a1 1 0 0 1 1 1v3a2 2 0 0 0 0 4v3a1 1 0 0 1-1 1h-3a2 2 0 0 1-4 0z" />
			</svg>
		);
	}

	return (
		<svg
			width={size}
			height={size}
			viewBox="0 0 40 40"
			fill="none"
			stroke="currentColor"
			strokeLinecap="round"
			strokeLinejoin="round"
			className={className}
			aria-hidden="true"
		>
			<path
				d="M14 27h-4a2 2 0 0 1-2-2v-4a3 3 0 0 1 0-6v-4a2 2 0 0 1 2-2h4a3 3 0 0 0 6 0h4a2 2 0 0 1 2 2v4a3 3 0 0 0 0 6v4a2 2 0 0 1-2 2h-4a3 3 0 0 1-6 0z"
				strokeWidth="2.2"
			/>
		</svg>
	);
};
