#!/bin/sh

rm -rf output-zpodfactory-*

packer build \
    --var-file="zpodfactory-builder.json" \
    --var-file="zpodfactory-0.7.2.json" \
    zpodfactory.json
