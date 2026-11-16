#!/bin/bash
# 操作動画を1本撮る。Release ビルドの Kakiire を起動し、act でマウスを動かしながら画面を録画する。
# 使い方: take.sh <画像> <出力.mp4> <書き入れる文字> [en]
# 撮っているあいだ(30 秒ほど)はマウスに触らない。手順は README.md。
set -eu
D=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$D/../.." && pwd)
IMG="$1"; OUT="$2"; LABEL="$3"; LANG_OPT="${4:-}"
APP="$ROOT/build/DerivedData/Build/Products/Release/Kakiire.app"
ACT="$ROOT/build/demo-video/act"
WX=620; WY=110                  # Kakiire ウインドウの左上(画面の座標)
REGION="crop=1742:980:600:100"  # 撮る範囲(16:9)。ウインドウの右に、持ち出し先のデスクトップを残す
DROPPED="$HOME/Desktop/$(basename "$IMG")"

if [ ! -x "$ACT" ] || [ "$D/act.swift" -nt "$ACT" ]; then
  mkdir -p "$(dirname "$ACT")"
  swiftc -O "$D/act.swift" -o "$ACT"
fi

pkill -f 'Release/Kakiire.app/Contents/MacOS/Kakiire' || true
rm -f "$DROPPED"
sleep 1
if [ "$LANG_OPT" = en ]; then
  open -n -a "$APP" "$IMG" --args -AppleLanguages '(en)' -AppleLocale en_US -ApplePersistenceIgnoreState YES -showsGrid NO
else
  open -n -a "$APP" "$IMG" --args -ApplePersistenceIgnoreState YES -showsGrid NO
fi
sleep 2.5
PID=$(pgrep -f 'Release/Kakiire.app/Contents/MacOS/Kakiire')
osascript -e "tell application \"System Events\" to tell (first process whose unix id is $PID)" -e "set position of window 1 to {$WX, $WY}" -e 'set frontmost to true' -e 'end tell'
# 道具は前回の選択が残るので選択ツールに戻し、カーソルを画像の上に置いておく
"$ACT" $WX $WY click 19 56 move 1000 560 300
sleep 0.8

ffmpeg -hide_banner -loglevel error -f avfoundation -framerate 60 -capture_cursor 1 -i "0:none" \
  -vf "$REGION" -c:v libx264 -preset veryfast -crf 12 -pix_fmt yuv420p -y "$OUT" </dev/null &
FF=$!
sleep 1.5

# 座標はウインドウの左上から。道具の列は x=19(選択 56・矢印 86・四角 146・文字 206・スタンプ 326・モザイク 356・持ち出し 778)
"$ACT" $WX $WY \
  wait 600 \
  click 19 86 wait 250 drag 700 728 516 640 800 wait 700 \
  click 19 206 wait 250 click 714 702 wait 300 type "$LABEL" wait 250 esc wait 700 \
  click 19 146 wait 250 drag 352 350 768 402 800 wait 600 \
  click 19 356 wait 250 drag 368 356 600 392 800 wait 700 \
  click 19 326 wait 250 click 800 376 wait 450 click 358 602 wait 700 \
  click 19 56 wait 250 drag 790 722 812 732 500 wait 300 esc wait 700 \
  drag 19 778 1630 390 1500 wait 2200

kill -INT $FF; wait $FF || true
pkill -f 'Release/Kakiire.app/Contents/MacOS/Kakiire' || true
rm -f "$DROPPED"
