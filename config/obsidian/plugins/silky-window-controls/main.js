/*
 * Silky Window Controls — align Obsidian's traffic lights, glass surface, and window layout with Folio and Foot.
 *
 *  - Red: native close (preserves Obsidian's close handling).
 *  - Yellow: minimise to the MacShell Dock (falls back to omarchy-hyprland-window-minimize); disabled in fullscreen.
 *  - Green: single click toggles true fullscreen (matching Super+F, Folio, and Foot); right-click or press-and-hold
 *    opens the shared MacShell 2-row window layout menu (halves and corners) with live snap preview.
 *  - Titlebar empty space: double-click toggles maximised state; dragging notifies Hyprland for edge snap preview.
 *  - Compositor glass: keeps the Electron BrowserWindow background alpha at #00000000 so Hyprland blurs the
 *    translucent sidebar while the editor pane stays solid.
 *  - Unfocused dimming: toggles body.silky-window-unfocused so the traffic lights dim when inactive.
 *
 * Only active when Hyprland is running (HYPRLAND_INSTANCE_SIGNATURE); elsewhere Obsidian's own buttons are left alone.
 * Part of https://github.com/sqlsec/silky-omarchy — see docs/15-obsidian.md.
 */
"use strict";

const { Plugin, Notice } = require("obsidian");
const { execFile } = require("child_process");

const SELECTOR = ".titlebar-button-container.mod-right .titlebar-button";
const DRAG_CONTAINER = ".workspace-tab-header-container, .titlebar";
const INTERACTIVE =
  "button, input, textarea, select, a, .titlebar-button, .clickable-icon, .workspace-tab-header, .workspace-tab-header-inner, .workspace-tab-header-new-tab, .workspace-tab-header-tab-list";
const HOLD_MS = 350;
const HOLD_MOVE_PX = 6;

const toggleFullscreen = (address) =>
  `hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle", window = "address:${address}" })`;
const toggleMaximized = (address) =>
  `hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle", window = "address:${address}" })`;

function getRemote() {
  try {
    return require("@electron/remote");
  } catch (error) {
    return null;
  }
}

function mainPid() {
  const remote = getRemote();
  return remote ? remote.process.pid : process.ppid;
}

function execCmd(cmd, args) {
  return new Promise((resolve, reject) => {
    execFile(cmd, args, { timeout: 3000, maxBuffer: 8 * 1024 * 1024 }, (error, stdout) =>
      error ? reject(error) : resolve(String(stdout)),
    );
  });
}

function runHyprctl(args) {
  return execCmd("hyprctl", args);
}

function applyTransparentBackground(doc) {
  const win = doc && doc.defaultView;
  try {
    const remote = getRemote();
    const bw = win && win.electronWindow ? win.electronWindow : remote && remote.getCurrentWindow();
    if (bw && typeof bw.setBackgroundColor === "function") {
      bw.setBackgroundColor("#00000000");
    }
  } catch (error) {
    // Ignore if remote window is unavailable (e.g. during teardown).
  }
}

