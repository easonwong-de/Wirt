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

export interface NativeGenericReply {
	readonly status?: string;
	readonly error?: string;
	readonly extensions?: readonly ExtensionDescriptor[];
	readonly matchingExtensions?: readonly MatchingExtension[];
	readonly extensionId?: string;
	readonly name?: string;
	readonly message?: string;
}

export type NativeResponse =
	| NativeInstalledExtensionsReply
	| NativeActionClickReply
	| NativeMatchingScriptsReply
	| NativeInstallPackageReply
	| NativeOpenHostAppReply
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
			readonly payload: Record<string, string | number | boolean | null>;
	  }
	| {
			readonly type: "INSTALL_PACKAGE_FROM_URL";
			readonly downloadUrl: string;
			readonly referrer?: string;
	  }
	| {
			readonly type: "STORAGE_GET";
			readonly extensionId: string;
			readonly area: "local";
			readonly keys: readonly string[] | string;
	  }
	| {
			readonly type: "STORAGE_SET";
			readonly extensionId: string;
			readonly area: "local";
			readonly items: Record<string, string | number | boolean | null>;
	  };
