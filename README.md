# Whisper Dictation (macOS)

Local, offline push-to-talk dictation that types into any app.

| Hold | Language | Example output |
|---|---|---|
| Right ⌥ Option | English | "Can you check the deploy? Is it stuck?" |
| Right ⌘ Command | Hinglish (romanized) | "Haan, main keh raha tha ki deploy check karo." |

Release the key and the text is pasted into whatever field is focused (~1–2 s). Your clipboard is restored afterwards. Quick taps and ⌘/⌥ shortcuts are ignored.

## Install

Needs an Apple Silicon Mac, [Homebrew](https://brew.sh), ~5 GB free during setup (~2 GB after).

```bash
cd whisper-dictation
chmod +x install.sh
./install.sh                # or ./install.sh --no-hinglish (skips the ~3 GB Hinglish build)
```

Then:
1. **System Settings → Privacy & Security → Accessibility** → turn on **Hammerspoon** (use **+** if it isn't listed).
2. Hammerspoon menu-bar icon → **Reload Config**.
3. Hold right ⌥, speak, release. Allow the **Microphone** prompt the first time.

It starts automatically at login.

## Customise

Edit `~/.hammerspoon/whisper_dictate.lua`, then Reload Config:
- `VOCAB` — names and jargon to spell correctly.
- `MODES` — change keys (61 = right ⌥, 54 = right ⌘) or models.

## Uninstall

```bash
rm -rf ~/.whisper ~/.hammerspoon/whisper_dictate.lua
brew uninstall --cask hammerspoon && brew uninstall whisper-cpp sox
```

## Credits

[whisper.cpp](https://github.com/ggml-org/whisper.cpp), [OpenAI Whisper large-v3](https://huggingface.co/openai/whisper-large-v3), [Oriserve Whisper-Hindi2Hinglish-Apex](https://huggingface.co/Oriserve/Whisper-Hindi2Hinglish-Apex), [Hammerspoon](https://www.hammerspoon.org).
