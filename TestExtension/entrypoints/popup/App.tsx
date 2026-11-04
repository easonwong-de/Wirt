import React, { useCallback, useEffect, useState } from "react";
import type { CounterState } from "@/types/extension";
import {
	getStoredState,
	INITIAL_STATE,
	sendCounterMessage,
} from "@/utils/storage";

export const App: React.FC = () => {
	const [state, setState] = useState<CounterState>(INITIAL_STATE);

	const refresh = useCallback(async () => {
		const res = await sendCounterMessage({ type: "GET_COUNT" });
		if (res.status === "ok" && typeof res.count === "number") {
			setState({
				count: res.count,
				lastModifiedBy: res.lastModifiedBy ?? "background",
				lastModifiedAt: res.lastModifiedAt ?? new Date().toISOString(),
			});
		} else {
			const stored = await getStoredState();
			setState(stored);
		}
	}, []);

	useEffect(() => {
		void refresh();
		const listener = (changes: {
			counterState?: { newValue?: CounterState };
		}) => {
			if (changes.counterState?.newValue) {
				setState(changes.counterState.newValue);
			}
		};
		browser.storage?.onChanged?.addListener(listener);
		return () => {
			browser.storage?.onChanged?.removeListener(listener);
		};
	}, [refresh]);

	const handleDelta = async (delta: number) => {
		const res = await sendCounterMessage({
			type: "INCREMENT_COUNT",
			delta,
			source: "popup",
		});
		if (res.status === "ok" && typeof res.count === "number") {
			setState({
				count: res.count,
				lastModifiedBy: "popup",
				lastModifiedAt: new Date().toISOString(),
			});
		}
	};

	const handleReset = async () => {
		const res = await sendCounterMessage({
			type: "RESET_COUNT",
			source: "popup",
		});
		if (res.status === "ok") {
			setState({
				count: 0,
				lastModifiedBy: "popup",
				lastModifiedAt: new Date().toISOString(),
			});
		}
	};

	const handleOpenOptions = async () => {
		await sendCounterMessage({ type: "OPEN_OPTIONS_PAGE" });
	};

	const countClass =
		state.count > 0 ? "positive" : state.count < 0 ? "negative" : "zero";

	return (
		<div className="counter-shell">
			<span className="counter-origin-badge">Popup Counter</span>
			<div className={`counter-display ${countClass}`}>{state.count}</div>
			<div className="counter-meta">Source: {state.lastModifiedBy}</div>

			<div className="button-row">
				<button
					type="button"
					className="btn"
					onClick={() => void handleDelta(-1)}
				>
					-1
				</button>
				<button
					type="button"
					className="btn"
					onClick={() => void handleReset()}
				>
					Reset
				</button>
				<button
					type="button"
					className="btn"
					onClick={() => void handleDelta(1)}
				>
					+1
				</button>
			</div>

			<div className="button-row">
				<button
					type="button"
					className="btn btn-secondary"
					onClick={() => {
						const port = browser.runtime.connect?.({
							name: "popup-counter-stream",
						});
						port?.postMessage?.({
							type: "PORT_STREAM_UPDATE",
							delta: 10,
						});
						setTimeout(() => port?.disconnect?.(), 50);
					}}
				>
					+10 (Port)
				</button>
				<button
					type="button"
					className="btn btn-secondary"
					onClick={() => void handleOpenOptions()}
				>
					Options Page
				</button>
			</div>
		</div>
	);
};

export default App;
