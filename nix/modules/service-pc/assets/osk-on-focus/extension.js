import Clutter from 'gi://Clutter';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

// mutter only raises the keyboard for text-input v1 clients on a second
// enable of an already focused field, which GTK sends on a tap into a
// focused entry and Firefox never sends. The input method has no focus-in
// signal and its vfunc cannot be overridden after registration, but its
// focus-in always calls update(), so that method is wrapped on the instance.
export default class OskOnFocusExtension extends Extension {
    enable() {
        this._raised = false;

        const im = Main.inputMethod;
        const update = im.update;
        im.update = () => {
            update.call(im);
            this._raise();
        };

        im.connectObject('input-panel-state', (_im, state) => {
            if (state === Clutter.InputPanelState.OFF)
                this._raised = false;
        }, this);
    }

    disable() {
        const im = Main.inputMethod;
        im.disconnectObject(this);
        delete im.update;
        this._raised = false;
    }

    _raise() {
        if (this._raised || !Main.inputMethod.currentFocus)
            return;
        this._raised = true;
        Main.inputMethod.set_input_panel_state(Clutter.InputPanelState.ON);
    }
}
