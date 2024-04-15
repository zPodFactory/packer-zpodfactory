#!/bin/sh

rm -rf output-zpodfactory-*

packer build \
    --var-file="zpodfactory-builder.json" \
    --var-file="zpodfactory-0.5.0.json" \
    zpodfactory.json
