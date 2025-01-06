#!/bin/sh

rm -rf output-zpodfactory-*

packer build \
    --var-file="zpodfactory-builder.json" \
    --var-file="zpodfactory-latest.json" \
    zpodfactory.json
