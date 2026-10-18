# History tab and storage

- **Tab:** searchable table of past dictations with Copy and Delete per row. Delete rewrites `history.jsonl` without that entry (matched by timestamp), so it also drops out of the stats.
- **Storage:** every dictation is appended to `~/.wisprlite/history.jsonl` (`Session`: date, text, words, seconds), one JSON object per line, via `History.add` in `finishRecording`. Only read when the window is open.
- With "Save dictation text" off, `text` is empty but counts still feed the stats, and History shows nothing for those.
