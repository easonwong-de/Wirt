document.addEventListener("DOMContentLoaded", async () => {
	const listView = document.getElementById("list-view");
	const popupView = document.getElementById("popup-view");
	const listContainer = document.getElementById("extension-list");
	const countLabel = document.getElementById("extension-count");
	const popupTitle = document.getElementById("popup-title");
	const popupFrame = document.getElementById("popup-frame");
	const btnBack = document.getElementById("btn-back");
	const btnCloseView = document.getElementById("btn-close-view");
	const btnSettings = document.getElementById("btn-settings");

	btnBack.addEventListener("click", showListView);
	btnCloseView.addEventListener("click", () => window.close());
	btnSettings.addEventListener("click", () => {
		browser.runtime.sendNativeMessage("application.id", {
			action: "openSettings",
		});
	});

	function showListView() {
		popupFrame.src = "about:blank";
		popupView.hidden = true;
		listView.hidden = false;
	}

	function showPopupView(ext) {
		listView.hidden = true;
		popupView.hidden = false;
		popupTitle.textContent = ext.name;
		popupFrame.src = `ext-ui://${ext.id}/${ext.popupPath}`;
	}

	async function loadExtensions() {
		listContainer.innerHTML = "";
		try {
			const response = await browser.runtime.sendMessage({
				type: "GET_INSTALLED_EXTENSIONS",
			});
			const extensions = response?.extensions || [];
			const [activeTab] = await browser.tabs.query({
				active: true,
				currentWindow: true,
			});

			countLabel.textContent = `${extensions.length} extension${extensions.length === 1 ? "" : "s"} loaded`;

			if (extensions.length === 0) {
				listContainer.innerHTML =
					'<div style="padding:20px;text-align:center;color:var(--secondary-text)">No extensions installed yet.<br><br>Download a .crx or .xpi in Safari to install.</div>';
				return;
			}

			extensions.forEach((ext) => {
				const row = document.createElement("div");
				row.className = `extension-row state-${ext.actionType}`;

				let subtitle = "Click to execute action";
				if (ext.actionType === "popup") {
					subtitle = "Click to open popup";
				} else if (ext.actionType === "none") {
					subtitle = "No toolbar action";
				}

				row.innerHTML = `
          <div class="ext-info">
            <span class="ext-name">${ext.name}</span>
            <span class="ext-subtitle">${subtitle}</span>
          </div>
          ${ext.badgeText ? `<span class="ext-action-badge" style="background:${ext.badgeColor || "#0071e3"}">${ext.badgeText}</span>` : ""}
        `;

				if (ext.actionType === "popup") {
					row.addEventListener("click", () => showPopupView(ext));
				} else if (ext.actionType === "click") {
					row.addEventListener("click", async () => {
						await browser.runtime.sendMessage({
							type: "DISPATCH_ACTION_CLICK",
							extensionId: ext.id,
							tab: activeTab,
						});
						window.close();
					});
				}
				listContainer.appendChild(row);
			});
		} catch (err) {
			listContainer.innerHTML = `<div style="padding:16px;color:#d70015">Failed to query extensions: ${err.message}</div>`;
		}
	}

	await loadExtensions();
});
