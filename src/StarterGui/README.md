# StarterGui (read-only copy)

Rojo does NOT sync this folder into Studio (it isn't in default.project.json), so your UI in Studio is never
overwritten. The UI lives in Studio. These files are only a copy so the code can be written against your UI.

To update the copy (with Rojo disconnected in Studio):
1. Studio: File > Download a Copy -> save as game.rbxl in the work folder
2. Terminal: rojo syncback ui.project.json --input game.rbxl
3. git add . ; git commit -m "ui copy" ; git push
