document.addEventListener("DOMContentLoaded", async () => {
	const listView = document.getElementById("list-view");
	const popupView = document.getElementById("popup-view");
	const listContainer = document.getElementById("extension-list");
	const appHeader = document.getElementById("app-header");
	const popupDivider = document.getElementById("popup-divider");
	const disconnectedView = document.getElementById("disconnected-view");
	const emptyView = document.getElementById("empty-view");
	const popupTitle = document.getElementById("popup-title");
	const popupFrame = document.getElementById("popup-frame");
	const btnBack = document.getElementById("btn-back");
	const btnCloseView = document.getElementById("btn-close-view");
	const btnRefresh = document.getElementById("btn-refresh");
	const btnRefreshDisconnected = document.getElementById(
		"btn-refresh-disconnected",
	);

	btnBack.addEventListener("click", showListView);
	btnCloseView.addEventListener("click", () => window.close());
	btnRefresh.addEventListener("click", () => loadExtensions());
	if (btnRefreshDisconnected) {
		btnRefreshDisconnected.addEventListener("click", () =>
			loadExtensions(),
		);
	}

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

	function showDisconnectedState() {
		appHeader.hidden = true;
		popupDivider.hidden = true;
		disconnectedView.hidden = false;
		emptyView.hidden = true;
		listContainer.hidden = true;
		listContainer.innerHTML = "";
	}

	function showEmptyState() {
		appHeader.hidden = false;
		popupDivider.hidden = false;
		disconnectedView.hidden = true;
		emptyView.hidden = false;
		listContainer.hidden = true;
		listContainer.innerHTML = "";
	}

	function showActiveList(extensions, activeTab) {
		appHeader.hidden = false;
		popupDivider.hidden = false;
		disconnectedView.hidden = true;
		emptyView.hidden = true;
		listContainer.hidden = false;
		listContainer.innerHTML = "";

		extensions.forEach((ext) => {
			const row = document.createElement("div");
			row.className = `extension-row state-${ext.actionType}`;

			let subtitle = "Click to execute action";
			if (ext.actionType === "popup") {
				subtitle = "Click to open popup";
			} else if (ext.actionType === "none") {
				subtitle = "No toolbar action";
			}

			const badgeHtml = ext.badgeText
				? `<span class="ext-action-badge" style="background:${ext.badgeColor || "#0071e3"}">${escapeHtml(ext.badgeText)}</span>`
				: "";

			row.innerHTML = `
				<div class="ext-info">
					<span class="ext-name">${escapeHtml(ext.name)}</span>
					<span class="ext-subtitle">${subtitle}</span>
				</div>
				${badgeHtml}
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
	}

	function escapeHtml(text) {
		const div = document.createElement("div");
		div.textContent = text || "";
		return div.innerHTML;
	}

	async function loadExtensions() {
		try {
			const response = await browser.runtime.sendMessage({
				type: "GET_INSTALLED_EXTENSIONS",
			});

			if (!response || response.error) {
				showDisconnectedState();
				return;
			}

			const extensions = response.extensions || [];
			if (extensions.length === 0) {
				showEmptyState();
				return;
			}

			const [activeTab] = await browser.tabs.query({
				active: true,
				currentWindow: true,
			});

			showActiveList(extensions, activeTab);
		} catch (err) {
			showDisconnectedState();
		}
	}

	await loadExtensions();
});
