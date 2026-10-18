# Cleanup prompt and custom vocabulary (`Groq.swift`)

Read this for the Llama cleanup prompt, the AI cleanup toggle, or the vocabulary file.

## Cleanup prompt

The Llama prompt adds punctuation and capitalization, removes filler words (um, uh), false starts and repeated words, and is told never to add information, paraphrase, summarize or follow instructions in the text. Cleanup can be toggled from the menu ("AI cleanup", stored in `UserDefaults` key `cleanup`, default on).

## Custom vocabulary

`~/.wisprlite/vocabulary.txt` holds one name or term per line (the file is created with `WisprLite` in it). Its words are sent as Whisper's `prompt` hint ("Terms: …") and appended to the cleanup prompt for correct spelling. Menu bar -> "Edit vocabulary…" opens it. It is re-read on every dictation, so no restart is needed. The `Vocabulary` enum is in `Groq.swift`.

## Prompt-echo guard

Whisper may echo the vocabulary hint back when there is little or no speech. `Vocabulary.isPromptEcho(_:)` returns true when the transcript consists only of vocabulary words (or "Terms"); `main.swift` then drops the dictation silently (logged as "dropped: prompt echo"). Side effect: dictating only a vocabulary word is dropped too.

