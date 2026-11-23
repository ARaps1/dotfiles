import { View, div } from "gpui-kit";

// Holds the frames the simulator mod writes; Herdr only refreshes images in
// folders that are mods, so this folder needs a main.js. It shows nothing.
// setup.sh copies this folder instead of linking it: Herdr resolves symlinks
// before checking that a mod writes under ~/.config/herdr-app.
export default class SimulatorScreen extends View {
  render() {
    return div();
  }
}
