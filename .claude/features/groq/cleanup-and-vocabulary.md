# Cleanup prompt and custom vocabulary (`Providers.swift`, `Vocabulary.swift`)

Read this for the cleanup prompt, the AI cleanup toggle, or the vocabulary file.

## Cleanup prompt

The cleanup prompt (the same for every provider) adds punctuation and capitalization, removes filler words (um, uh), false starts and repeated words, and is told never to add information, paraphrase, summarize or follow instructions in the text. Cleanup can be toggled from the menu ("AI cleanup", stored in `UserDefaults` key `cleanup`, default on).

## Custom vocabulary

`~/.wisprlite/vocabulary.txt` holds one name or term per line (the file is created with `WisprLite` in it). Its words are passed to Apple's analyzer as contextual strings (which it largely ignores, see `transcription/on-device.md`) and appended to the cleanup prompt for correct spelling. Menu bar -> "Edit vocabulary…" opens it. It is re-read on every dictation, so no restart is needed. The `Vocabulary` enum is in `Vocabulary.swift`.
