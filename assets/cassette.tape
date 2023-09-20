Output demo.gif
# Terminal config
# Set Shell fish
Set FontSize 16
Set TypingSpeed 200ms
Set Theme "Catppuccin Macchiato"
Set Padding 16
# Install with some pretty output
Type "zap i --peers --no-logs"
Enter
Sleep 20s
Type "clear"
Enter
# Why command
Type "zap why 'react*@18'"
Enter
Sleep 8s
Type "clear"
Enter
# Dlx command
Type "zap x --package cowsay --package lolcatjs -c 'ls ./node_modules | tail -n 10 | cowsay | lolcatjs'"
Enter
Sleep 8s
Type "clear"
Enter
# Install and execute a bin
Type "zap add typescript"
Enter
Sleep 8s
Type "zap tsc --version"
Enter
Sleep 3s
Type "clear"
Enter
# Run a script
Type "zap build"
Enter
Sleep 15s
