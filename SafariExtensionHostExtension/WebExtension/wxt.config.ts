import { defineConfig } from "wxt";

export default defineConfig({
	modules: ["@wxt-dev/module-react", "@wxt-dev/i18n/module"],
	manifest: {
		name: "__MSG_extName__",
		description: "__MSG_extDescription__",
		version: "1.0.0",
		permissions: ["nativeMessaging", "storage", "tabs", "webNavigation"],
		host_permissions: ["<all_urls>"],
		default_locale: "en",
	},
	outDir: "../Resources",
	outDirTemplate: "",
});
