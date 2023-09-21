Output demo.gif

# Terminal config

Set Shell fish
Set FontSize 14
Set TypingSpeed 200ms
Set Theme "MaterialDarker"
Set Padding 16

# Install packages

Type "zap i --peers --no-logs # cold install - no cache, lockfile or node modules"
Enter
Sleep 25s
Type "clear"
Enter

Type "rm -Rf node_modules"
Enter
Sleep 5s
Type "zap i # with lockfile and without node modules"
Enter
Sleep 10s
Type "clear"
Enter

Type "rm .zap-lock.yml"
Enter
Sleep 3s
Type "zap i # with node modules and without lockfile"
Enter
Sleep 10s
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
Type "zap rm typescript"
Enter
Sleep 5s
Type "clear"
Enter

# Run a script

Type "zap build"
Enter
Sleep 15s
