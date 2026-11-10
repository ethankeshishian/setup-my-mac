#!/bin/bash

# Moves the highlight dot to the focused workspace and dims empty workspaces,
# all in a single sketchybar call.

ACTIVE=0xFFFFFFFF
EMPTY=0x59FFFFFF

FOCUSED=${FOCUSED_WORKSPACE:-$(aerospace list-workspaces --focused)}
WORKSPACES=($(aerospace list-workspaces --all))
OCCUPIED=" $(aerospace list-workspaces --monitor all --empty no | tr '\n' ' ') "

ARGS=()
INDEX=0
for i in "${!WORKSPACES[@]}"; do
    sid=${WORKSPACES[$i]}
    [ "$sid" = "$FOCUSED" ] && INDEX=$i

    if [ "$sid" = "$FOCUSED" ] || [[ $OCCUPIED == *" $sid "* ]]; then
        COLOR=$ACTIVE
    else
        COLOR=$EMPTY
    fi
    ARGS+=(--set space.$sid icon.color=$COLOR --set space_ex.$sid icon.color=$COLOR)
done

PADDING=$((-(${#WORKSPACES[@]} - INDEX) * 30 + 4))

sketchybar "${ARGS[@]}" \
           --animate circ 15 --set highlight_space background.padding_left=$PADDING
