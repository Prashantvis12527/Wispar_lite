# Dashboard window (`Dashboard.swift`, `History.swift`)

Menu bar -> Insights… / History… / Settings… opens one window with three tabs. It is built only when opened and released on close, so idle cost stays about zero. `App` (in `main.swift`) implements the `DashboardHost` protocol so settings changed here stay in sync with the menu.

Read the file for the tab you are changing:
- `insights.md`: words per minute, total words, streak heatmap
- `history.md`: past dictations list, Copy/Delete, and where data is stored
- `settings.md`: the Settings tab
