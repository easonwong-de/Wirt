import { join } from "node:path";
import { defineConfig } from "wxt";

const { TARGET_BUILD_DIR, UNLOCALIZED_RESOURCES_FOLDER_PATH } = process.env;

const bundleResourcesDir =
	TARGET_BUILD_DIR && UNLOCALIZED_RESOURCES_FOLDER_PATH
		? join(TARGET_BUILD_DIR, UNLOCALIZED_RESOURCES_FOLDER_PATH)
		: undefined;

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
	outDir: bundleResourcesDir,
	outDirTemplate: "",
	hooks: {
		"build:before": () => {
			if (!bundleResourcesDir) {
				throw new Error(
					"Build the web extension through Xcode; TARGET_BUILD_DIR is not set.",
				);
			}
		},
	},
});
