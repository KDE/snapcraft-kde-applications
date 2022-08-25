#!/bin/bash

snaps_to_watch=(
  "krita:amd64,arm64" 
  "kalzium:amd64"
  "kdenlive:amd64,arm64"
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
