#!/bin/bash
/Users/jasonzhong/Library/Developer/Xcode/DerivedData/AnnoTex-ftwjtqhhqpfiqldwebptkknrjpiv/Build/Products/Debug/AnnoTex.app/Contents/MacOS/AnnoTex &
APP_PID=$!
sleep 3
osascript -e 'tell application "System Events" to tell process "AnnoTex"' -e 'click at {500, 500}' -e 'click at {500, 500}' -e 'end tell'
sleep 2
kill -9 $APP_PID
