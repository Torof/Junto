// Dummy screen for the "Menu" tab — the tab's press is intercepted in
// _layout (tabPress → preventDefault → open MenuSheet), so this never renders.
export default function MenuTab() {
  return null;
}
