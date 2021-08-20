#!/usr/bin/env bash

dir=$(dirname $0)
parent=${dir%/*}
bash "$parent"/tuxnukem --interactive
