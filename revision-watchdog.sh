#!/bin/bash

snaps_to_watch=(
  "krita:amd64,arm64" 
  "kalzium:amd64"
  "kdenlive:amd64,arm64"
  "akregator:amd64,arm64"
  "kblocks:amd64,arm64"
  "kmousetool:amd64,arm64"
  "ktuberling:amd64,arm64"
  "ark:amd64,arm64"
  "kbounce:amd64,arm64"
  "kmplot:amd64,arm64"
  "kturtle:amd64,arm64"
  "artikulate:amd64,arm64"
  "kbreakout:amd64,arm64"
  "knavalbattle:amd64,arm64"
  "kubrick:amd64,arm64"
  "blinken:amd64,arm64"
  "kbruch:amd64,arm64"
  "knetwalk:amd64,arm64"
  "kwordquiz:amd64,arm64"
  "bomber:amd64,arm64"
  "kcalc:amd64,arm64"
  "knights:amd64,arm64"
  "labplot:amd64,arm64"
  "bovo:amd64,arm64"
  "kcolorchooser:amd64,arm64"
  "kollision:amd64,arm64"
  "lokalize:amd64,arm64"
  "calligra:amd64,arm64"
  "kde-frameworks:amd64,arm64"
  "kolourpaint:amd64,arm64"
  "massif-visualizer:amd64,arm64"
  "calligraplan:amd64,arm64"
  "kompare:amd64,arm64"
  "minuet:amd64,arm64"
  "cantor:amd64,arm64"
  "kdevelop:amd64,arm64"
  "konqueror:amd64,arm64"
  "neochat:amd64,arm64"
  "cervisia:amd64,arm64"
  "kdf:amd64,arm64"
  "konquest:amd64,arm64"
  "digikam:amd64,arm64"
  "kdiamond:amd64,arm64"
  "kontact:amd64,arm64"
  "okteta:amd64,arm64"
  "kfourinline:amd64,arm64"
  "konversation:amd64,arm64"
  "okular:amd64,arm64"
  "dolphin:amd64,arm64"
  "kgeography:amd64,arm64"
  "kpat:amd64,arm64"
  "palapeli:amd64,arm64"
  "dragon:amd64,arm64"
  "kgeotag:amd64,arm64"
  "krdc:amd64,arm64"
  "parley:amd64,arm64"
  "elisa:amd64,arm64"
  "kgoldrunner:amd64,arm64"
  "kreversi:amd64,arm64"
  "peruse:amd64,arm64"
  "falkon:amd64,arm64"
  "kgraphviewer:amd64,arm64"
  "picmi:amd64,arm64"
  "gcompris-qt:amd64,arm64"
  "kid3:amd64,arm64"
  "kronometer:amd64,arm64"
  "quassel:amd64,arm64"
  "gwenview:amd64,arm64"
  "kig:amd64,arm64"
  "kruler:amd64,arm64"
  "haruna:amd64,arm64"
  "kigo:amd64,arm64"
  "kshisen:amd64,arm64"
  "rocs:amd64,arm64"
  "isoimagewriter:amd64,arm64"
  "killbots:amd64,arm64"
  "ksirk:amd64,arm64"
  "ruqola:amd64,arm64"
  "kajongg:amd64,arm64"
  "kiriki:amd64,arm64"
  "ksnakeduel:amd64,arm64"
  "skanlite:amd64,arm64"
  "kalarm:amd64,arm64"
  "kiten:amd64,arm64"
  "kspaceduel:amd64,arm64"
  "skrooge:amd64,arm64"
  "kalgebra:amd64,arm64"
  "kjumpingcube:amd64,arm64"
  "ksquares:amd64,arm64"
  "spectacle:amd64,arm64"
  "klettres:amd64,arm64"
  "kstars:amd64,arm64"
  "step:amd64,arm64"
  "kanagram:amd64,arm64"
  "klickety:amd64,arm64"
  "ksudoku:amd64,arm64"
  "subtitlecomposer:amd64,arm64"
  "kapman:amd64,arm64"
  "klines:amd64,arm64"
  "kteatime:amd64,arm64"
  "symboleditor:amd64,arm64"
  "kate:amd64,arm64"
  "kmag:amd64,arm64"
  "ktimer:amd64,arm64"
  "umbrello:amd64,arm64"
  "katomic:amd64,arm64"
  "kmahjongg:amd64,arm64"
  "ktorrent:amd64,arm64"
  "kblackbox:amd64,arm64"
  "kmines:amd64,arm64"
  "ktouch:amd64,arm64"
)

function get_snap_data {
  local snap="$1"
  local snap_data="$(curl \
    -s -H 'Snap-Device-Series: 16' \
    "https://api.snapcraft.io/v2/snaps/info/$snap")"
  echo "$snap_data"
}

function get_channel_revision {
  local snap_data="$1"
  local arch="$2"
  local risk="$3"
  local revision="$(echo "$snap_data" | 
    jq -r ".\"channel-map\"[] | \
    select(.channel.risk==\"$risk\" and .channel.architecture==\"$arch\").revision")"
  local revision=${revision:-<none>}
  echo "$revision"
}

function get_channel_version {
  local snap_data="$1"
  local arch="$2"
  local risk="$3"
  local version="$(echo "$snap_data" | 
    jq -r ".\"channel-map\"[] | \
    select(.channel.risk==\"$risk\" and .channel.architecture==\"$arch\").version")"
  local version=${version:-<none>}
  echo "$version"
}

need_releasing=()

echo "Checking snaps for possible candidate->stable promotions..."
echo ""

for snap in "${snaps_to_watch[@]}"; do
  _split=(${snap/:/ })
  snap_name="${_split[0]}"
  snap_archs="${_split[1]}"
  snap_archs=(${snap_archs/,/ })
  snap_data="$(get_snap_data "$snap_name")"
  for arch in "${snap_archs[@]}"; do
    candidate_revision="$(get_channel_revision "$snap_data" "$arch" candidate)"
    stable_revision="$(get_channel_revision "$snap_data" "$arch" stable)"

    echo "$snap_name:$arch: { candidate: $candidate_revision, stable: $stable_revision }"
    if [ "$stable_revision" != "$candidate_revision" ]; then
      candidate_version="$(get_channel_version "$snap_data" "$arch" candidate)"
      release_candidate="$snap_name $arch $candidate_revision $candidate_version"
      need_releasing+=("$release_candidate")
    fi
  done
done

echo ""
echo "Candidates for testing & promotion to stable"
echo "============================================"
echo ""
echo "Date: $(date +"%Y-%m-%dT%H:%M:%S%z")"
echo ""

if [ "${#need_releasing[@]}" == 0 ]; then
  echo "There is nothing to do. Relax."
  exit 0
fi

echo "Snap                    | Arch   | Revision | Version      "
echo "------------------------|--------|----------|--------------"
for release_candidate in "${need_releasing[@]}"; do
  release_candidate=($release_candidate)
  printf "%-23s | %-6s | %-8s | %s \n" "${release_candidate[0]}" "${release_candidate[1]}" "${release_candidate[2]}" "${release_candidate[3]}"
done
