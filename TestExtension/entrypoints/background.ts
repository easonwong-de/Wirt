import type { CounterMessage, CounterResponse } from "@/types/extension";
import { getStoredState, setStoredState } from "@/utils/storage";

const TAG = "[TestExtension:Background]";

async function updateBadge(count: number): Promise<void> {
	try {
		const text = count === 0 ? "" : String(count);
		await browser.action?.setBadgeText?.({ text });
		const color = count > 0 ? "#30d158" : count < 0 ? "#ff453a" : "#0071e3";
		await browser.action?.setBadgeBackgroundColor?.({ color });
	} catch (err) {
		console.warn(TAG, "Badge update error:", err);
	}
}

async function handleMessage(
	request: CounterMessage,
): Promise<CounterResponse> {
	console.log(TAG, "Message received:", request.type);

	if (request.type === "GET_COUNT") {
		const state = await getStoredState();
		return {
			status: "ok",
			count: state.count,
			lastModifiedBy: state.lastModifiedBy,
			lastModifiedAt: state.lastModifiedAt,
			runtimeId: browser.runtime.id,
		};
	} else if (request.type === "INCREMENT_COUNT") {
		const current = await getStoredState();
		const delta = request.delta ?? 1;
		const next = await setStoredState(
			current.count + delta,
			request.source,
		);
		await updateBadge(next.count);
		return {
			status: "ok",
			count: next.count,
			lastModifiedBy: next.lastModifiedBy,
			lastModifiedAt: next.lastModifiedAt,
		};
	} else if (request.type === "SET_COUNT") {
		const next = await setStoredState(request.count, request.source);
		await updateBadge(next.count);
		return {
			status: "ok",
			count: next.count,
			lastModifiedBy: next.lastModifiedBy,
			lastModifiedAt: next.lastModifiedAt,
		};
	} else if (request.type === "RESET_COUNT") {
		const next = await setStoredState(0, request.source);
		await updateBadge(0);
		return {
			status: "ok",
			count: 0,
			lastModifiedBy: next.lastModifiedBy,
			lastModifiedAt: next.lastModifiedAt,
		};
	} else if (request.type === "OPEN_OPTIONS_PAGE") {
		await browser.runtime.openOptionsPage?.();
		return { status: "ok" };
	} else if (request.type === "QUERY_TABS") {
		const tabs = (await browser.tabs?.query?.({})) ?? [];
		return {
			status: "ok",
			tabsCount: tabs.length,
		};
	}

	return { status: "error", message: "Unknown message type" };
}

export default defineBackground(() => {
	console.info(TAG, "Background runtime initialized for", browser.runtime.id);

	// Synchronize initial badge on boot
	void getStoredState().then((state) => updateBadge(state.count));

	browser.runtime.onMessage.addListener(
		(
			message: CounterMessage | null | undefined,
			_sender: Browser.runtime.MessageSender,
			sendResponse: (response: CounterResponse) => void,
		): boolean => {
			if (!message || typeof message.type !== "string") {
				return false;
			}
			handleMessage(message)
				.then((res) => sendResponse(res))
				.catch((err: unknown) => {
					const msg =
						err instanceof Error ? err.message : String(err);
					console.error(TAG, "handleMessage error:", msg);
					sendResponse({ status: "error", message: msg });
				});
			return true;
		},
	);

	browser.action?.onClicked?.addListener(() => {
		console.info(TAG, "Action clicked: incrementing count from action");
		void (async () => {
			const current = await getStoredState();
			const next = await setStoredState(current.count + 1, "background");
			await updateBadge(next.count);
		})();
	});

	browser.runtime.onConnect?.addListener?.((port) => {
		console.info(TAG, `Port connected: ${port.name}`);
		port.onMessage?.addListener?.((msg) => {
			console.log(TAG, `Port ${port.name} received:`, msg);
			const request = msg as CounterMessage | undefined;
			if (request?.type === "PORT_STREAM_UPDATE") {
				void (async () => {
					const current = await getStoredState();
					const next = await setStoredState(
						current.count + request.delta,
						"background",
					);
					await updateBadge(next.count);
				})();
			}
		});
		port.onDisconnect?.addListener?.(() => {
			console.info(TAG, `Port disconnected: ${port.name}`);
		});
	});

	browser.storage?.onChanged?.addListener((changes, areaName) => {
		if (changes.counterState) {
			const nextCount = changes.counterState.newValue?.count ?? 0;
			void updateBadge(nextCount);
			console.log(
				TAG,
				`Storage[${areaName}] count changed to:`,
				nextCount,
			);
		}
	});
});
