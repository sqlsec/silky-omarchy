// Silky Omarchy: keep WeChat's pinyin in its candidate bar instead of inline (docs/09-wowtype-glass.md).
//
// WeChat bundles an fcitx5-qt client that draws the candidate bar itself as a Wayland xdg_popup.
// That client cannot move a popup in place, so it unmaps and remaps the popup whenever the anchor
// (the text cursor) moves. With inline preedit the cursor moves on every keystroke, and the bar
// blinks. With preedit shown in the bar instead, the cursor stays put and the bar is only redrawn.
#include <memory>
#include <vector>

#include <fcitx/addonfactory.h>
#include <fcitx/addoninstance.h>
#include <fcitx/addonmanager.h>
#include <fcitx/event.h>
#include <fcitx/inputcontext.h>
#include <fcitx/instance.h>

namespace {

bool isWeChatClientPanel(const fcitx::InputContext *ic) {
    // Only WeChat's bundled D-Bus client draws its own panel; its wayland_v2 context is left alone.
    return ic->program() == "wechat" && ic->frontendName() == "dbus";
}

class SilkyWeChatPreedit : public fcitx::AddonInstance {
public:
    explicit SilkyWeChatPreedit(fcitx::Instance *instance) {
        auto apply = [](fcitx::Event &event) {
            auto *ic = static_cast<fcitx::InputContextEvent &>(event).inputContext();
            if (isWeChatClientPanel(ic) && ic->isPreeditEnabled()) {
                ic->setEnablePreedit(false);
            }
        };
        // FocusIn as well: a global config reload resets every context to the default.
        for (auto type : {fcitx::EventType::InputContextCreated,
                          fcitx::EventType::InputContextFocusIn}) {
            handlers_.emplace_back(instance->watchEvent(
                type, fcitx::EventWatcherPhase::PostInputMethod, apply));
        }
    }

private:
    std::vector<std::unique_ptr<fcitx::HandlerTableEntry<fcitx::EventHandler>>> handlers_;
};

class Factory : public fcitx::AddonFactory {
    fcitx::AddonInstance *create(fcitx::AddonManager *manager) override {
        return new SilkyWeChatPreedit(manager->instance());
    }
};

} // namespace

FCITX_ADDON_FACTORY(Factory)
