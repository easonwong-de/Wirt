import type { NativeGenericReply, RuntimeMessage } from "@/types/extension";

export function safeSendMessage<T extends NativeGenericReply>(
	message: RuntimeMessage,
): Promise<T> {
	return new Promise((resolve) => {
		try {
			logInfo("Sending runtime message:", message.type, message);
			const promise = browser.runtime.sendMessage(message) as
				Promise<T> | undefined;
			if (promise && typeof promise.then === "function") {
				promise
					.then((res: T | undefined) => {
						logInfo(
							"Received response for message:",
							message.type,
							res,
						);
						resolve(
							(res ??
								({
									status: "success",
								} as NativeGenericReply)) as T,
						);
					})
					.catch((err) => {
						const msg =
							err instanceof Error ? err.message : String(err);
						logWarn(
							"Runtime message suppressed rejection:",
							message.type,
							msg,
						);
						resolve({ error: msg } as T);
					});
			} else {
				resolve({} as T);
			}
		} catch (err) {
			const msg = err instanceof Error ? err.message : String(err);
			logWarn("Failed to invoke runtime.sendMessage:", msg);
			resolve({ error: msg } as T);
		}
	});
}
