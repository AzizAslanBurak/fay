#!/bin/bash
# Fay demo videosu montajı: raw/*.mov -> fay_demo.mp4 (1920x1080, H.264 + AAC, <= 3:00)
# narration/segNN.mp3 varsa: anlatım atempo ile hızlandırılır, sondaki sessizlik kırpılır, arkasına GAP sn boşluk eklenir;
# görüntü segmenti bu süreye uydurulur (kısa görüntü: son kare dondurulur, uzun: sonu kesilir).
# music.mp3 varsa MUSIC_DB ile alta döşenir, anlatım sırasında sidechaincompress ile biraz daha kısılır.
set -euo pipefail
cd "$(dirname "$0")"
FF=/opt/homebrew/opt/ffmpeg@7/bin
[ -x "$FF/ffmpeg" ] || FF="$(dirname "$(command -v ffmpeg)")"
TMP=raw/_build
rm -rf "$TMP" && mkdir -p "$TMP"

TEMPO=1.08        # anlatım hızı
GAP=0.4           # segmentler arası anlatım boşluğu (sn)
TAIL=1.0          # son anlatımdan sonra kalan süre (sn)
MUSIC_DB=-24      # müzik kazancı (dB)
MUSIC_IN=1        # müzik fade-in (sn)
MUSIC_OUT=2       # müzik fade-out (sn)
VFADE_D=0.5       # görüntü fade (sn)

# Kırpma alanları (3024x1964 ekran kaydı üzerinde)
PAGE="2244:1516:20:428"   # Chrome sayfa alanı, MetaMask paneli açıkken (şerit + panel dışarıda)
WIDE="2984:1516:20:428"   # Chrome sayfa alanı, panel kapalıyken
DASH="3024:1656:0:308"    # seg01: kullanıcının kendi sekmesi
T3="1158:768:1024:770"    # seg03 Terminal penceresi (80x24)
T3B="1790:602:470:886"    # seg03b Terminal penceresi (125x18)
T5A="1790:885:527:943"    # seg05 Terminal penceresi, ilk konum (alt kenar Dock altında)
T5="1791:1051:548:548"    # seg05 Terminal penceresi, son konum (125x34)

# segment|kaynak|başlangıç|süre|kırpma
CLIPS="
01|seg01_dashboard|0|24.5|$DASH
02|seg02_buy|5|6.5|$WIDE
02|seg02_buy|16.5|4.5|$WIDE
02|seg02_buy|22|2.5|$PAGE
02|seg02_buy|32|3.5|$PAGE
02|seg02_buy|49.5|8|$PAGE
02|seg02b_buy|0.5|5.5|$PAGE
03|seg03_oracle|0|34|$T3
03|seg03b_oracle|0|12|$T3B
04|seg04_payout|0|7.5|$PAGE
04|seg04_payout|9|3.5|$PAGE
04|seg04_payout|20.5|2.5|$PAGE
04|seg04_payout|38|6.2|$PAGE
04|seg04_payout|47|3|$PAGE
05|seg05_tee|0|16|$T5A
05|seg05_tee|22|4|$T5
05|seg05b_guardian|1|5|$PAGE
05|seg05b_guardian|9.5|5|$PAGE
05|seg05b_guardian|15.5|6.4|$PAGE
06|seg06_outro|0.4|19.6|$PAGE
"
VF_TAIL="scale=1920:1080:force_original_aspect_ratio=decrease:flags=lanczos,pad=1920:1080:(ow-iw)/2:(oh-ih)/2:color=black,fps=30,setsar=1,format=yuv420p"
ENC="-c:v libx264 -preset medium -crf 20 -pix_fmt yuv420p"
dur() { "$FF/ffprobe" -v error -show_entries format=duration -of csv=p=0 "$1"; }

# 1) Klipleri kes, kırp, 1080p'ye getir
i=0
echo "$CLIPS" | while IFS='|' read -r seg src ss t crop; do
  [ -z "$seg" ] && continue
  i=$((i+1)); out=$(printf "%s/c%s_%02d.mp4" "$TMP" "$seg" "$i")
  "$FF/ffmpeg" -nostdin -v error -y -ss "$ss" -t "$t" -i "raw/$src.mov" -an -vf "crop=$crop,$VF_TAIL" $ENC "$out"
  echo "file '$(basename "$out")'" >> "$TMP/list$seg.txt"
done

