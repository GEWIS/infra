import Clutter from 'gi://Clutter';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

// mutter only raises the keyboard for text-input v1 clients on a second
// enable of an already focused field, which GTK sends on a tap into a
// focused entry and Firefox never sends. The cursor rectangle arrives with
// every focus-in, so it stands in as the focus-in signal here.
export default class OskOnFocusExtension extends Extension {
    enable() {
        this._raised = false;
        Main.inputMethod.connectObject(
            'cursor-location-changed', () => this._raise(),
            'input-panel-state', (_im, state) => {
                if (state === Clutter.InputPanelState.OFF)
                    this._raised = false;
            },
            this);
    }

    disable() {
        Main.inputMethod.disconnectObject(this);
        this._raised = false;
    }

    _raise() {
        if (this._raised || !Main.inputMethod.currentFocus)
            return;
        this._raised = true;
        Main.inputMethod.set_input_panel_state(Clutter.InputPanelState.ON);
    }
}
