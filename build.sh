#!/usr/bin/env bash

veripress theme install richardchien/veripress-theme-light --name light2

theme=`python -c "import config; print(config.THEME)"`
rm -rf ./themes/$theme/templates/custom
cp -R ./theme-custom ./themes/$theme/templates/custom

veripress generate --app-root=/
