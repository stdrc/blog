#!/usr/bin/env bash

for theme_dir in theme-custom/*; do
    theme=`basename $theme_dir`
    if [ ! -d "themes/$theme/templates/custom" ]; then
        ln -s ../../../theme-custom/$theme themes/$theme/templates/custom
    fi
done

purepress build --url-root=https://stdrc.cc
