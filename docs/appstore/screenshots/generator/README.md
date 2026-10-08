# App-Store-Screenshots

Die Bilder in den Ordnern darüber sind aus dem Code nachgebaut (Farben, Texte und Tonnen-Symbole aus der App) und in den
exakten Pixelgrößen von App Store Connect gerendert.

Neu erzeugen (Linux/macOS mit Node und Playwright):

```
python3 gen.py
PW=$(npm root -g)/playwright node render.js      # Ausgabe in png/
```