# 2) Segmentleri birleştir, anlatıma göre süre ayarla, ses ekle
HAS_NARR=0
: > "$TMP/final.txt"
for seg in 01 02 03 04 05 06; do
  "$FF/ffmpeg" -v error -y -f concat -safe 0 -i "$TMP/list$seg.txt" -c copy "$TMP/v$seg.mp4"
  narr="narration/seg$seg.mp3"
  if [ -f "$narr" ]; then
    HAS_NARR=1
    pad=$GAP; [ "$seg" = 06 ] && pad=$TAIL
    # hızlandır, sondaki sessizliği kırp, sabit boşluk ekle
    "$FF/ffmpeg" -v error -y -i "$narr" -ar 48000 -ac 2 \
      -af "atempo=$TEMPO,areverse,silenceremove=start_periods=1:start_threshold=-45dB,areverse,apad=pad_dur=$pad" "$TMP/n$seg.wav"
    n=$(dur "$TMP/n$seg.wav")
    "$FF/ffmpeg" -v error -y -i "$TMP/v$seg.mp4" -i "$TMP/n$seg.wav" \
      -filter_complex "[0:v]tpad=stop_mode=clone:stop_duration=600[v]" \
      -map "[v]" -map 1:a -t "$n" $ENC -c:a aac -b:a 192k -ac 2 "$TMP/s$seg.mp4"
  else
    v=$(dur "$TMP/v$seg.mp4")
    "$FF/ffmpeg" -v error -y -i "$TMP/v$seg.mp4" -f lavfi -i anullsrc=r=48000:cl=stereo \
      -map 0:v -map 1:a -t "$v" -c:v copy -c:a aac -b:a 192k "$TMP/s$seg.mp4"
  fi
  echo "file 's$seg.mp4'" >> "$TMP/final.txt"
done
"$FF/ffmpeg" -v error -y -f concat -safe 0 -i "$TMP/final.txt" -c copy "$TMP/all.mp4"
D=$(dur "$TMP/all.mp4"); FO=$(echo "$D - $VFADE_D" | bc -l); MO=$(echo "$D - $MUSIC_OUT" | bc -l)

# 3) Müzik + fade
VFADE="fade=t=in:st=0:d=$VFADE_D,fade=t=out:st=$FO:d=$VFADE_D"
if [ -f music.mp3 ]; then
  MUS="[1:a]aresample=48000,volume=${MUSIC_DB}dB,afade=t=in:st=0:d=$MUSIC_IN,afade=t=out:st=$MO:d=$MUSIC_OUT[m]"
  if [ "$HAS_NARR" = 1 ]; then
    AF="$MUS;[0:a]asplit[n1][n2];[m][n1]sidechaincompress=threshold=0.03:ratio=3:attack=20:release=500[md];[n2][md]amix=inputs=2:duration=first:normalize=0[a]"
  else
    AF="$MUS;[m]anull[a]"
  fi
  "$FF/ffmpeg" -v error -y -i "$TMP/all.mp4" -stream_loop -1 -i music.mp3 \
    -filter_complex "[0:v]$VFADE[v];$AF" -map "[v]" -map "[a]" -t "$D" \
    $ENC -c:a aac -b:a 192k -movflags +faststart fay_demo.mp4
else
  "$FF/ffmpeg" -v error -y -i "$TMP/all.mp4" -vf "$VFADE" \
    $ENC -c:a aac -b:a 192k -movflags +faststart fay_demo.mp4
fi

echo "--- segment süreleri (görüntü -> son) ---"
for seg in 01 02 03 04 05 06; do printf "seg%s  %6.2f -> %6.2f sn\n" "$seg" "$(dur "$TMP/v$seg.mp4")" "$(dur "$TMP/s$seg.mp4")"; done
printf "TOPLAM %6.2f sn  |  %s  |  anlatım: %s  müzik: %s\n" "$(dur fay_demo.mp4)" "$(du -h fay_demo.mp4 | cut -f1)" \
  "$([ "$HAS_NARR" = 1 ] && echo var || echo yok)" "$([ -f music.mp3 ] && echo var || echo yok)"
echo "--- ses seviyesi (loudnorm ölçümü) ---"
"$FF/ffmpeg" -hide_banner -nostats -i fay_demo.mp4 -vn -af loudnorm=print_format=summary -f null - 2>&1 | grep -E "Input (Integrated|True Peak|LRA)"
