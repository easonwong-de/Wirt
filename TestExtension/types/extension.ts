export interface CounterState {
	readonly count: number;
	readonly lastModifiedBy:
		| "background"
		| "content"
		| "popup"
		| "options"
		| "sidepanel"
		| "initial";
	readonly lastModifiedAt: string;
}

export type CounterMessage =
	| { readonly type: "GET_COUNT" }
	| {
			readonly type: "SET_COUNT";
			readonly count: number;
			readonly source: CounterState["lastModifiedBy"];
	  }
	| {
			readonly type: "INCREMENT_COUNT";
			readonly delta?: number;
			readonly source: CounterState["lastModifiedBy"];
	  }
	| {
			readonly type: "RESET_COUNT";
			readonly source: CounterState["lastModifiedBy"];
	  }
	| { readonly type: "OPEN_OPTIONS_PAGE" }
	| { readonly type: "QUERY_TABS" }
	| {
			readonly type: "PORT_STREAM_UPDATE";
			readonly delta: number;
	  };

export interface CounterResponse {
	readonly status: "ok" | "error";
	readonly count?: number;
	readonly lastModifiedBy?: CounterState["lastModifiedBy"];
	readonly lastModifiedAt?: string;
	readonly tabsCount?: number;
	readonly runtimeId?: string;
	readonly message?: string;
}
