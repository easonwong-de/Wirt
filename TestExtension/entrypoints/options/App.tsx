import React, { useCallback, useEffect, useState } from "react";
import type { CounterState } from "@/types/extension";
import {
	getStoredState,
	INITIAL_STATE,
	sendCounterMessage,
} from "@/utils/storage";

export const App: React.FC = () => {
	const [state, setState] = useState<CounterState>(INITIAL_STATE);
	const [tabsCount, setTabsCount] = useState<number | null>(null);

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

		const tabRes = await sendCounterMessage({ type: "QUERY_TABS" });
		if (typeof tabRes.tabsCount === "number") {
			setTabsCount(tabRes.tabsCount);
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
			source: "options",
		});
		if (res.status === "ok" && typeof res.count === "number") {
			setState({
				count: res.count,
				lastModifiedBy: "options",
				lastModifiedAt: new Date().toISOString(),
			});
		}
	};

	const handleReset = async () => {
		const res = await sendCounterMessage({
			type: "RESET_COUNT",
			source: "options",
		});
		if (res.status === "ok") {
			setState({
				count: 0,
				lastModifiedBy: "options",
				lastModifiedAt: new Date().toISOString(),
			});
		}
	};

	const countClass =
		state.count > 0 ? "positive" : state.count < 0 ? "negative" : "zero";

	return (
		<div className="options-shell">
			<div className="counter-card">
				<span className="card-title">Options Page Counter</span>
				<div className={`counter-display ${countClass}`}>
					{state.count}
				</div>
				<div className="counter-meta">
					Source: {state.lastModifiedBy} | Updated:{" "}
					{new Date(state.lastModifiedAt).toLocaleTimeString()}
				</div>

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

				{tabsCount !== null && (
					<div className="tabs-stat">
						browser.tabs reporting {tabsCount} open tab(s)
					</div>
				)}
			</div>
		</div>
	);
};

export default App;
