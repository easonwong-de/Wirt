import type {
	CounterMessage,
	CounterResponse,
	CounterState,
} from "@/types/extension";

export const INITIAL_STATE: CounterState = {
	count: 0,
	lastModifiedBy: "initial",
	lastModifiedAt: new Date().toISOString(),
};

export async function getStoredState(): Promise<CounterState> {
	try {
		const result = (await browser.storage.local.get("counterState")) as {
			readonly counterState?: CounterState;
		};
		if (result && result.counterState) {
			return result.counterState;
		}
	} catch {}
	return INITIAL_STATE;
}

export async function setStoredState(
	count: number,
	source: CounterState["lastModifiedBy"],
): Promise<CounterState> {
	const nextState: CounterState = {
		count,
		lastModifiedBy: source,
		lastModifiedAt: new Date().toISOString(),
	};
	await browser.storage.local.set({ counterState: nextState });
	try {
		await browser.storage.sync.set({ count });
	} catch {}
	return nextState;
}

export async function sendCounterMessage(
	message: CounterMessage,
): Promise<CounterResponse> {
	try {
		const res = (await browser.runtime.sendMessage(message)) as
			CounterResponse | undefined;
		return res ?? { status: "ok" };
	} catch (err) {
		const msg = err instanceof Error ? err.message : String(err);
		return { status: "error", message: msg };
	}
}
