barWidget.setText("—")

noctalia.runStream("exec \"$HOME/.local/libexec/waybar-fcitx-mode\"", function(line)
  if line == "中" or line == "EN" or line == "—" then
    barWidget.setText(line)
  end
end)
