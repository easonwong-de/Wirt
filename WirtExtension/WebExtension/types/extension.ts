export type ActionType = "popup" | "click" | "none";

export interface ExtensionDescriptor {
	readonly id: string;
	readonly name: string;
	readonly version: string;
	readonly actionType: ActionType;
	readonly popupPath: string;
	readonly badgeText: string;
	readonly badgeColor: string;
	readonly iconUrl?: string;
}

export interface ActiveTab {
	readonly id?: number;
	readonly url?: string;
	readonly windowId?: number;
	readonly title?: string;
}

export interface MatchingScriptItem {
	readonly code: string;
	readonly path?: string;
	readonly runAt?: string;
	readonly allFrames?: boolean;
}

export interface MatchingExtension {
	readonly id: string;
	readonly styles?: readonly string[];
	readonly scripts?: readonly MatchingScriptItem[];
}

export interface NativeInstalledExtensionsReply {
	readonly extensions?: readonly ExtensionDescriptor[];
	readonly error?: string;
}

export interface NativeActionClickReply {
	readonly status: "success" | "error";
	readonly error?: string;
}

export interface NativeMatchingScriptsReply {
	readonly matchingExtensions?: readonly MatchingExtension[];
	readonly error?: string;
}

export interface NativeInstallPackageReply {
	readonly status: "success" | "error";
	readonly extensionId?: string;
	readonly name?: string;
	readonly message?: string;
	readonly error?: string;
}

export interface NativeOpenHostAppReply {
	readonly status: "success" | "error";
	readonly error?: string;
}

export interface NativePopupResourcesReply {
	readonly status: "success" | "error";
	readonly html?: string;
	readonly error?: string;
}

export interface NativeGenericReply {
	readonly status?: string;
	readonly error?: string;
	readonly extensions?: readonly ExtensionDescriptor[];
	readonly matchingExtensions?: readonly MatchingExtension[];
	readonly extensionId?: string;
	readonly name?: string;
	readonly message?: string;
	readonly data?: Record<string, unknown>;
	readonly html?: string;
}

export type NativeResponse =
	| NativeInstalledExtensionsReply
	| NativeActionClickReply
	| NativeMatchingScriptsReply
	| NativeInstallPackageReply
	| NativeOpenHostAppReply
	| NativePopupResourcesReply
	| NativeGenericReply;

export type RuntimeMessage =
	| { readonly type: "GET_INSTALLED_EXTENSIONS" }
	| {
			readonly type: "DISPATCH_ACTION_CLICK";
			readonly extensionId: string;
			readonly tab?: ActiveTab;
	  }
	| { readonly type: "OPEN_HOST_APP" }
	| { readonly type: "GET_MATCHING_SCRIPTS"; readonly url: string }
	| {
			readonly type: "RUNTIME_SEND_MESSAGE";
			readonly extensionId: string;
			readonly payload: unknown;
	  }
	| {
			readonly type: "INSTALL_PACKAGE_FROM_URL";
			readonly downloadUrl: string;
			readonly referrer?: string;
	  }
	| {
			readonly type: "STORAGE_GET";
			readonly extensionId: string;
			readonly area?: "local" | "sync";
			readonly keys?: unknown;
	  }
	| {
			readonly type: "STORAGE_SET";
			readonly extensionId: string;
			readonly area?: "local" | "sync";
			readonly items: Record<string, unknown>;
	  }
	| {
			readonly type: "STORAGE_REMOVE";
			readonly extensionId: string;
			readonly area?: "local" | "sync";
			readonly keys: readonly string[] | string;
	  }
	| {
			readonly type: "STORAGE_CLEAR";
			readonly extensionId: string;
			readonly area?: "local" | "sync";
	  }
	| {
			readonly type: "GET_POPUP_RESOURCES";
			readonly extensionId: string;
			readonly popupPath: string;
	  };
