import { join } from "node:path";
import { defineConfig } from "wxt";

const { TARGET_BUILD_DIR, UNLOCALIZED_RESOURCES_FOLDER_PATH } = process.env;

const preloadOutputDir =
	TARGET_BUILD_DIR && UNLOCALIZED_RESOURCES_FOLDER_PATH
		? join(
				TARGET_BUILD_DIR,
				UNLOCALIZED_RESOURCES_FOLDER_PATH,
				"PreloadExtensions",
				"wirt-test-extension",
			)
		: ".output/chrome-mv3";

export default defineConfig({
	modules: ["@wxt-dev/module-react", "@wxt-dev/i18n/module"],
	manifest: {
		name: "__MSG_extName__",
		description: "__MSG_extDescription__",
		version: "0.1.0",
		author: "Wirt (Debug)" as any,
		homepage_url: "https://github.com/easonwong-de/wirt",
		default_locale: "en",
		permissions: [
			"storage",
			"tabs",
			"activeTab",
			"sidePanel",
			"alarms",
			"notifications",
			"contextMenus",
			"scripting",
		],
		host_permissions: ["<all_urls>"],
		browser_specific_settings: {
			gecko: {
				id: "test-extension@wirt.dev",
			},
		},
		side_panel: {
			default_path: "sidepanel.html",
		},
		sidebar_action: {
			default_panel: "sidepanel.html",
			default_title: "Wirt Test Sidebar",
		},
	},
	outDir: preloadOutputDir,
	outDirTemplate: "",
});
