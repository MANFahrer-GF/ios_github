# App-Store-Screenshots

Die Bilder in den Ordnern darüber sind aus dem Code nachgebaut (Farben, Texte und Tonnen-Symbole aus der App) und in den
exakten Pixelgrößen von App Store Connect gerendert.

Neu erzeugen (Linux/macOS mit Node und Playwright):

```
python3 gen.py
PW=$(npm root -g)/playwright node render.js      # Ausgabe in png/
```

Seit 2.0.3 zeigen „Übersicht“ und „Geburtstage“ echte Screenshots aus dem Simulator (Ordner `shots/`), im selben Rahmen.
Neu aufnehmen (iPhone 18 Pro und iPad Pro 13″, Statusleiste vorher mit `xcrun simctl status_bar … override --time 9:41` setzen):

```
TEST_RUNNER_TONNE_MARKETING=1 xcodebuild test -scheme "Tonne & Torte" -destination 'id=<Simulator>' \
  -only-testing:TonneUITests/TonneUITests/testMarketingScreenshots -resultBundlePath mk.xcresult
xcrun xcresulttool export attachments --path mk.xcresult --output-path mk   # marketing-*.png → shots/iphone_… bzw. ipad_…
```
Die Beispieldaten (Oma Erika wird heute 80 …) kommen aus `TonneUndTorteApp.seedDemo` (Startschalter `-demoData`, nur Debug).
