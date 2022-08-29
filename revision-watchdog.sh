#!/bin/bash

size_warning_threshold="100" # in MiB
default_archs="amd64,arm64"

snaps_to_watch=(
  "krita" 
  "kalzium"
  "kdenlive"
  "akregator"
  "kblocks"
  "kmousetool"
  "ktuberling"
  "ark"
  "kbounce"
  "kmplot"
  "kturtle"
  "artikulate"
  "kbreakout"
  "knavalbattle"
  "kubrick"
  "blinken"
  "kbruch"
  "knetwalk"
  "kwordquiz"
  "bomber"
  "kcalc"
  "knights"
  "labplot"
  "bovo"
  "kcolorchooser"
  "kollision"
  "lokalize"
  "calligra"
  "kde-frameworks"
  "kolourpaint"
  "massif-visualizer"
  "calligraplan"
  "kompare"
  "minuet"
  "cantor"
  "kdevelop"
  "konqueror"
  "neochat"
  "cervisia"
  "kdf"
  "konquest"
  "digikam"
  "kdiamond"
  "kontact"
  "okteta"
  "kfourinline"
  "konversation"
  "okular"
  "dolphin"
  "kgeography"
  "kpat"
  "palapeli"
  "dragon"
  "kgeotag"
  "krdc"
  "parley"
  "elisa"
  "kgoldrunner"
  "kreversi"
  "peruse"
  "falkon"
  "kgraphviewer"
  "picmi"
  "gcompris-qt"
  "kid3"
  "kronometer"
  "quassel"
  "gwenview"
  "kig"
  "kruler"
  "haruna"
  "kigo"
  "kshisen"
  "rocs"
  "isoimagewriter"
  "killbots"
  "ksirk"
  "ruqola"
  "kajongg"
  "kiriki"
  "ksnakeduel"
  "skanlite"
  "kalarm"
  "kiten"
  "kspaceduel"
  "skrooge"
  "kalgebra"
  "kjumpingcube"
  "ksquares"
  "spectacle"
  "klettres"
  "kstars"
  "step"
  "kanagram"
  "klickety"
  "ksudoku"
  "subtitlecomposer"
  "kapman"
  "klines"
  "kteatime"
  "symboleditor"
  "kate"
  "kmag"
  "ktimer"
  "umbrello"
  "katomic"
  "kmahjongg"
  "ktorrent"
  "kblackbox"
  "kmines"
  "ktouch"
)

function get_snap_data {
  local snap="$1"
  local snap_data="$(curl \
    -s -f -H 'Snap-Device-Series: 16' \
    "https://api.snapcraft.io/v2/snaps/info/$snap" 2> /dev/null)"
  if [ -z "$snap_data" ]; then
    exit 1
  fi
  echo "$snap_data"
}

function get_channel_property {
  local snap_data="$1"
  local arch="$2"
  local risk="$3"
  local key="$4"
  local value="$(echo "$snap_data" | 
    jq -r ".\"channel-map\"[] | \
    select(.channel.risk==\"$risk\" and .channel.architecture==\"$arch\").$key")"
  local value=${value:-<none>}
  echo "$value"
}

function get_channel_revision {
  get_channel_property "$1" "$2" "$3" revision
}

function get_channel_version {
  get_channel_property "$1" "$2" "$3" version
}

function get_snap_size {
  get_channel_property "$1" "$2" "$3" download.size
}

need_releasing=()
size_warnings=()

echo "Checking snaps for possible candidate->stable promotions..."
echo ""

if [ ! -z "$1" ]; then
  snaps_to_watch=("$1")
fi

for snap in "${snaps_to_watch[@]}"; do
  _split=(${snap/:/ })
  snap_name="${_split[0]}"
  snap_archs="${_split[1]}"
  snap_archs="${snap_archs:-$default_archs}"
  snap_archs=(${snap_archs/,/ })
  snap_data="$(get_snap_data "$snap_name")"
  if [ $? != 0 ]; then
    echo "Could not retrieve data for snap '$snap_name'. Is it registered?" > /dev/stderr
    continue
  fi
  for arch in "${snap_archs[@]}"; do
    candidate_revision="$(get_channel_revision "$snap_data" "$arch" candidate)"
    stable_revision="$(get_channel_revision "$snap_data" "$arch" stable)"

    echo "$snap_name:$arch: { candidate: $candidate_revision, stable: $stable_revision }"
    if [ "$stable_revision" != "$candidate_revision" ]; then
      candidate_version="$(get_channel_version "$snap_data" "$arch" candidate)"
      stable_version="$(get_channel_version "$snap_data" "$arch" stable)"
      release_candidate="$snap_name $arch $candidate_revision $candidate_version"
      if [ "$candidate_version" != "$stable_version" ]; then
        release_candidate+=" yes"
      fi
      need_releasing+=("$release_candidate")
    fi

    snap_size_bytes="$(get_snap_size "$snap_data" "$arch" stable)"
    if [ "$snap_size_bytes" != "<none>" ]; then
      snap_size_mib=$((snap_size_bytes >> 20))
      if [ "$snap_size_mb" -gt "$size_warning_threshold" ]; then
        warning="$snap_name $arch $snap_size_mib"
        size_warnings+=("$warning")
      fi
    fi
  done
done

number_of_unreleased_revisions="${#need_releasing[@]}"

echo ""
echo "Candidates for testing & promotion to stable"
echo "============================================"
echo ""
echo "Date: $(date +"%Y-%m-%dT%H:%M:%S%z")"
echo "Unpromoted revisions: $number_of_unreleased_revisions"
echo ""

if [ "$number_of_unreleased_revisions" = 0 ]; then
  echo "There is nothing to do. Relax."
  exit 0
fi

separator="------------------------|--------|----------|-----------------------"

echo      "Snap                    | Arch   | Revision | Version "

prev_snap=""
for release_candidate in "${need_releasing[@]}"; do
  release_candidate=($release_candidate)
  snap_name="${release_candidate[0]}"
  snap_arch="${release_candidate[1]}"
  snap_rev="${release_candidate[2]}"
  snap_version="${release_candidate[3]}"
  version_has_changed="${release_candidate[4]}"

  if [ "$version_has_changed" = "yes" ]; then
    snap_version="$snap_version (NEW)"
  fi

  if [ "$prev_snap" != "$snap_name" ]; then
    echo "$separator"
  fi

  printf "%-23s | %-6s | %-8s | %s \n" "$snap_name" "$snap_arch" "$snap_rev" "$snap_version"
  prev_snap="$snap_name"
done

echo ""
echo "Size warnings (size > $size_warning_threshold MiB)"
echo "============================================="
echo ""
echo "Date: $(date +"%Y-%m-%dT%H:%M:%S%z")"
echo ""

separator="------------------------|--------|----------"
echo      "Snap                    | Arch   | Size "

prev_snap=""
for warning in "${size_warnings[@]}"; do
  warning=($warning)
  snap_name="${warning[0]}"
  snap_arch="${warning[1]}"
  snap_size_mb="${warning[2]}"

  if [ "$prev_snap" != "$snap_name" ]; then
    echo "$separator"
  fi

  printf "%-23s | %-6s | %s MiB \n" "$snap_name" "$snap_arch" "$snap_size_mb"
  prev_snap="$snap_name"
done