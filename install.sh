#!/usr/bin/env bash
# Local push-to-talk dictation for macOS (Apple Silicon) using whisper.cpp + Hammerspoon.
#   Hold RIGHT Option  -> English
#   Hold RIGHT Command -> Hinglish (romanized)
# Usage:  ./install.sh            (English + Hinglish)
#         ./install.sh --no-hinglish
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
MODELS="$HOME/.whisper/models"
HF="https://huggingface.co/ggerganov/whisper.cpp/resolve/main"
WITH_HINGLISH=1
[[ "${1:-}" == "--no-hinglish" ]] && WITH_HINGLISH=0

say() { printf "\n\033[1;34m==> %s\033[0m\n" "$*"; }
die() { printf "\033[1;31mError: %s\033[0m\n" "$*" >&2; exit 1; }

[[ "$(uname -s)" == "Darwin" ]] || die "macOS only."
[[ "$(uname -m)" == "arm64" ]] || echo "Warning: not Apple Silicon; transcription will be slow."
command -v brew >/dev/null || die "Install Homebrew first: https://brew.sh"

say "Installing whisper.cpp, sox, Hammerspoon"
brew list whisper-cpp >/dev/null 2>&1 || brew install whisper-cpp
brew list sox         >/dev/null 2>&1 || brew install sox
[[ -d /Applications/Hammerspoon.app ]] || brew install --cask hammerspoon

mkdir -p "$MODELS"
fetch() { # url dest expected_bytes
  local have=0; [[ -f "$2" ]] && have=$(stat -f%z "$2")
  if [[ "$have" == "$3" ]]; then echo "  $(basename "$2") already present"; return; fi
  curl --http1.1 -fL -C - --retry 5 -o "$2" "$1"
}

say "Downloading English model (large-v3, ~1.1 GB)"
fetch "$HF/ggml-large-v3-q5_0.bin" "$MODELS/ggml-large-v3-q5_0.bin" 1081140203

HING="$MODELS/ggml-hinglish-apex-q8_0.bin"
if [[ $WITH_HINGLISH == 1 && ! -s "$HING" ]]; then
  say "Building Hinglish model from Oriserve/Whisper-Hindi2Hinglish-Apex (~3 GB download, ~5 min)"
  command -v uv  >/dev/null || brew install uv
  command -v git >/dev/null || die "git is required (xcode-select --install)"
  W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
  git clone -q --depth 1 https://github.com/ggml-org/whisper.cpp.git "$W/whisper.cpp"
  git clone -q --depth 1 https://github.com/openai/whisper.git       "$W/whisper"
  uv venv -q -p 3.12 "$W/.venv"
  uv pip install -q -p "$W/.venv/bin/python" torch transformers numpy safetensors huggingface_hub
  "$W/.venv/bin/python" -I -c "from huggingface_hub import snapshot_download as s; s('Oriserve/Whisper-Hindi2Hinglish-Apex', local_dir='$W/apex', allow_patterns=['*.json','*.txt','*.safetensors'])"
  # The checkpoint is bfloat16; numpy needs float32.
  sed 's/list_vars\[src\]\.squeeze()\.numpy()/list_vars[src].squeeze().float().numpy()/' \
      "$W/whisper.cpp/models/convert-h5-to-ggml.py" > "$W/convert.py"
  "$W/.venv/bin/python" -I "$W/convert.py" "$W/apex" "$W/whisper" "$W" >/dev/null
  whisper-quantize "$W/ggml-model.bin" "$HING" q8_0 >/dev/null 2>&1
  [[ -s "$HING" ]] || die "Hinglish model build failed"
fi

say "Installing Hammerspoon config"
mkdir -p "$HOME/.hammerspoon"
cp "$HERE/whisper_dictate.lua" "$HOME/.hammerspoon/whisper_dictate.lua"
INIT="$HOME/.hammerspoon/init.lua"
touch "$INIT"
if ! grep -q 'require("whisper_dictate")' "$INIT"; then
  cat >> "$INIT" <<'EOF'

-- Whisper dictation
require("hs.ipc")
hs.autoLaunch(true)
whisperDictate = require("whisper_dictate")
hs.alert.show("Dictation ready — right ⌥ English · right ⌘ Hinglish")
EOF
fi
if [[ $WITH_HINGLISH == 0 ]]; then
  # Drop the right-Command mode if the model isn't installed.
  sed -i '' '/\[54\] = {/,/^  },$/d' "$HOME/.hammerspoon/whisper_dictate.lua"
fi

say "Warming up the model (first run compiles GPU shaders)"
say_tmp="$(mktemp -d)"
/usr/bin/say -o "$say_tmp/t.aiff" "Testing dictation."
sox "$say_tmp/t.aiff" -r 16000 -c 1 "$say_tmp/t.wav"
whisper-cli -m "$MODELS/ggml-large-v3-q5_0.bin" -f "$say_tmp/t.wav" -l en -nt -np 2>/dev/null || true
rm -rf "$say_tmp"

open -a Hammerspoon
cat <<'EOF'

Done. Two one-time steps:
  1. System Settings → Privacy & Security → Accessibility → turn on Hammerspoon
     (click + and pick /Applications/Hammerspoon.app if it isn't listed).
  2. Hammerspoon menu-bar icon → Reload Config, then hold right ⌥ and speak.
     Allow the Microphone prompt the first time.

Hold right ⌥ (English) or right ⌘ (Hinglish), speak, release → text is pasted.
Add your own names/jargon to VOCAB in ~/.hammerspoon/whisper_dictate.lua.
EOF
