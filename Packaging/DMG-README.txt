========================================================
  Aura Local — How to Install  (please read first)
========================================================

Aura Local is a local-first RAG chat app for macOS. Everything
runs on your Mac — your documents never leave your machine.

This app is distributed outside the Mac App Store and is NOT
signed with a paid Apple Developer certificate. Because of that,
macOS will block it the first time you open it. This is normal.
The steps below let you run it. You only need to do this ONCE.


--------------------------------------------------------
  STEP 1 — Install
--------------------------------------------------------

Drag the "Aura Local" icon onto the "Applications" folder
shown in this window.


--------------------------------------------------------
  STEP 2 — Try to open it (this first attempt will be blocked)
--------------------------------------------------------

Open your Applications folder and double-click "Aura Local".

macOS will show a message such as:
  "Apple could not verify 'Aura Local' is free of malware..."
  or  "'Aura Local' cannot be opened because Apple cannot
       check it for malicious software."

Click  "Done".   (Do NOT click "Move to Trash".)


--------------------------------------------------------
  STEP 3 — Allow it in System Settings
--------------------------------------------------------

1. Open the Apple menu ()  ->  System Settings
2. Click  "Privacy & Security"  in the sidebar
3. Scroll down to the "Security" section
4. You will see:  "Aura Local was blocked to protect your Mac."
5. Click the  "Open Anyway"  button next to it
6. Authenticate with Touch ID or your password
7. In the final dialog, click  "Open Anyway"  once more

Aura Local now launches — and it will open normally every
time from now on. You will not need to repeat these steps.


--------------------------------------------------------
  Shortcut for macOS 14 (Sonoma)
--------------------------------------------------------

Right-click (or Control-click) "Aura Local" in your
Applications folder, choose "Open", then click "Open" in
the dialog. That approves it in one step.


--------------------------------------------------------
  Requirements
--------------------------------------------------------

- macOS 14 (Sonoma) or later
- Ollama (https://ollama.com) and/or LM Studio (https://lmstudio.ai)
- A chat model and an embedding model
  (bge-m3 via Ollama is the recommended embedding model)

On first launch, Aura Local's onboarding walks you through
picking a provider and models, then adding your documents.


--------------------------------------------------------
  Documentation & source
--------------------------------------------------------

https://github.com/srg-sphynx/AuraLocal


Optional (advanced): if you prefer the terminal, you can clear
the quarantine flag instead of using System Settings:

  xattr -dr com.apple.quarantine "/Applications/Aura Local.app"
