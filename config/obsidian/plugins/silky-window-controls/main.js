/*
 * Silky Window Controls — make Obsidian's traffic lights behave like Silky's hyprbars title bars on Hyprland.
 *
 * Omarchy suppresses maximise requests from every window (default/hypr/windows.lua), and Electron keeps its own
 * "maximised" flag that drifts from Hyprland's, so Obsidian's green button did nothing. Here the green button runs the
 * same dispatcher as Super+Alt+F ("Full width"), aimed at this Obsidian window: Hyprland's client list is matched by
 * Obsidian's main process id and the window title, so a click never resizes some other focused window. The
 * minimise light does nothing, because there is no minimise in this setup (see docs/02-macshell.md).
 *
 * Only active when Hyprland is running (HYPRLAND_INSTANCE_SIGNATURE); elsewhere Obsidian's own buttons are left alone.
 * Part of https://github.com/sqlsec/silky-omarchy — see docs/15-obsidian.md.
 */
"use strict";

const { Plugin, Notice } = require("obsidian");
const { execFile } = require("child_process");

const fullWidth = (address) =>
  `hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle", window = "address:${address}" })`;

function mainPid() {
  try {
    return require("@electron/remote").process.pid;
  } catch (error) {
    return process.ppid;
  }
}

function run(args) {
  return new Promise((resolve, reject) => {
    execFile("hyprctl", args, { timeout: 3000, maxBuffer: 8 * 1024 * 1024 }, (error, stdout) =>
      error ? reject(error) : resolve(String(stdout)),
    );
  });
}

const SELECTOR = ".titlebar-button-container.mod-right .titlebar-button";

module.exports = class SilkyWindowControls extends Plugin {
  onload() {
    if (process.platform !== "linux" || !process.env.HYPRLAND_INSTANCE_SIGNATURE) return;

    this.watch(document);
    // Popout windows have their own document and title bar.
    this.registerEvent(this.app.workspace.on("window-open", (win) => this.watch(win.doc)));
  }

  watch(doc) {
    // Capture phase on the document runs before the buttons' own onclick, so Obsidian never sees the click.
    this.registerDomEvent(
      doc,
      "click",
      (event) => {
        const button = event.target instanceof Element ? event.target.closest(SELECTOR) : null;
        if (!button) return;
        if (button.classList.contains("mod-maximize")) {
          event.preventDefault();
          event.stopImmediatePropagation();
          this.toggleFullWidth(button.ownerDocument);
        } else if (button.classList.contains("mod-minimize")) {
          event.preventDefault();
          event.stopImmediatePropagation();
        }
      },
      { capture: true },
    );
  }

  async toggleFullWidth(doc) {
    try {
      const pid = mainPid();
      const clients = JSON.parse(await run(["clients", "-j"])).filter((c) => c.pid === pid);
      const client = clients.find((c) => c.title === doc.title) || (clients.length === 1 ? clients[0] : null);
      if (!client) throw new Error("this window is not in hyprctl clients");
      const out = (await run(["dispatch", fullWidth(client.address)])).trim();
      if (out && out !== "ok") throw new Error(out);
    } catch (error) {
      new Notice(`Silky Window Controls: ${error.message}`);
    }
  }
};