module.exports = class SilkyWindowControls extends Plugin {
  onload() {
    if (process.platform !== "linux" || !process.env.HYPRLAND_INSTANCE_SIGNATURE) return;

    this.docs = new Set();
    this.watch(document);
    // Popout windows have their own document and title bar.
    this.registerEvent(this.app.workspace.on("window-open", (win) => this.watch(win.doc)));
    this.registerEvent(
      this.app.workspace.on("css-change", () => {
        for (const doc of this.docs) this.reapplyAlpha(doc);
      }),
    );
  }

  onunload() {
    for (const doc of this.docs || []) {
      doc.body && doc.body.classList.remove("silky-window-unfocused");
    }
  }

  reapplyAlpha(doc) {
    applyTransparentBackground(doc);
    // Obsidian's startup-appearance IPC updates the window background colour shortly after css-change.
    const win = doc && doc.defaultView;
    if (win) {
      win.setTimeout(() => applyTransparentBackground(doc), 150);
    }
  }

  watch(doc) {
    if (!doc || this.docs.has(doc)) return;
    this.docs.add(doc);
    this.reapplyAlpha(doc);

    const win = doc.defaultView;
    const syncFocus = () => {
      if (!doc.body) return;
      doc.body.classList.toggle("silky-window-unfocused", !doc.hasFocus());
    };
    syncFocus();
    if (win) {
      this.registerDomEvent(win, "focus", syncFocus);
      this.registerDomEvent(win, "blur", syncFocus);
      this.registerDomEvent(win, "unload", () => this.docs.delete(doc));
    }

    let holdTimer = null;
    let holdStart = null;
    let holdTriggered = false;
    let suppressNextClick = false;

    const clearHold = () => {
      if (holdTimer !== null && win) {
        win.clearTimeout(holdTimer);
      }
      holdTimer = null;
      holdStart = null;
    };

    // Capture phase on the document runs before Obsidian's own onclick handlers.
    this.registerDomEvent(
      doc,
      "click",
      (event) => {
        const button = event.target instanceof Element ? event.target.closest(SELECTOR) : null;
        if (!button) return;
        if (button.classList.contains("mod-maximize")) {
          event.preventDefault();
          event.stopImmediatePropagation();
          if (suppressNextClick) {
            suppressNextClick = false;
            return;
          }
          this.dispatchWindowAction(button.ownerDocument, toggleFullscreen);
        } else if (button.classList.contains("mod-minimize")) {
          event.preventDefault();
          event.stopImmediatePropagation();
          this.minimizeWindow(button.ownerDocument);
        }
      },
      { capture: true },
    );

    // Right-click on the green light opens the shared MacShell window layout menu.
    this.registerDomEvent(
      doc,
      "contextmenu",
      (event) => {
        const button = event.target instanceof Element ? event.target.closest(SELECTOR) : null;
        if (!button || !button.classList.contains("mod-maximize")) return;
        event.preventDefault();
        event.stopImmediatePropagation();
        clearHold();
        this.openLayoutMenu(button);
      },
      { capture: true },
    );

    // Press-and-hold on the green light opens the same layout menu without firing click on release.
    this.registerDomEvent(
      doc,
      "pointerdown",
      (event) => {
        if (event.button !== 0) return;
        const button = event.target instanceof Element ? event.target.closest(SELECTOR) : null;
        if (button && button.classList.contains("mod-maximize")) {
          clearHold();
          holdTriggered = false;
          holdStart = { x: event.clientX, y: event.clientY };
          if (win) {
            holdTimer = win.setTimeout(() => {
              holdTimer = null;
              holdTriggered = true;
              suppressNextClick = true;
              this.openLayoutMenu(button);
            }, HOLD_MS);
          }
          return;
        }

        // Empty titlebar / tab-header space: notify Hyprland so edge-drag snap preview activates.
        const target = event.target instanceof Element ? event.target : null;
        if (target && target.closest(DRAG_CONTAINER) && !target.closest(INTERACTIVE)) {
          runHyprctl(["eval", `o.silky_folio_begin_drag(${mainPid()})`]).catch(() => {});
        }
      },
      { capture: true },
    );

    this.registerDomEvent(
      doc,
      "pointermove",
      (event) => {
        if (!holdStart || holdTimer === null) return;
        if (Math.hypot(event.clientX - holdStart.x, event.clientY - holdStart.y) > HOLD_MOVE_PX) {
          clearHold();
        }
      },
      { capture: true },
    );

    const endHold = () => {
      clearHold();
      if (holdTriggered && win) {
        holdTriggered = false;
        win.setTimeout(() => {
          suppressNextClick = false;
        }, 120);
      }
    };
    this.registerDomEvent(doc, "pointerup", endHold, { capture: true });
    this.registerDomEvent(doc, "pointercancel", endHold, { capture: true });

    // Double-click empty titlebar space toggles maximised state.
    this.registerDomEvent(
      doc,
      "dblclick",
      (event) => {
        if (event.button !== 0) return;
        const target = event.target instanceof Element ? event.target : null;
        if (!target || !target.closest(DRAG_CONTAINER) || target.closest(INTERACTIVE)) return;
        event.preventDefault();
        event.stopImmediatePropagation();
        this.dispatchWindowAction(doc, toggleMaximized);
      },
      { capture: true },
    );
  }

  async findClient(doc) {
    const pid = mainPid();
    const clients = JSON.parse(await runHyprctl(["clients", "-j"])).filter((c) => c.pid === pid);
    const client = clients.find((c) => c.title === doc.title) || (clients.length === 1 ? clients[0] : null);
    if (!client) throw new Error("this window is not in hyprctl clients");
    return client;
  }

  async dispatchWindowAction(doc, makeDispatcher) {
    try {
      const client = await this.findClient(doc);
      const out = (await runHyprctl(["dispatch", makeDispatcher(client.address)])).trim();
      if (out && out !== "ok") throw new Error(out);
    } catch (error) {
      new Notice(`Silky Window Controls: ${error.message}`);
    }
  }

  async minimizeWindow(doc) {
    try {
      const client = await this.findClient(doc);
      if ((client.fullscreen || 0) >= 2) return;
      try {
        const out = (await execCmd("qs", ["-c", "MacShell", "ipc", "call", "window", "minimizeFoot", client.address])).trim();
        if (out === "true") return;
      } catch (error) {
        // Fall through to Omarchy's built-in minimize helper.
      }
      await execCmd("omarchy-hyprland-window-minimize", [client.address]);
    } catch (error) {
      new Notice(`Silky Window Controls: ${error.message}`);
    }
  }

  async openLayoutMenu(button) {
    try {
      const doc = button.ownerDocument;
      const client = await this.findClient(doc);
      const monitors = JSON.parse(await runHyprctl(["monitors", "-j"]));
      const monitor = monitors.find((m) => m.id === client.monitor) || monitors[0];
      if (!monitor) throw new Error("no active monitor");
      const rect = button.getBoundingClientRect();
      const x = Math.round(client.at[0] + rect.left + rect.width / 2);
      const y = Math.round(client.at[1] + rect.bottom + 4);
      await runHyprctl([
        "eval",
        `o.silky_foot_menu(${JSON.stringify(client.address)}, ${JSON.stringify(monitor.name)}, ${x}, ${y})`,
      ]);
    } catch (error) {
      new Notice(`Silky Window Controls: ${error.message}`);
    }
  }
};
