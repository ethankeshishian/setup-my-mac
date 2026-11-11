#!/usr/bin/env bash

cmd_etc() {
  if [ "$#" -ne 1 ] || [ "$1" != review ]; then
    warn 'usage: smm etc review'
    return 2
  fi
  smm_etc_review
}
