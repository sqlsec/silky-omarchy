/*
 * Silky Typing — fade newly typed characters in (Obsidian editor, CodeMirror 6).
 *
 * Each typed run gets a short-lived mark decoration with the class `silky-typed`; the animation itself
 * lives in the Silky macOS theme (or styles.css next to this file when another theme is in use).
 *
 * Input methods: nothing is decorated while a composition is active, because touching the DOM around the
 * preedit text breaks Chromium's IME handling. Text inserted during the composition is tracked as a
 * pending range and animated once the composition ends, so committed Chinese text fades in as well.
 *
 * Part of https://github.com/sqlsec/silky-omarchy — see docs/15-obsidian.md.
 */
"use strict";

const { Plugin } = require("obsidian");
const { ViewPlugin, Decoration, EditorView } = require("@codemirror/view");
const { StateField, StateEffect } = require("@codemirror/state");

const LIFETIME = 260; // ms; keep a little longer than the CSS animation (220ms)
const MAX_TYPED = 8; // longer insertions (paste, snippets) are not animated
const MAX_COMPOSED = 64;

const addMarks = StateEffect.define(); // [{from, to}]
const expire = StateEffect.define(); // timestamp
const commitComposition = StateEffect.define();

let serial = 0;
function mark(now) {
  // A unique attribute stops CodeMirror from merging neighbouring marks, so earlier characters do not
  // restart their animation when the next one arrives.
  return Decoration.mark({
    class: "silky-typed",
    attributes: { "data-silky": String(++serial) },
    silkyBorn: now,
  });
}

const typingField = StateField.define({
  create() {
    return { decorations: Decoration.none, pending: null };
  },

  update(value, tr) {
    let { decorations, pending } = value;
    const now = Date.now();

    if (tr.docChanged) {
      decorations = decorations.map(tr.changes);
      if (pending) {
        const from = tr.changes.mapPos(pending.from, -1);
        const to = tr.changes.mapPos(pending.to, 1);
        pending = to > from ? { from, to } : null;
      }

      if (tr.isUserEvent("input.type.compose")) {
        tr.changes.iterChanges((_fa, _ta, fromB, toB) => {
          if (toB <= fromB) return;
          pending = pending
            ? { from: Math.min(pending.from, fromB), to: Math.max(pending.to, toB) }
            : { from: fromB, to: toB };
        });
      } else if (tr.isUserEvent("input.type")) {
        const ranges = [];
        tr.changes.iterChanges((_fa, _ta, fromB, toB) => {
          if (toB > fromB && toB - fromB <= MAX_TYPED) ranges.push({ from: fromB, to: toB });
        });
        if (ranges.length) {
          decorations = decorations.update({ add: ranges.map((r) => mark(now).range(r.from, r.to)) });
        }
      }
    }

    for (const effect of tr.effects) {
      if (effect.is(addMarks) && effect.value.length) {
        decorations = decorations.update({
          add: effect.value.map((r) => mark(now).range(r.from, r.to)),
          sort: true,
        });
      } else if (effect.is(commitComposition)) {
        if (pending && pending.to - pending.from <= MAX_COMPOSED) {
          decorations = decorations.update({ add: [mark(now).range(pending.from, pending.to)] });
        }
        pending = null;
      } else if (effect.is(expire)) {
        decorations = decorations.update({
          filter: (_from, _to, deco) => effect.value - deco.spec.silkyBorn < LIFETIME,
        });
      }
    }

    if (decorations === value.decorations && pending === value.pending) return value;
    return { decorations, pending };
  },

  provide: (field) => EditorView.decorations.from(field, (value) => value.decorations),
});

const scheduler = ViewPlugin.fromClass(
  class {
    constructor(view) {
      this.view = view;
      this.timer = null;
      this.onCompositionEnd = () => {
        // Let CodeMirror flush the final composed text first.
        setTimeout(() => {
          if (!this.view.composing && this.view.state.field(typingField, false)?.pending) {
            this.view.dispatch({ effects: commitComposition.of(null) });
          }
        }, 0);
      };
      view.contentDOM.addEventListener("compositionend", this.onCompositionEnd);
    }

    update(update) {
      const value = update.state.field(typingField, false);
      if (value && value.decorations.size && !this.timer) this.schedule();
    }

    schedule() {
      this.timer = setTimeout(() => {
        this.timer = null;
        if (this.view.composing) {
          this.schedule(); // never touch the DOM under a live preedit
          return;
        }
        const value = this.view.state.field(typingField, false);
        if (!value || !value.decorations.size) return;
        this.view.dispatch({ effects: expire.of(Date.now()) });
      }, LIFETIME);
    }

    destroy() {
      clearTimeout(this.timer);
      this.view.contentDOM.removeEventListener("compositionend", this.onCompositionEnd);
    }
  },
);

module.exports = class SilkyTyping extends Plugin {
  onload() {
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;
    this.registerEditorExtension([typingField, scheduler]);
  }
};
