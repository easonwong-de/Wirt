const LOG_TAG = "[Wirt:Content]";

export function logInfo(...args: readonly unknown[]): void {
	console.log(LOG_TAG, ...args);
}

export function logWarn(...args: readonly unknown[]): void {
	console.warn(LOG_TAG, ...args);
}

export function logError(...args: readonly unknown[]): void {
	console.error(LOG_TAG, ...args);
}
